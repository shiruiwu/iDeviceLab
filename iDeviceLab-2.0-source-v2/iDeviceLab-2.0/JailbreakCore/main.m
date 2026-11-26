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

static void RecordInventoryError(NSError **scanError, NSError *error, NSString *fallback) {
    if (!scanError || *scanError) return;
    *scanError = error ?: [NSError errorWithDomain:@"iDeviceLab.Inventory" code:1
        userInfo:@{NSLocalizedDescriptionKey:fallback ?: @"inventory scan was incomplete"}];
}

static NSArray *InstalledApplications(NSError **scanError) {
    NSString *root = @"/var/containers/Bundle/Application";
    struct stat rootInfo = {0};
    if (lstat(root.fileSystemRepresentation, &rootInfo) != 0) {
        int savedErrno = errno;
        RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"installed app bundle root is unavailable: %s", strerror(savedErrno)]);
        return @[];
    }
    if (!S_ISDIR(rootInfo.st_mode)) {
        RecordInventoryError(scanError, nil, @"installed app bundle root is not a real directory");
        return @[];
    }
    NSError *rootError = nil;
    NSArray *containers = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:&rootError];
    if (!containers) {
        RecordInventoryError(scanError, rootError, @"unable to enumerate installed app bundle root");
        return @[];
    }
    NSMutableArray *apps = [NSMutableArray array];
    NSMutableSet *seenBundleIDs = [NSMutableSet set];
    NSMutableSet *ambiguousBundleIDs = [NSMutableSet set];
    for (NSString *container in containers) {
        if ([container hasPrefix:@"."]) continue;
        NSString *containerPath = [root stringByAppendingPathComponent:container];
        struct stat containerInfo = {0};
        if (lstat(containerPath.fileSystemRepresentation, &containerInfo) != 0) {
            if (errno != ENOENT) RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"unable to inspect app bundle container %@", container]);
            continue;
        }
        if (!S_ISDIR(containerInfo.st_mode)) continue;
        NSError *childrenError = nil;
        NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:containerPath error:&childrenError];
        if (!children) {
            RecordInventoryError(scanError, childrenError, [NSString stringWithFormat:@"unable to enumerate app bundle container %@", container]);
            continue;
        }
        for (NSString *child in children) {
            if (![child.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            NSString *appPath = [containerPath stringByAppendingPathComponent:child];
            struct stat appInfo = {0};
            if (lstat(appPath.fileSystemRepresentation, &appInfo) != 0 || !S_ISDIR(appInfo.st_mode)) {
                RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"unable to inspect app bundle %@", child]);
                continue;
            }
            NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
            struct stat plistInfo = {0};
            if (lstat(plistPath.fileSystemRepresentation, &plistInfo) != 0 || !S_ISREG(plistInfo.st_mode)) {
                RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"app bundle %@ has no readable regular Info.plist", child]);
                continue;
            }
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            NSString *bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:NSString.class] ? info[@"CFBundleIdentifier"] : nil;
            if (bundleID.length == 0) {
                RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"app bundle %@ has no valid Bundle ID", child]);
                continue;
            }
            if ([ambiguousBundleIDs containsObject:bundleID]) continue;
            if ([seenBundleIDs containsObject:bundleID]) {
                NSUInteger existingIndex = [apps indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) {
                    return [candidate[@"bundleIdentifier"] isEqualToString:bundleID];
                }];
                if (existingIndex != NSNotFound) [apps removeObjectAtIndex:existingIndex];
                [ambiguousBundleIDs addObject:bundleID];
                RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"multiple installed app bundles claim Bundle ID %@; app selection is ambiguous", bundleID]);
                continue;
            }
            [seenBundleIDs addObject:bundleID];
            NSString *name = [info[@"CFBundleDisplayName"] isKindOfClass:NSString.class] ? info[@"CFBundleDisplayName"] :
                ([info[@"CFBundleName"] isKindOfClass:NSString.class] ? info[@"CFBundleName"] : child.stringByDeletingPathExtension);
            NSString *version = [info[@"CFBundleShortVersionString"] isKindOfClass:NSString.class] ? info[@"CFBundleShortVersionString"] : @"";
            [apps addObject:@{@"name":name, @"bundleIdentifier":bundleID, @"version":version}];
        }
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return apps;
}


static NSDictionary *AppDataContainerIndex(NSError **scanError) {
    NSString *root = @"/var/mobile/Containers/Data/Application";
    struct stat rootInfo = {0};
    if (lstat(root.fileSystemRepresentation, &rootInfo) != 0) {
        int savedErrno = errno;
        RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"app data container root is unavailable: %s", strerror(savedErrno)]);
        return @{};
    }
    if (!S_ISDIR(rootInfo.st_mode)) {
        RecordInventoryError(scanError, nil, @"app data container root is not a real directory");
        return @{};
    }
    NSError *childrenError = nil;
    NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:&childrenError];
    if (!children) {
        RecordInventoryError(scanError, childrenError, @"unable to enumerate app data containers");
        return @{};
    }
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    NSMutableSet *ambiguousBundleIDs = [NSMutableSet set];
    for (NSString *child in children) {
        if ([child hasPrefix:@"."] || [[NSUUID alloc] initWithUUIDString:child] == nil) continue;
        NSString *container = [root stringByAppendingPathComponent:child];
        struct stat info = {0};
        if (lstat(container.fileSystemRepresentation, &info) != 0) {
            if (errno != ENOENT) RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"unable to inspect app data container %@", child]);
            continue;
        }
        if (!S_ISDIR(info.st_mode)) {
            RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"app data container %@ is not a real directory", child]);
            continue;
        }
        NSString *metadataPath = [container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        struct stat metadataInfo = {0};
        if (lstat(metadataPath.fileSystemRepresentation, &metadataInfo) != 0) {
            int savedErrno = errno;
            RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"container %@ metadata is unavailable: %s", child, strerror(savedErrno)]);
            continue;
        }
        if (!S_ISREG(metadataInfo.st_mode)) {
            RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"container %@ metadata is not a regular file", child]);
            continue;
        }
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
        if (![metadata isKindOfClass:NSDictionary.class]) {
            RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"container %@ metadata is unreadable or invalid", child]);
            continue;
        }
        NSString *bundleID = [metadata[@"MCMMetadataIdentifier"] isKindOfClass:NSString.class] ? metadata[@"MCMMetadataIdentifier"] : nil;
        if (bundleID.length == 0 || bundleID.length > 255) {
            RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"container %@ metadata has no valid Bundle ID", child]);
            continue;
        }
        // Never select an arbitrary container if metadata maps one bundle ID more than once.
        if ([ambiguousBundleIDs containsObject:bundleID]) continue;
        if (index[bundleID] != nil) {
            [index removeObjectForKey:bundleID];
            [ambiguousBundleIDs addObject:bundleID];
            RecordInventoryError(scanError, nil, [NSString stringWithFormat:@"multiple app data containers claim Bundle ID %@; mapping is ambiguous", bundleID]);
            continue;
        }
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
        options:0 errorHandler:^BOOL(__unused NSURL *url, __unused NSError *error) { return YES; }];
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

static unsigned long long SafePathBytes(NSString *path, const struct stat *info) {
    if (S_ISREG(info->st_mode)) return (unsigned long long)MAX((off_t)0, info->st_size);
    if (S_ISDIR(info->st_mode)) return SafeDirectoryBytes(path);
    return 0;
}

static void SetMaintenanceError(NSError **error, NSInteger code, NSString *description) {
    if (error && !*error) *error = [NSError errorWithDomain:@"iDeviceLab.AppMaintenance" code:code
        userInfo:@{NSLocalizedDescriptionKey:description ?: @"maintenance operation failed"}];
}

static BOOL ValidateRemovalTree(NSString *path, NSString *relativePath, NSString **failedAt, NSError **error) {
    struct stat info = {0};
    if (lstat(path.fileSystemRepresentation, &info) != 0) {
        int savedErrno = errno;
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, savedErrno, [NSString stringWithFormat:@"unable to inspect %@ during cleanup preflight: %s", relativePath, strerror(savedErrno)]);
        return NO;
    }
    // A symlink is removed as a link; never traverse its destination.
    if (S_ISLNK(info.st_mode) || S_ISREG(info.st_mode)) return YES;
    if (!S_ISDIR(info.st_mode)) {
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, 19, [NSString stringWithFormat:@"unsupported special file in cleanup target: %@", relativePath]);
        return NO;
    }
    if (access(path.fileSystemRepresentation, W_OK | X_OK) != 0) {
        int savedErrno = errno;
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, savedErrno, [NSString stringWithFormat:@"directory is not writable or searchable during cleanup preflight: %@ (%s)", relativePath, strerror(savedErrno)]);
        return NO;
    }
    NSError *enumerationError = nil;
    NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:&enumerationError];
    if (!children) {
        if (failedAt) *failedAt = relativePath;
        if (error && !*error) *error = enumerationError ?: [NSError errorWithDomain:@"iDeviceLab.AppMaintenance" code:20
            userInfo:@{NSLocalizedDescriptionKey:@"unable to enumerate nested cleanup directory"}];
        return NO;
    }
    for (NSString *child in children) {
        if ([child isEqualToString:@"."] || [child isEqualToString:@".."] || [child containsString:@"/"]) {
            if (failedAt) *failedAt = relativePath;
            SetMaintenanceError(error, 21, @"nested directory enumeration returned an invalid child name");
            return NO;
        }
        NSString *candidate = [path stringByAppendingPathComponent:child];
        NSString *childRelativePath = [relativePath stringByAppendingPathComponent:child];
        if (!ValidateRemovalTree(candidate, childRelativePath, failedAt, error)) return NO;
    }
    return YES;
}

static BOOL ClearDirectDirectoryContents(NSString *container, NSString *relativePath,
    unsigned long long *removedBytes, unsigned long long *removedItems, BOOL dryRun,
    NSString **failedAt, NSError **error) {
    NSString *root = @"/var/mobile/Containers/Data/Application";
    NSString *canonicalContainer = container.stringByStandardizingPath;
    if (![canonicalContainer.stringByDeletingLastPathComponent isEqualToString:root]) {
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, 10, @"app container is not a direct child of the application data root");
        return NO;
    }
    if ([[NSUUID alloc] initWithUUIDString:canonicalContainer.lastPathComponent] == nil) {
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, 11, @"app container directory name is not a UUID");
        return NO;
    }
    if (![canonicalContainer.stringByResolvingSymlinksInPath isEqualToString:canonicalContainer]) {
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, 12, @"app container path resolves through a symbolic link");
        return NO;
    }
    if (![relativePath isEqualToString:@"Library/Caches"] && ![relativePath isEqualToString:@"tmp"]) {
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, 13, @"requested cleanup path is outside the allowed cache locations");
        return NO;
    }
    NSString *target = [[canonicalContainer stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    if (![target.stringByResolvingSymlinksInPath isEqualToString:target]) {
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, 14, @"cleanup target contains an intermediate symbolic link");
        return NO;
    }
    struct stat info = {0};
    if (lstat(target.fileSystemRepresentation, &info) != 0) {
        int savedErrno = errno;
        if (savedErrno == ENOENT) return YES;
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, savedErrno, [NSString stringWithFormat:@"unable to inspect %@: %s", relativePath, strerror(savedErrno)]);
        return NO;
    }
    if (!S_ISDIR(info.st_mode)) {
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, 15, [NSString stringWithFormat:@"%@ exists but is not a directory", relativePath]);
        return NO;
    }
    if (access(target.fileSystemRepresentation, W_OK | X_OK) != 0) {
        int savedErrno = errno;
        if (failedAt) *failedAt = relativePath;
        SetMaintenanceError(error, savedErrno, [NSString stringWithFormat:@"cleanup directory is not writable or searchable: %@ (%s)", relativePath, strerror(savedErrno)]);
        return NO;
    }
    NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:target error:error];
    if (!children) {
        if (failedAt) *failedAt = relativePath;
        if (error && !*error) SetMaintenanceError(error, 16, [NSString stringWithFormat:@"unable to enumerate %@", relativePath]);
        return NO;
    }
    for (NSString *child in children) {
        if ([child isEqualToString:@"."] || [child isEqualToString:@".."] || [child containsString:@"/"]) {
            if (failedAt) *failedAt = relativePath;
            SetMaintenanceError(error, 17, @"directory enumeration returned an invalid child name");
            return NO;
        }
        NSString *candidate = [target stringByAppendingPathComponent:child];
        struct stat childInfo = {0};
        if (lstat(candidate.fileSystemRepresentation, &childInfo) != 0) {
            int savedErrno = errno;
            if (failedAt) *failedAt = [relativePath stringByAppendingPathComponent:child];
            SetMaintenanceError(error, savedErrno, [NSString stringWithFormat:@"unable to inspect cleanup item %@: %s", child, strerror(savedErrno)]);
            return NO;
        }
        if (dryRun) {
            NSString *childRelativePath = [relativePath stringByAppendingPathComponent:child];
            if (!ValidateRemovalTree(candidate, childRelativePath, failedAt, error)) return NO;
        } else {
            unsigned long long itemBytes = SafePathBytes(candidate, &childInfo);
            NSError *removeError = nil;
            if (![NSFileManager.defaultManager removeItemAtPath:candidate error:&removeError]) {
                if (failedAt) *failedAt = [relativePath stringByAppendingPathComponent:child];
                if (error && !*error) *error = removeError ?: [NSError errorWithDomain:@"iDeviceLab.AppMaintenance" code:18
                    userInfo:@{NSLocalizedDescriptionKey:@"unable to remove cleanup item"}];
                return NO;
            }
            if (removedBytes) *removedBytes += itemBytes;
            if (removedItems) (*removedItems)++;
        }
    }
    return YES;
}

static NSDictionary *SafeDirectoryMetrics(NSString *path) {
    struct stat rootInfo = {0};
    if (lstat(path.fileSystemRepresentation, &rootInfo) != 0) {
        int savedErrno = errno;
        return @{@"bytes":@0, @"fileCount":@0,
                 @"status":(savedErrno == ENOENT ? @"missing" : @"inaccessible"),
                 @"error":(savedErrno == ENOENT ? @"" : ([NSString stringWithUTF8String:strerror(savedErrno)] ?: @"unable to inspect directory"))};
    }
    if (!S_ISDIR(rootInfo.st_mode))
        return @{@"bytes":@0, @"fileCount":@0, @"status":@"notDirectory", @"error":@"target is not a directory"};

    __block NSError *scanError = nil;
    unsigned long long totalBytes = 0, totalFiles = 0;
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:path]
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey, NSURLIsSymbolicLinkKey]
        options:0 errorHandler:^BOOL(__unused NSURL *url, NSError *error) {
            if (!scanError) scanError = error;
            return YES;
        }];
    if (!enumerator)
        return @{@"bytes":@0, @"fileCount":@0, @"status":@"inaccessible", @"error":@"unable to enumerate directory"};

    for (NSURL *url in enumerator) {
        NSNumber *isLink = nil, *isFile = nil, *size = nil;
        NSError *resourceError = nil;
        if (![url getResourceValue:&isLink forKey:NSURLIsSymbolicLinkKey error:&resourceError]) {
            if (!scanError) scanError = resourceError;
            continue;
        }
        if (isLink.boolValue) { [enumerator skipDescendants]; continue; }
        if (![url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:&resourceError]) {
            if (!scanError) scanError = resourceError;
            continue;
        }
        if (isFile.boolValue) {
            if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:&resourceError]) {
                if (!scanError) scanError = resourceError;
                continue;
            }
            totalFiles++;
            totalBytes += size.unsignedLongLongValue;
        }
    }
    return @{@"bytes":@(totalBytes), @"fileCount":@(totalFiles),
             @"status":(scanError ? @"partial" : @"complete"),
             @"error":scanError.localizedDescription ?: @""};
}


static NSDictionary *AppMaintenanceInventory(void) {
    NSError *installedScanError = nil, *containerScanError = nil;
    NSArray *installed = InstalledApplications(&installedScanError);
    NSDictionary *containers = AppDataContainerIndex(&containerScanError);
    NSMutableSet *installedIDs = [NSMutableSet set];
    NSMutableArray *apps = [NSMutableArray array];
    for (NSDictionary *app in installed) {
        NSString *bundleID = app[@"bundleIdentifier"];
        if (![bundleID isKindOfClass:NSString.class]) continue;
        [installedIDs addObject:bundleID];
        NSString *container = containers[bundleID];
        NSString *cachesPath = container ? [container stringByAppendingPathComponent:@"Library/Caches"] : nil;
        NSString *temporaryPath = container ? [container stringByAppendingPathComponent:@"tmp"] : nil;
        NSDictionary *cachesMetrics = cachesPath ? SafeDirectoryMetrics(cachesPath) : @{@"bytes":@0, @"fileCount":@0, @"status":@"unavailable", @"error":@"app container unavailable"};
        NSDictionary *temporaryMetrics = temporaryPath ? SafeDirectoryMetrics(temporaryPath) : @{@"bytes":@0, @"fileCount":@0, @"status":@"unavailable", @"error":@"app container unavailable"};
        unsigned long long caches = [cachesMetrics[@"bytes"] unsignedLongLongValue];
        unsigned long long temporary = [temporaryMetrics[@"bytes"] unsignedLongLongValue];
        [apps addObject:@{
            @"name": app[@"name"] ?: bundleID,
            @"bundleIdentifier": bundleID,
            @"version": app[@"version"] ?: @"",
            @"containerAvailable": @(container != nil),
            @"cachesBytes": @(caches),
            @"temporaryBytes": @(temporary),
            @"cachesFileCount": cachesMetrics[@"fileCount"] ?: @0,
            @"temporaryFileCount": temporaryMetrics[@"fileCount"] ?: @0,
            @"cachesScanStatus": cachesMetrics[@"status"] ?: @"unknown",
            @"temporaryScanStatus": temporaryMetrics[@"status"] ?: @"unknown",
            @"cachesScanError": cachesMetrics[@"error"] ?: @"",
            @"temporaryScanError": temporaryMetrics[@"error"] ?: @"",
            @"cleanableBytes": @(caches + temporary)
        }];
    }
    NSMutableArray *orphans = [NSMutableArray array];
    BOOL orphanScanComplete = installedScanError == nil && containerScanError == nil;
    BOOL orphanMetricsComplete = YES;
    if (orphanScanComplete) for (NSString *bundleID in containers) {
        if ([installedIDs containsObject:bundleID]) continue;
        NSString *container = containers[bundleID];
        NSString *containerUUID = container.lastPathComponent ?: @"";
        struct stat containerInfo = {0};
        BOOL accessible = lstat(container.fileSystemRepresentation, &containerInfo) == 0 && S_ISDIR(containerInfo.st_mode);
        NSDictionary *containerMetrics = SafeDirectoryMetrics(container);
        if (![containerMetrics[@"status"] isEqualToString:@"complete"]) orphanMetricsComplete = NO;
        [orphans addObject:@{
            @"bundleIdentifier": bundleID,
            @"containerUUID": containerUUID,
            @"accessible": @(accessible),
            @"containerBytes": containerMetrics[@"bytes"] ?: @0,
            @"containerScanStatus": containerMetrics[@"status"] ?: @"unknown",
            @"containerScanError": containerMetrics[@"error"] ?: @"",
            @"diagnosticReason": @"Container metadata references a Bundle ID absent from the current installed-app inventory; this is a candidate only, not proof that the data is stale."
        }];
    }
    [orphans sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"bundleIdentifier"] localizedCaseInsensitiveCompare:b[@"bundleIdentifier"]];
    }];
    return @{@"ok":@YES, @"apps":apps, @"orphanedContainerCount":@(orphans.count),
             @"orphanedContainers":orphans,
             @"installedAppScanStatus":(installedScanError ? @"partial" : @"complete"),
             @"installedAppScanError":installedScanError.localizedDescription ?: @"",
             @"containerIndexScanStatus":(containerScanError ? @"partial" : @"complete"),
             @"containerIndexScanError":containerScanError.localizedDescription ?: @"",
             @"orphanScanStatus":(!orphanScanComplete ? @"unavailable" : (orphanMetricsComplete ? @"complete" : @"partial")),
             @"scope":@"Orphan candidates are emitted only when both installed-app and app-container inventories completed without scan errors. Only Library/Caches and tmp are eligible for cleanup."};
}

static NSDictionary *ClearAppCaches(NSData *body) {
    if (body.length == 0 || body.length > 4096) return @{@"ok":@NO, @"error":@"invalid request body"};
    id input = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    NSString *bundleID = [input isKindOfClass:NSDictionary.class] ? input[@"bundleIdentifier"] : nil;
    if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 || bundleID.length > 255)
        return @{@"ok":@NO, @"error":@"a valid bundleIdentifier is required"};
    NSError *installedScanError = nil;
    NSArray *installedApps = InstalledApplications(&installedScanError);
    if (installedScanError)
        return @{@"ok":@NO, @"error":[NSString stringWithFormat:@"installed app inventory is incomplete; cleanup refused: %@", installedScanError.localizedDescription]};
    BOOL installed = NO;
    for (NSDictionary *app in installedApps) {
        if ([app[@"bundleIdentifier"] isEqualToString:bundleID]) { installed = YES; break; }
    }
    if (!installed) return @{@"ok":@NO, @"error":@"only currently installed applications can be selected"};
    NSError *containerScanError = nil;
    NSDictionary *containerIndex = AppDataContainerIndex(&containerScanError);
    if (containerScanError)
        return @{@"ok":@NO, @"error":[NSString stringWithFormat:@"app container inventory is incomplete; cleanup refused: %@", containerScanError.localizedDescription]};
    NSString *container = containerIndex[bundleID];
    if (!container) return @{@"ok":@NO, @"error":@"app data container is not accessible"};
    unsigned long long removed = 0, removedItems = 0;
    NSError *error = nil;
    NSString *failedAt = nil;
    // Preflight both locations before deleting anything, reducing partial-cleanup failures.
    if (!ClearDirectDirectoryContents(container, @"Library/Caches", NULL, NULL, YES, &failedAt, &error) ||
        !ClearDirectDirectoryContents(container, @"tmp", NULL, NULL, YES, &failedAt, &error))
        return @{@"ok":@NO, @"partial":@NO, @"removedBytes":@0, @"removedItems":@0,
                 @"failedArea":failedAt ?: @"preflight", @"error":error.localizedDescription ?: @"cache cleanup preflight failed; no files were intentionally removed"};
    if (!ClearDirectDirectoryContents(container, @"Library/Caches", &removed, &removedItems, NO, &failedAt, &error) ||
        !ClearDirectDirectoryContents(container, @"tmp", &removed, &removedItems, NO, &failedAt, &error))
        return @{@"ok":@NO, @"partial":@(removedItems > 0), @"bundleIdentifier":bundleID,
                 @"removedBytes":@(removed), @"removedItems":@(removedItems),
                 @"failedArea":failedAt ?: @"unknown",
                 @"error":error.localizedDescription ?: @"cache cleanup failed after preflight; inspect the selected app container"};
    return @{@"ok":@YES, @"partial":@NO, @"bundleIdentifier":bundleID,
             @"removedBytes":@(removed), @"removedItems":@(removedItems),
             @"clearedAreas":@[@"Library/Caches", @"tmp"],
             @"excludedAreas":@[@"Documents", @"Library/Preferences", @"Library/Application Support", @"Keychain", @"cloud state"]};
}

static NSDictionary *HookInstallationStatus(void) {
    NSString *directory = @"/var/jb/Library/MobileSubstrate/DynamicLibraries";
    NSString *dylib = [directory stringByAppendingPathComponent:@"mod_hw_for_ios.dylib"];
    NSString *filter = [directory stringByAppendingPathComponent:@"mod_hw_for_ios.plist"];
    struct stat dylibInfo = {0}, filterInfo = {0};
    BOOL dylibRegular = lstat(dylib.fileSystemRepresentation, &dylibInfo) == 0 && S_ISREG(dylibInfo.st_mode);
    BOOL filterRegular = lstat(filter.fileSystemRepresentation, &filterInfo) == 0 && S_ISREG(filterInfo.st_mode);
    NSDictionary *filterPlist = filterRegular ? [NSDictionary dictionaryWithContentsOfFile:filter] : nil;
    NSDictionary *filterRoot = [filterPlist[@"Filter"] isKindOfClass:NSDictionary.class] ? filterPlist[@"Filter"] : nil;
    NSArray *bundles = [filterRoot[@"Bundles"] isKindOfClass:NSArray.class] ? filterRoot[@"Bundles"] : @[];
    NSArray *executables = [filterRoot[@"Executables"] isKindOfClass:NSArray.class] ? filterRoot[@"Executables"] : @[];
    NSMutableArray *targets = [NSMutableArray array];
    for (id item in bundles) if ([item isKindOfClass:NSString.class]) [targets addObject:item];
    for (id item in executables) if ([item isKindOfClass:NSString.class]) [targets addObject:item];
    NSDictionary *attributes = dylibRegular ? [NSFileManager.defaultManager attributesOfItemAtPath:dylib error:nil] : @{};
    return @{
        @"ok":@YES,
        @"coreServiceRunning":@YES,
        @"tweakLibraryFound":@(dylibRegular),
        @"tweakFilterFound":@(filterRegular),
        @"filterParseable":@(filterRoot != nil),
        @"filterTargetCount":@(targets.count),
        @"filterTargets":targets,
        @"tweakLibraryBytes":@(dylibRegular ? [attributes[NSFileSize] unsignedLongLongValue] : 0),
        @"runtimeInjectionVerified":@NO,
        @"note":@"This checks file type, filter plist structure and declared targets only. It does not verify that any target process loaded the tweak."
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
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/apps"]) {
        NSError *scanError = nil;
        NSArray *apps = InstalledApplications(&scanError);
        return @{@"ok":@YES, @"apps":apps,
                 @"inventoryScanStatus":scanError ? @"partial" : @"complete",
                 @"inventoryScanError":scanError.localizedDescription ?: @""};
    }
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/maintenance/apps"]) return AppMaintenanceInventory();
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/maintenance/clear"]) return ClearAppCaches(body);
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/hooks/status"]) return HookInstallationStatus();
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/config/status"]) return Alpha11ConfigStatus();
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/config/update"]) return ApplySafeAlpha11ConfigUpdate(body);
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/config/restore"]) return RestoreAlpha11ConfigBackup();

    return @{@"ok":@NO, @"error":@"not found"};
}

static BOOL SendAll(int fd, const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t sent = send(fd, cursor, remaining, 0);
        if (sent < 0) {
            if (errno == EINTR) continue;
            return NO;
        }
        if (sent == 0) return NO;
        cursor += (size_t)sent;
        remaining -= (size_t)sent;
    }
    return YES;
}

static void Reply(int fd, NSDictionary *payload, int status) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil] ?: [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *reason = status == 200 ? @"OK" : (status == 400 ? @"Bad Request" : @"Not Found");
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n", status, reason, (unsigned long)body.length];
    NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    if (!SendAll(fd, headerData.bytes, headerData.length)) return;
    SendAll(fd, body.bytes, body.length);
}

static NSDictionary *ReadHTTPRequest(int fd, NSString **failure) {
    const NSUInteger maximumHeaderBytes = 16 * 1024;
    const NSUInteger maximumBodyBytes = 1024 * 1024;
    NSMutableData *requestData = [NSMutableData data];
    NSUInteger headerEnd = NSNotFound;
    uint8_t chunk[4096];

    while (headerEnd == NSNotFound) {
        ssize_t count = recv(fd, chunk, sizeof(chunk), 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            if (failure) *failure = count == 0 ? @"connection closed before request headers completed" : @"request header read failed or timed out";
            return nil;
        }
        [requestData appendBytes:chunk length:(NSUInteger)count];
        const uint8_t separator[] = {13,10,13,10};
        NSRange range = [requestData rangeOfData:[NSData dataWithBytes:separator length:4]
                                         options:0 range:NSMakeRange(0, requestData.length)];
        if (range.location != NSNotFound) {
            headerEnd = NSMaxRange(range);
            if (headerEnd > maximumHeaderBytes) {
                if (failure) *failure = @"request headers exceed 16 KiB";
                return nil;
            }
        } else if (requestData.length > maximumHeaderBytes) {
            if (failure) *failure = @"request headers exceed 16 KiB";
            return nil;
        }
    }

    NSData *headerData = [requestData subdataWithRange:NSMakeRange(0, headerEnd - 4)];
    NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
    if (!headerText) {
        if (failure) *failure = @"request headers are not valid UTF-8";
        return nil;
    }
    NSArray *lines = [headerText componentsSeparatedByString:@"\r\n"];
    NSArray *requestLine = lines.count ? [lines[0] componentsSeparatedByString:@" "] : @[];
    if (requestLine.count != 3 || [requestLine[0] length] == 0 ||
        [requestLine[1] length] == 0 || ![requestLine[1] hasPrefix:@"/"] ||
        ![requestLine[2] isEqualToString:@"HTTP/1.1"] ||
        (![(NSString *)requestLine[0] isEqualToString:@"GET"] && ![(NSString *)requestLine[0] isEqualToString:@"POST"])) {
        if (failure) *failure = @"request line must be GET or POST, an absolute path, and HTTP/1.1";
        return nil;
    }

    BOOL hasContentLength = NO;
    unsigned long long contentLength = 0;
    for (NSUInteger index = 1; index < lines.count; index++) {
        NSString *line = lines[index];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound || colon.location == 0) {
            if (failure) *failure = @"malformed HTTP header";
            return nil;
        }
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([name isEqualToString:@"transfer-encoding"]) {
            if (failure) *failure = @"Transfer-Encoding is not supported";
            return nil;
        }
        if ([name isEqualToString:@"content-length"]) {
            if (hasContentLength || value.length == 0 ||
                [value rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
                if (failure) *failure = @"Content-Length must appear once and contain decimal digits only";
                return nil;
            }
            hasContentLength = YES;
            NSScanner *scanner = [NSScanner scannerWithString:value];
            unsigned long long parsed = 0;
            if (![scanner scanUnsignedLongLong:&parsed] || !scanner.isAtEnd || parsed > maximumBodyBytes) {
                if (failure) *failure = @"request body exceeds 1 MiB or has invalid Content-Length";
                return nil;
            }
            contentLength = parsed;
        }
    }

    if (!hasContentLength) contentLength = 0;
    NSUInteger expectedTotal = headerEnd + (NSUInteger)contentLength;
    if (requestData.length > expectedTotal) {
        if (failure) *failure = @"unexpected bytes after the declared request body";
        return nil;
    }
    while (requestData.length < expectedTotal) {
        ssize_t count = recv(fd, chunk, MIN(sizeof(chunk), expectedTotal - requestData.length), 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            if (failure) *failure = @"request body is incomplete or timed out";
            return nil;
        }
        [requestData appendBytes:chunk length:(NSUInteger)count];
    }

    NSData *body = [requestData subdataWithRange:NSMakeRange(headerEnd, (NSUInteger)contentLength)];
    return @{@"method":requestLine[0], @"target":requestLine[1], @"body":body};
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
            struct timeval timeout = {5, 0};
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
            @autoreleasepool {
                NSString *requestError = nil;
                NSDictionary *request = ReadHTTPRequest(client, &requestError);
                if (!request) {
                    Reply(client, @{@"ok":@NO, @"error":requestError ?: @"malformed request"}, 400);
                } else {
                    NSString *method = request[@"method"];
                    NSString *target = request[@"target"];
                    NSData *body = request[@"body"];
                    NSDictionary *result = ProcessRequest(method, target, body);
                    NSString *requestPath = [[target componentsSeparatedByString:@"?"] firstObject] ?: target;
                    BOOL known = [@[@"/status", @"/system", @"/compatibility", @"/apps", @"/maintenance/apps", @"/maintenance/clear", @"/hooks/status", @"/config/status", @"/config/update", @"/config/restore"] containsObject:requestPath];
                    NSInteger httpStatus = !known ? 404 : ([result[@"ok"] respondsToSelector:@selector(boolValue)] && ![result[@"ok"] boolValue] ? 400 : 200);
                    Reply(client, result, (int)httpStatus);
                }
            }
            close(client);
        }
    }
    return 0;
}
