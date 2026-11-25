#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <signal.h>
#import <errno.h>
#import <string.h>
#import <math.h>
#import <sys/sysctl.h>

static NSString * const kRoot = @"/var/mobile/Library/Application Support/iDeviceLab";
static NSString * const kStore = @"/var/mobile/Library/Application Support/iDeviceLab/profiles.json";
static const int kPort = 18080;

static NSDictionary *ReadStore(void) {
    NSData *data = [NSData dataWithContentsOfFile:kStore];
    if (data.length) {
        id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if ([value isKindOfClass:NSDictionary.class]) return value;
    }
    return @{@"version": @1, @"selected": @"", @"profiles": @[]};
}

static BOOL WriteStore(NSDictionary *value) {
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:kRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
    if (error) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:&error];
    return data && !error && [data writeToFile:kStore options:NSDataWritingAtomic error:&error];
}


static NSString *SysctlString(const char *key) {
    size_t size = 0;
    if (sysctlbyname(key, NULL, &size, NULL, 0) != 0 || size == 0) return @"Unknown";
    char *value = calloc(1, size);
    if (!value) return @"Unknown";
    NSString *result = @"Unknown";
    if (sysctlbyname(key, value, &size, NULL, 0) == 0)
        result = [NSString stringWithUTF8String:value] ?: @"Unknown";
    free(value);
    return result;
}

static NSDictionary *SystemSummary(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attributes = [fm attributesOfFileSystemForPath:@"/var" error:nil] ?: @{};
    unsigned long long total = [attributes[NSFileSystemSize] unsignedLongLongValue];
    unsigned long long free = [attributes[NSFileSystemFreeSize] unsignedLongLongValue];

    // hw.cputype and hw.cpusubtype are integer sysctl values, not C strings.
    int cpuType = 0;
    int cpuSubtype = 0;
    size_t cpuTypeSize = sizeof(cpuType);
    size_t cpuSubtypeSize = sizeof(cpuSubtype);
    BOOL hasCPUType = sysctlbyname("hw.cputype", &cpuType, &cpuTypeSize, NULL, 0) == 0;
    BOOL hasCPUSubtype = sysctlbyname("hw.cpusubtype", &cpuSubtype, &cpuSubtypeSize, NULL, 0) == 0;
    NSString *architecture = hasCPUType && cpuType == 0x0100000c
        ? (hasCPUSubtype ? [NSString stringWithFormat:@"arm64 (subtype %d)", cpuSubtype] : @"arm64")
        : @"Unknown";

    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
    BOOL rootlessDetected = [fm fileExistsAtPath:@"/var/jb"];
    return @{
        @"ok": @YES,
        @"productType": SysctlString("hw.machine"),
        @"architecture": architecture,
        @"cpuType": hasCPUType ? @(cpuType) : [NSNull null],
        @"cpuSubtype": hasCPUSubtype ? @(cpuSubtype) : [NSNull null],
        @"osVersion": osVersion,
        @"rootlessDetected": @(rootlessDetected),
        @"hostname": NSProcessInfo.processInfo.hostName ?: @"",
        @"diskTotalBytes": @(total),
        @"diskFreeBytes": @(free),
        @"uptimeSeconds": @(NSProcessInfo.processInfo.systemUptime)
    };
}

static NSArray *InstalledApplications(void) {
    NSString *root = @"/var/containers/Bundle/Application";
    NSArray *containers = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[];
    NSMutableArray *apps = [NSMutableArray array];
    for (NSString *container in containers) {
        if ([container hasPrefix:@"."]) continue;
        NSString *containerPath = [root stringByAppendingPathComponent:container];
        NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:containerPath error:nil] ?: @[];
        for (NSString *child in children) {
            if (![child.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            NSString *appPath = [containerPath stringByAppendingPathComponent:child];
            NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            NSString *bundleID = info[@"CFBundleIdentifier"];
            if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0) continue;
            NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: child.stringByDeletingPathExtension;
            NSString *version = info[@"CFBundleShortVersionString"] ?: @"";
            [apps addObject:@{@"name":name, @"bundleIdentifier":bundleID, @"version":version}];
        }
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return apps;
}

static NSDictionary *ValidateAndStoreExchange(NSData *body) {
    if (body.length == 0 || body.length > 1024 * 1024) return @{@"ok":@NO, @"error":@"exchange payload must be 1 byte to 1 MiB"};
    NSError *error = nil;
    id root = [NSJSONSerialization JSONObjectWithData:body options:NSJSONReadingMutableContainers error:&error];
    if (![root isKindOfClass:NSDictionary.class]) return @{@"ok":@NO, @"error":@"invalid JSON archive"};
    NSDictionary *archive = root;
    if ([archive[@"schemaVersion"] integerValue] != 1) return @{@"ok":@NO, @"error":@"unsupported schemaVersion"};
    NSArray *profiles = [archive[@"profiles"] isKindOfClass:NSArray.class] ? archive[@"profiles"] : nil;
    NSArray *apps = [archive[@"managedApps"] isKindOfClass:NSArray.class] ? archive[@"managedApps"] : nil;
    if (!profiles.count || profiles.count > 100 || apps.count > 500) return @{@"ok":@NO, @"error":@"profile/app count is outside supported limits"};

    NSMutableSet *profileIDs = [NSMutableSet set];
    for (id value in profiles) {
        if (![value isKindOfClass:NSDictionary.class]) return @{@"ok":@NO, @"error":@"invalid profile entry"};
        NSDictionary *profile = value;
        NSString *identifier = [profile[@"id"] isKindOfClass:NSString.class] ? profile[@"id"] : @"";
        NSString *name = [profile[@"name"] isKindOfClass:NSString.class] ? [profile[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        NSNumber *lat = [profile[@"latitude"] isKindOfClass:NSNumber.class] ? profile[@"latitude"] : nil;
        NSNumber *lon = [profile[@"longitude"] isKindOfClass:NSNumber.class] ? profile[@"longitude"] : nil;
        NSNumber *battery = [profile[@"batteryPercent"] isKindOfClass:NSNumber.class] ? profile[@"batteryPercent"] : nil;
        NSNumber *memory = [profile[@"memoryGB"] isKindOfClass:NSNumber.class] ? profile[@"memoryGB"] : nil;
        NSString *testID = [profile[@"testIdentifier"] isKindOfClass:NSString.class] ? profile[@"testIdentifier"] : @"";
        if (!identifier.length || [profileIDs containsObject:identifier] || !name.length || !lat || !lon || !battery || !memory ||
            !isfinite(lat.doubleValue) || !isfinite(lon.doubleValue) || lat.doubleValue < -90 || lat.doubleValue > 90 ||
            lon.doubleValue < -180 || lon.doubleValue > 180 || battery.integerValue < 1 || battery.integerValue > 100 ||
            memory.integerValue < 1 || memory.integerValue > 64 || !testID.length) {
            return @{@"ok":@NO, @"error":@"profile validation failed"};
        }
        [profileIDs addObject:identifier];
    }

    NSMutableSet *appIDs = [NSMutableSet set];
    NSMutableSet *bundleIDs = [NSMutableSet set];
    for (id value in apps) {
        if (![value isKindOfClass:NSDictionary.class]) return @{@"ok":@NO, @"error":@"invalid managed app entry"};
        NSDictionary *app = value;
        NSString *identifier = [app[@"id"] isKindOfClass:NSString.class] ? app[@"id"] : @"";
        NSString *name = [app[@"name"] isKindOfClass:NSString.class] ? [app[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        NSString *bundle = [app[@"bundleIdentifier"] isKindOfClass:NSString.class] ? [app[@"bundleIdentifier"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        NSString *profileID = [app[@"profileID"] isKindOfClass:NSString.class] ? app[@"profileID"] : @"";
        NSString *normalizedBundle = bundle.lowercaseString;
        if (!identifier.length || [appIDs containsObject:identifier] || !name.length || !bundle.length ||
            [bundleIDs containsObject:normalizedBundle] || ![profileIDs containsObject:profileID]) {
            return @{@"ok":@NO, @"error":@"managed app validation failed"};
        }
        [appIDs addObject:identifier];
        [bundleIDs addObject:normalizedBundle];
    }

    NSString *selected = [archive[@"selectedID"] isKindOfClass:NSString.class] ? archive[@"selectedID"] : @"";
    if (selected.length && ![profileIDs containsObject:selected]) return @{@"ok":@NO, @"error":@"selected profile does not exist"};

    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *writeError = nil;
    [fm createDirectoryAtPath:kRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&writeError];
    if (writeError || ![body writeToFile:[kRoot stringByAppendingPathComponent:@"test-profile-exchange.json"] options:NSDataWritingAtomic error:&writeError]) {
        return @{@"ok":@NO, @"error":@"could not persist exchange archive"};
    }
    return @{@"ok":@YES, @"profileCount":@(profiles.count), @"managedAppCount":@(apps.count), @"selectedID":selected};
}

static NSDictionary *ProcessRequest(NSString *method, NSString *target, NSData *body) {
    NSArray *parts = [target componentsSeparatedByString:@"?"];
    NSString *path = parts.firstObject ?: @"/";
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    if (parts.count > 1) {
        for (NSString *pair in [parts[1] componentsSeparatedByString:@"&"]) {
            NSArray *kv = [pair componentsSeparatedByString:@"="];
            if (kv.count >= 2) query[kv[0]] = [kv[1] stringByRemovingPercentEncoding] ?: kv[1];
        }
    }
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/status"])
        return @{@"ok":@YES, @"service":@"iDeviceLab Rootless Core", @"version":@"0.1.2", @"port":@(kPort)};
    if ([method isEqualToString:@"GET"] && ([path isEqualToString:@"/system"] || [path isEqualToString:@"/compatibility"])) return SystemSummary();
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/apps"]) return @{@"ok":@YES, @"apps":InstalledApplications()};

    NSString *exchangePath = [kRoot stringByAppendingPathComponent:@"test-profile-exchange.json"];
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/exchange/import"])
        return ValidateAndStoreExchange(body);
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/exchange/status"]) {
        NSDictionary *archive = [NSDictionary dictionaryWithContentsOfFile:exchangePath];
        if (!archive) {
            NSData *data = [NSData dataWithContentsOfFile:exchangePath];
            id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            archive = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
        }
        if (!archive) return @{@"ok":@YES, @"synced":@NO, @"profileCount":@0, @"managedAppCount":@0};
        NSArray *profiles = [archive[@"profiles"] isKindOfClass:NSArray.class] ? archive[@"profiles"] : @[];
        NSArray *apps = [archive[@"managedApps"] isKindOfClass:NSArray.class] ? archive[@"managedApps"] : @[];
        return @{@"ok":@YES, @"synced":@YES, @"profileCount":@(profiles.count), @"managedAppCount":@(apps.count),
                 @"createdAt":archive[@"createdAt"] ?: @""};
    }

    NSDictionary *store = ReadStore();
    NSArray *profiles = store[@"profiles"] ?: @[];
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/profiles"])
        return @{@"ok":@YES, @"profiles":profiles, @"selected":store[@"selected"] ?: @""};

    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/current"]) {
        NSString *selected = store[@"selected"] ?: @"";
        for (NSDictionary *profile in profiles)
            if ([profile[@"id"] isEqualToString:selected]) return @{@"ok":@YES, @"profile":profile};
        return @{@"ok":@YES, @"profile":[NSNull null]};
    }

    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/profiles/new"]) {
        NSString *name = [query[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length || name.length > 64) return @{@"ok":@NO, @"error":@"name must contain 1-64 characters"};
        NSMutableArray *nextProfiles = [profiles mutableCopy];
        NSDictionary *entry = @{@"id":NSUUID.UUID.UUIDString, @"name":name, @"createdAt":@([NSDate date].timeIntervalSince1970)};
        [nextProfiles addObject:entry];
        NSMutableDictionary *next = [store mutableCopy];
        next[@"profiles"] = nextProfiles;
        if (!WriteStore(next)) return @{@"ok":@NO, @"error":@"could not persist profile store"};
        return @{@"ok":@YES, @"profile":entry};
    }

    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/profiles/select"]) {
        NSString *identifier = query[@"id"] ?: @"";
        BOOL found = NO;
        for (NSDictionary *profile in profiles) if ([profile[@"id"] isEqualToString:identifier]) found = YES;
        if (!found) return @{@"ok":@NO, @"error":@"profile not found"};
        NSMutableDictionary *next = [store mutableCopy];
        next[@"selected"] = identifier;
        if (!WriteStore(next)) return @{@"ok":@NO, @"error":@"could not persist selection"};
        return @{@"ok":@YES, @"selected":identifier};
    }
    return @{@"ok":@NO, @"error":@"not found"};
}

static void Reply(int fd, NSDictionary *payload, int status) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil] ?: [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *reason = status == 200 ? @"OK" : (status == 400 ? @"Bad Request" : @"Not Found");
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n", status, reason, (unsigned long)body.length];
    send(fd, header.UTF8String, strlen(header.UTF8String), 0);
    send(fd, body.bytes, body.length, 0);
}

int main(void) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        int server = socket(AF_INET, SOCK_STREAM, 0);
        if (server < 0) return 1;
        int yes = 1;
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        struct sockaddr_in addr = {0};
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(kPort);
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(server, 8) < 0) { close(server); return 2; }

        for (;;) {
            int client = accept(server, NULL, NULL);
            if (client < 0) { if (errno == EINTR) continue; sleep(1); continue; }
            NSMutableData *requestData = [NSMutableData data];
            uint8_t chunk[16384];
            ssize_t count = 0;
            NSUInteger headerEnd = NSNotFound;
            NSUInteger expectedLength = 0;
            while (requestData.length < 1024 * 1024 + 16384) {
                count = recv(client, chunk, sizeof(chunk), 0);
                if (count <= 0) break;
                [requestData appendBytes:chunk length:(NSUInteger)count];
                if (headerEnd == NSNotFound) {
                    const uint8_t separator[] = {13,10,13,10};
                    NSRange range = [requestData rangeOfData:[NSData dataWithBytes:separator length:4] options:0 range:NSMakeRange(0, requestData.length)];
                    if (range.location != NSNotFound) {
                        headerEnd = NSMaxRange(range);
                        NSData *headerData = [requestData subdataWithRange:NSMakeRange(0, range.location)];
                        NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
                        for (NSString *line in [headerText componentsSeparatedByString:@"\r\n"]) {
                            if ([line.lowercaseString hasPrefix:@"content-length:"]) {
                                expectedLength = (NSUInteger)MAX(0, [[line substringFromIndex:15] integerValue]);
                            }
                        }
                        if (expectedLength > 1024 * 1024) break;
                    }
                }
                if (headerEnd != NSNotFound && requestData.length >= headerEnd + expectedLength) break;
            }
            if (requestData.length > 0) {
                @autoreleasepool {
                    const uint8_t separator[] = {13,10,13,10};
                    NSRange range = [requestData rangeOfData:[NSData dataWithBytes:separator length:4] options:0 range:NSMakeRange(0, requestData.length)];
                    NSData *headerData = range.location != NSNotFound ? [requestData subdataWithRange:NSMakeRange(0, range.location)] : [NSData data];
                    NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
                    NSArray *lines = [headerText componentsSeparatedByString:@"\r\n"];
                    NSArray *first = lines.firstObject ? [lines.firstObject componentsSeparatedByString:@" "] : @[];
                    if (first.count >= 2 && range.location != NSNotFound) {
                        NSString *method = first[0], *target = first[1];
                        NSUInteger bodyStart = NSMaxRange(range);
                        NSUInteger available = requestData.length > bodyStart ? requestData.length - bodyStart : 0;
                        NSUInteger bodyLength = MIN(expectedLength, available);
                        NSData *body = [requestData subdataWithRange:NSMakeRange(bodyStart, bodyLength)];
                        NSDictionary *result = ProcessRequest(method, target, body);
                        BOOL known = [target hasPrefix:@"/status"] || [target hasPrefix:@"/system"] || [target hasPrefix:@"/compatibility"] || [target hasPrefix:@"/apps"] || [target hasPrefix:@"/profiles"] || [target hasPrefix:@"/current"] || [target hasPrefix:@"/exchange"];
                        Reply(client, result, known ? 200 : 404);
                    } else Reply(client, @{@"ok":@NO, @"error":@"malformed request"}, 400);
                }
            }
            close(client);
        }
    }
    return 0;
}
