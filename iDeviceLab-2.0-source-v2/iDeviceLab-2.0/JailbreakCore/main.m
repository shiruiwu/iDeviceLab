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
#import <sys/stat.h>

static const int kPort = 18080;


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


static NSDictionary *AppDataContainerIndex(void) {
    NSString *root = @"/var/mobile/Containers/Data/Application";
    struct stat rootInfo = {0};
    if (lstat(root.fileSystemRepresentation, &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode))
        return @{};
    NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[];
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    for (NSString *child in children) {
        if ([child hasPrefix:@"."]) continue;
        NSString *container = [root stringByAppendingPathComponent:child];
        struct stat info = {0};
        if (lstat(container.fileSystemRepresentation, &info) != 0 || !S_ISDIR(info.st_mode)) continue;
        NSString *metadataPath = [container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        struct stat metadataInfo = {0};
        if (lstat(metadataPath.fileSystemRepresentation, &metadataInfo) != 0 || !S_ISREG(metadataInfo.st_mode)) continue;
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
        NSString *bundleID = metadata[@"MCMMetadataIdentifier"];
        if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 || bundleID.length > 255) continue;
        index[bundleID] = container;
    }
    return index;
}

static unsigned long long SafeDirectoryBytes(NSString *path) {
    struct stat rootInfo = {0};
    if (lstat(path.fileSystemRepresentation, &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode)) return 0;
    unsigned long long total = 0;
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:path]
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey, NSURLIsSymbolicLinkKey]
        options:0 errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];
    for (NSURL *url in enumerator) {
        NSNumber *isLink = nil, *isFile = nil, *size = nil;
        [url getResourceValue:&isLink forKey:NSURLIsSymbolicLinkKey error:nil];
        if (isLink.boolValue) { [enumerator skipDescendants]; continue; }
        [url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
        if (isFile.boolValue) {
            [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            total += size.unsignedLongLongValue;
        }
    }
    return total;
}

static BOOL ClearDirectDirectoryContents(NSString *container, NSString *relativePath, unsigned long long *removedBytes, NSError **error) {
    NSString *root = @"/var/mobile/Containers/Data/Application";
    NSString *canonicalContainer = container.stringByStandardizingPath;
    if (![canonicalContainer.stringByDeletingLastPathComponent isEqualToString:root] &&
        ![canonicalContainer hasPrefix:[root stringByAppendingString:@"/"]]) return NO;
    if (![canonicalContainer.stringByResolvingSymlinksInPath isEqualToString:canonicalContainer]) return NO;
    NSString *target = [canonicalContainer stringByAppendingPathComponent:relativePath];
    struct stat info = {0};
    if (lstat(target.fileSystemRepresentation, &info) != 0) {
        if (errno == ENOENT) return YES;
        return NO;
    }
    if (!S_ISDIR(info.st_mode)) return NO;
    unsigned long long before = SafeDirectoryBytes(target);
    NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:target error:error];
    if (!children) return NO;
    for (NSString *child in children) {
        if ([child isEqualToString:@"."] || [child isEqualToString:@".."] || [child containsString:@"/"]) return NO;
        NSString *candidate = [target stringByAppendingPathComponent:child];
        struct stat childInfo = {0};
        if (lstat(candidate.fileSystemRepresentation, &childInfo) != 0) return NO;
        // removeItemAtPath removes a symlink itself; it does not resolve its destination.
        if (![NSFileManager.defaultManager removeItemAtPath:candidate error:error]) return NO;
    }
    if (removedBytes) *removedBytes += before;
    return YES;
}

static NSDictionary *AppMaintenanceInventory(void) {
    NSDictionary *containers = AppDataContainerIndex();
    NSArray *installed = InstalledApplications();
    NSMutableSet *installedIDs = [NSMutableSet set];
    NSMutableArray *apps = [NSMutableArray array];
    for (NSDictionary *app in installed) {
        NSString *bundleID = app[@"bundleIdentifier"];
        if (![bundleID isKindOfClass:NSString.class]) continue;
        [installedIDs addObject:bundleID];
        NSString *container = containers[bundleID];
        unsigned long long caches = container ? SafeDirectoryBytes([container stringByAppendingPathComponent:@"Library/Caches"]) : 0;
        unsigned long long temporary = container ? SafeDirectoryBytes([container stringByAppendingPathComponent:@"tmp"]) : 0;
        [apps addObject:@{
            @"name": app[@"name"] ?: bundleID,
            @"bundleIdentifier": bundleID,
            @"version": app[@"version"] ?: @"",
            @"containerAvailable": @(container != nil),
            @"cachesBytes": @(caches),
            @"temporaryBytes": @(temporary),
            @"cleanableBytes": @(caches + temporary)
        }];
    }
    NSUInteger orphanCount = 0;
    for (NSString *bundleID in containers) if (![installedIDs containsObject:bundleID]) orphanCount++;
    return @{@"ok":@YES, @"apps":apps, @"orphanedContainerCount":@(orphanCount),
             @"scope":@"Only Library/Caches and tmp are eligible for cleanup; app documents, preferences, databases and credentials are excluded."};
}

static NSDictionary *ClearAppCaches(NSData *body) {
    if (body.length == 0 || body.length > 4096) return @{@"ok":@NO, @"error":@"invalid request body"};
    id input = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    NSString *bundleID = [input isKindOfClass:NSDictionary.class] ? input[@"bundleIdentifier"] : nil;
    if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 || bundleID.length > 255)
        return @{@"ok":@NO, @"error":@"a valid bundleIdentifier is required"};
    BOOL installed = NO;
    for (NSDictionary *app in InstalledApplications()) {
        if ([app[@"bundleIdentifier"] isEqualToString:bundleID]) { installed = YES; break; }
    }
    if (!installed) return @{@"ok":@NO, @"error":@"only currently installed applications can be selected"};
    NSString *container = AppDataContainerIndex()[bundleID];
    if (!container) return @{@"ok":@NO, @"error":@"app data container is not accessible"};
    unsigned long long removed = 0;
    NSError *error = nil;
    if (!ClearDirectDirectoryContents(container, @"Library/Caches", &removed, &error) ||
        !ClearDirectDirectoryContents(container, @"tmp", &removed, &error))
        return @{@"ok":@NO, @"error":error.localizedDescription ?: @"cache cleanup failed; inspect permissions and container state"};
    return @{@"ok":@YES, @"bundleIdentifier":bundleID, @"removedBytes":@(removed),
             @"clearedAreas":@[@"Library/Caches", @"tmp"],
             @"excludedAreas":@[@"Documents", @"Library/Preferences", @"Library/Application Support", @"Keychain", @"cloud state"]};
}

static NSDictionary *HookInstallationStatus(void) {
    NSString *directory = @"/var/jb/Library/MobileSubstrate/DynamicLibraries";
    NSString *dylib = [directory stringByAppendingPathComponent:@"mod_hw_for_ios.dylib"];
    NSString *filter = [directory stringByAppendingPathComponent:@"mod_hw_for_ios.plist"];
    return @{
        @"ok":@YES,
        @"coreServiceRunning":@YES,
        @"tweakLibraryFound":@([NSFileManager.defaultManager fileExistsAtPath:dylib]),
        @"tweakFilterFound":@([NSFileManager.defaultManager fileExistsAtPath:filter]),
        @"runtimeInjectionVerified":@NO,
        @"note":@"File presence is installation evidence only; this endpoint does not claim that a target process loaded the tweak."
    };
}

static BOOL IsSafeAlpha11ConfigValue(NSString *key, NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0 || value.length > 64) return NO;
    NSString *pattern = @"^[A-Za-z0-9 ,._/-]+$";
    if ([key isEqualToString:@"ProductVersion"])
        pattern = @"^[0-9]{1,2}(\\.[0-9]{1,2}){1,2}$";
    else if ([key isEqualToString:@"BuildVersion"])
        pattern = @"^[A-Za-z0-9]{1,32}$";
    NSPredicate *valid = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", pattern];
    return [valid evaluateWithObject:value];
}

static NSDictionary *ApplySafeAlpha11ConfigUpdate(NSData *body) {
    if (body.length == 0 || body.length > 32768)
        return @{@"ok":@NO, @"error":@"empty or oversized configuration"};
    id input = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (![input isKindOfClass:NSDictionary.class])
        return @{@"ok":@NO, @"error":@"configuration must be a JSON object"};

    NSString *path = @"/var/mobile/Library/Preferences/com.modhw.ios.devices.plist";
    struct stat pathInfo = {0};
    if (lstat(path.fileSystemRepresentation, &pathInfo) != 0 || !S_ISREG(pathInfo.st_mode))
        return @{@"ok":@NO, @"error":@"existing regular Alpha11 plist is required"};
    NSMutableDictionary *current = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (![current isKindOfClass:NSMutableDictionary.class] ||
        ![current[@"UniqueDeviceID"] isKindOfClass:NSString.class])
        return @{@"ok":@NO, @"error":@"existing plist is invalid or missing Alpha11 root schema"};

    NSSet *allowed = [NSSet setWithArray:@[
        @"HWModelStr", @"ProductVersion", @"BuildVersion", @"HardwarePlatform",
        @"ModelNumber", @"RegionInfo", @"RegionCode", @"ProductType"
    ]];
    NSMutableArray *applied = [NSMutableArray array];
    NSMutableArray *ignored = [NSMutableArray array];
    for (id rawKey in input) {
        if (![rawKey isKindOfClass:NSString.class]) continue;
        NSString *key = rawKey;
        id rawValue = input[key];
        if (![allowed containsObject:key] || ![rawValue isKindOfClass:NSString.class]) {
            [ignored addObject:key];
            continue;
        }
        NSString *value = rawValue;
        if (!IsSafeAlpha11ConfigValue(key, value)) {
            [ignored addObject:key];
            continue;
        }
        current[key] = value;
        [applied addObject:key];
    }
    if (applied.count == 0)
        return @{@"ok":@NO, @"error":@"no valid supported fields were supplied", @"ignoredKeys":ignored};

    NSData *oldData = [NSData dataWithContentsOfFile:path];
    if (!oldData)
        return @{@"ok":@NO, @"error":@"unable to read original plist for rollback backup"};
    NSString *backupPath = [path stringByAppendingString:@".idevelab-backup"];
    struct stat backupInfo = {0};
    if (lstat(backupPath.fileSystemRepresentation, &backupInfo) == 0 && !S_ISREG(backupInfo.st_mode))
        return @{@"ok":@NO, @"error":@"rollback backup path is not a regular file"};
    NSError *writeError = nil;
    if (![oldData writeToFile:backupPath options:NSDataWritingAtomic error:&writeError])
        return @{@"ok":@NO, @"error":writeError.localizedDescription ?: @"unable to create rollback backup"};
    if (chmod(backupPath.fileSystemRepresentation, S_IRUSR | S_IWUSR) != 0)
        return @{@"ok":@NO, @"error":@"unable to secure rollback backup permissions"};
    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    [NSPropertyListSerialization propertyListWithData:oldData options:NSPropertyListMutableContainersAndLeaves format:&format error:nil];
    NSData *newData = [NSPropertyListSerialization dataWithPropertyList:current format:format options:0 error:&writeError];
    if (!newData || ![newData writeToFile:path options:NSDataWritingAtomic error:&writeError])
        return @{@"ok":@NO, @"error":writeError.localizedDescription ?: @"unable to save plist"};
    return @{@"ok":@YES, @"appliedKeys":[applied sortedArrayUsingSelector:@selector(compare:)],
             @"ignoredKeys":[ignored sortedArrayUsingSelector:@selector(compare:)], @"path":path};
}

static NSDictionary *RestoreAlpha11ConfigBackup(void) {
    NSString *path = @"/var/mobile/Library/Preferences/com.modhw.ios.devices.plist";
    NSString *backupPath = [path stringByAppendingString:@".idevelab-backup"];
    struct stat targetInfo = {0}, backupInfo = {0};
    if (lstat(path.fileSystemRepresentation, &targetInfo) == 0) {
        if (!S_ISREG(targetInfo.st_mode))
            return @{@"ok":@NO, @"error":@"current Alpha11 plist is not a regular file"};
    } else if (errno != ENOENT) {
        return @{@"ok":@NO, @"error":@"unable to inspect current Alpha11 plist path"};
    }
    if (lstat(backupPath.fileSystemRepresentation, &backupInfo) != 0 || !S_ISREG(backupInfo.st_mode))
        return @{@"ok":@NO, @"error":@"no valid local rollback backup exists"};
    if (chmod(backupPath.fileSystemRepresentation, S_IRUSR | S_IWUSR) != 0)
        return @{@"ok":@NO, @"error":@"unable to secure rollback backup permissions"};
    NSData *backupData = [NSData dataWithContentsOfFile:backupPath];
    NSDictionary *backupPlist = backupData ? [NSPropertyListSerialization propertyListWithData:backupData options:NSPropertyListImmutable format:nil error:nil] : nil;
    if (![backupPlist isKindOfClass:NSDictionary.class] || ![backupPlist[@"UniqueDeviceID"] isKindOfClass:NSString.class])
        return @{@"ok":@NO, @"error":@"rollback backup is invalid or has an incompatible Alpha11 schema"};
    NSError *error = nil;
    if (![backupData writeToFile:path options:NSDataWritingAtomic error:&error])
        return @{@"ok":@NO, @"error":error.localizedDescription ?: @"unable to restore rollback backup"};
    if (chmod(path.fileSystemRepresentation, S_IRUSR | S_IWUSR) != 0)
        return @{@"ok":@NO, @"error":@"backup restored but file permissions could not be secured"};
    return @{@"ok":@YES, @"restored":@YES, @"path":path};
}

static NSDictionary *Alpha11ConfigStatus(void) {
    NSString *path = @"/var/mobile/Library/Preferences/com.modhw.ios.devices.plist";
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL exists = [fm fileExistsAtPath:path];
    NSString *backupPath = [path stringByAppendingString:@".idevelab-backup"];
    struct stat backupInfo = {0};
    BOOL backupExists = lstat(backupPath.fileSystemRepresentation, &backupInfo) == 0 && S_ISREG(backupInfo.st_mode);
    NSDictionary *backupPlist = backupExists ? [NSDictionary dictionaryWithContentsOfFile:backupPath] : nil;
    BOOL backupParseable = [backupPlist isKindOfClass:NSDictionary.class] && [backupPlist[@"UniqueDeviceID"] isKindOfClass:NSString.class];
    if (!exists) {
        return @{@"ok":@YES, @"exists":@NO, @"parseable":@NO, @"path":path,
                 @"keyCount":@0, @"keys":@[], @"backupExists":@(backupExists), @"backupParseable":@(backupParseable)};
    }
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil] ?: @{};
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![plist isKindOfClass:NSDictionary.class]) {
        return @{@"ok":@YES, @"exists":@YES, @"parseable":@NO, @"path":path,
                 @"keyCount":@0, @"keys":@[], @"backupExists":@(backupExists), @"backupParseable":@(backupParseable), @"modifiedAt":@([attributes[NSFileModificationDate] timeIntervalSince1970])};
    }
    NSArray *keys = [[plist allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a description] localizedCaseInsensitiveCompare:[b description]];
    }];
    NSMutableArray *safeKeys = [NSMutableArray arrayWithCapacity:keys.count];
    for (id key in keys) {
        if ([key isKindOfClass:NSString.class]) [safeKeys addObject:key];
    }
    // The Alpha11 loader requires this root key; report presence/type only, never its value.
    BOOL schemaCompatible = [plist[@"UniqueDeviceID"] isKindOfClass:NSString.class];
    // Deliberately return key names and diagnostics only, never identifier values.
    return @{@"ok":@YES, @"exists":@YES, @"parseable":@YES, @"schemaCompatible":@(schemaCompatible), @"path":path,
             @"keyCount":@(safeKeys.count), @"keys":safeKeys,
             @"backupExists":@(backupExists), @"backupParseable":@(backupParseable),
             @"modifiedAt":@([attributes[NSFileModificationDate] timeIntervalSince1970])};
}

static NSDictionary *ProcessRequest(NSString *method, NSString *target, NSData *body) {
    NSArray *parts = [target componentsSeparatedByString:@"?"];
    NSString *path = parts.firstObject ?: @"/";
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/status"])
        return @{@"ok":@YES, @"service":@"iDeviceLab Rootless Core", @"version":@"0.1.9", @"port":@(kPort)};
    if ([method isEqualToString:@"GET"] && ([path isEqualToString:@"/system"] || [path isEqualToString:@"/compatibility"])) return SystemSummary();
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/apps"]) return @{@"ok":@YES, @"apps":InstalledApplications()};
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/maintenance/apps"]) return AppMaintenanceInventory();
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/maintenance/clear"]) return ClearAppCaches(body);
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/hooks/status"]) return HookInstallationStatus();
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/config/status"]) return Alpha11ConfigStatus();
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/config/update"]) return ApplySafeAlpha11ConfigUpdate(body);
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/config/restore"]) return RestoreAlpha11ConfigBackup();

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
                        NSData *body = nil;
                        if (headerEnd != NSNotFound && requestData.length >= headerEnd)
                            body = [requestData subdataWithRange:NSMakeRange(headerEnd, requestData.length - headerEnd)];
                        NSDictionary *result = ProcessRequest(method, target, body);
                        NSString *requestPath = [[target componentsSeparatedByString:@"?"] firstObject] ?: target;
                        BOOL known = [@[@"/status", @"/system", @"/compatibility", @"/apps", @"/maintenance/apps", @"/maintenance/clear", @"/hooks/status", @"/config/status", @"/config/update", @"/config/restore"] containsObject:requestPath];
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
