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

static NSDictionary *Alpha11ConfigStatus(void) {
    NSString *path = @"/var/mobile/Library/Preferences/com.modhw.ios.devices.plist";
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL exists = [fm fileExistsAtPath:path];
    if (!exists) {
        return @{@"ok":@YES, @"exists":@NO, @"parseable":@NO, @"path":path,
                 @"keyCount":@0, @"keys":@[]};
    }
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil] ?: @{};
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![plist isKindOfClass:NSDictionary.class]) {
        return @{@"ok":@YES, @"exists":@YES, @"parseable":@NO, @"path":path,
                 @"keyCount":@0, @"keys":@[], @"modifiedAt":@([attributes[NSFileModificationDate] timeIntervalSince1970])};
    }
    NSArray *keys = [[plist allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a description] localizedCaseInsensitiveCompare:[b description]];
    }];
    NSMutableArray *safeKeys = [NSMutableArray arrayWithCapacity:keys.count];
    for (id key in keys) {
        if ([key isKindOfClass:NSString.class]) [safeKeys addObject:key];
    }
    // Deliberately return key names and parse diagnostics only, never identifier values.
    return @{@"ok":@YES, @"exists":@YES, @"parseable":@YES, @"path":path,
             @"keyCount":@(safeKeys.count), @"keys":safeKeys,
             @"modifiedAt":@([attributes[NSFileModificationDate] timeIntervalSince1970])};
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
        return @{@"ok":@YES, @"service":@"iDeviceLab Rootless Core", @"version":@"0.1.4", @"port":@(kPort)};
    if ([method isEqualToString:@"GET"] && ([path isEqualToString:@"/system"] || [path isEqualToString:@"/compatibility"])) return SystemSummary();
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/apps"]) return @{@"ok":@YES, @"apps":InstalledApplications()};
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/config/status"]) return Alpha11ConfigStatus();

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
                        BOOL known = [target hasPrefix:@"/status"] || [target hasPrefix:@"/system"] || [target hasPrefix:@"/compatibility"] || [target hasPrefix:@"/apps"] || [target hasPrefix:@"/config"] || [target hasPrefix:@"/profiles"] || [target hasPrefix:@"/current"];
                        NSInteger httpStatus = !known ? 404 : ([result[@"ok"] respondsToSelector:@selector(boolValue)] && ![result[@"ok"] boolValue] ? 400 : 200);
                        Reply(client, result, (int)httpStatus);
                    } else Reply(client, @{@"ok":@NO, @"error":@"malformed request"}, 400);
                }
            }
            close(client);
        }
    }
    return 0;
}
