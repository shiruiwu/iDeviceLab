#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <signal.h>
#import <errno.h>
#import <string.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <sys/stat.h>
#import <pwd.h>
#import <stdlib.h>

// Alpha11 companion Core: read-only local diagnostics, bound to loopback.
static const int kPort = 18081;

// Do not follow symlinks when enumerating privileged backup storage.
// Require exact ownership and mode, not merely a subset of permission bits.
static BOOL HasSecureBackupMetadata(NSString *path, BOOL directory, gid_t mobileGID) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return NO;
    if (directory ? !S_ISDIR(st.st_mode) : !S_ISREG(st.st_mode)) return NO;
    mode_t expectedMode = directory ? 0750 : 0640;
    return st.st_uid == 0 && st.st_gid == mobileGID &&
           (st.st_mode & 07777) == expectedMode;
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
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
    return @{
        @"ok": @YES,
        @"productType": SysctlString("hw.machine"),
        @"architecture": @"arm64",
        @"osVersion": osVersion,
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


static NSArray *InstalledMaintenanceTools(void) {
    NSArray<NSString *> *names = @[
        @"mod-hw-diagnose",
        @"mod-hw-config-backup",
        @"mod-hw-config-restore",
        @"mod-hw-app-backup",
        @"mod-hw-app-backup-verify",
        @"mod-hw-app-restore",
        @"mod-hw-app-clean",
        @"mod-hw-maintenance",
        @"mod-hw-maintenance-helper",
        @"mod-hw-manager-pair",
        @"mod-hw-keychain-diagnose",
        @"mod-hw-selftest",
        @"mod-hw-acceptance-iphone12"
    ];
    NSMutableArray *tools = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
        NSString *path = [@"/var/jb/usr/bin" stringByAppendingPathComponent:name];
        BOOL installed = access(path.fileSystemRepresentation, X_OK) == 0;
        [tools addObject:@{@"name": name, @"path": path, @"installed": @(installed)}];
    }
    return tools;
}

static NSArray *InstalledProfiles(void) {
    NSString *root = @"/var/mobile/Library/Preferences/com.modhw.ios.profiles";
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[];
    NSMutableArray *profiles = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"plist"]) continue;
        NSString *bundleID = file.stringByDeletingPathExtension;
        if (bundleID.length == 0 || [bundleID containsString:@"/"] || [bundleID containsString:@".."]) continue;
        NSString *path = [root stringByAppendingPathComponent:file];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        id object = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil] : nil;
        BOOL valid = [object isKindOfClass:NSDictionary.class];
        [profiles addObject:@{@"bundleIdentifier": bundleID, @"valid": @(valid), @"path": path}];
    }
    [profiles sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"bundleIdentifier"] localizedCaseInsensitiveCompare:b[@"bundleIdentifier"]];
    }];
    return profiles;
}


static NSArray *AvailableBackups(void) {
    NSString *root = @"/var/mobile/Library/Application Support/mod_hw_for_ios/app-container-backups";
    struct passwd *mobileAccount = getpwnam("mobile");
    if (!mobileAccount || !HasSecureBackupMetadata(root, YES, mobileAccount->pw_gid)) return @[];
    gid_t mobileGID = mobileAccount->pw_gid;
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[];
    NSMutableArray *backups = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file hasSuffix:@".tar.gz"] || [file containsString:@"/"] || [file containsString:@".."]) continue;
        NSString *archive = [root stringByAppendingPathComponent:file];
        if (!HasSecureBackupMetadata(archive, NO, mobileGID)) continue;
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:archive error:nil];
        NSString *manifestPath = [archive stringByReplacingOccurrencesOfString:@".tar.gz" withString:@".txt"];
        if (!HasSecureBackupMetadata(manifestPath, NO, mobileGID)) continue;
        NSString *manifest = [NSString stringWithContentsOfFile:manifestPath encoding:NSUTF8StringEncoding error:nil];
        NSMutableDictionary *fields = [NSMutableDictionary dictionary];
        for (NSString *line in [manifest componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSRange separator = [line rangeOfString:@"="];
            if (separator.location == NSNotFound) continue;
            NSString *key = [line substringToIndex:separator.location];
            NSString *value = [line substringFromIndex:separator.location + 1];
            if ([@[@"bundle_id", @"container_id", @"created_at", @"archive", @"sha256", @"scope"] containsObject:key]) fields[key] = value;
        }
        NSString *hash = fields[@"sha256"];
        NSString *bundleID = fields[@"bundle_id"];
        NSString *containerID = fields[@"container_id"];
        NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
        NSCharacterSet *invalidIdentity = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"] invertedSet];
        BOOL validBundle = [bundleID isKindOfClass:NSString.class] && bundleID.length > 0 &&
            ![bundleID hasPrefix:@"."] && ![bundleID hasSuffix:@"."] &&
            ![bundleID containsString:@".."] && [bundleID rangeOfCharacterFromSet:invalidIdentity].location == NSNotFound;
        BOOL validContainer = [containerID isKindOfClass:NSString.class] && containerID.length > 0 &&
            ![containerID hasPrefix:@"."] && ![containerID hasSuffix:@"."] &&
            ![containerID containsString:@".."] && [containerID rangeOfCharacterFromSet:invalidIdentity].location == NSNotFound;
        BOOL validHash = [hash isKindOfClass:NSString.class] && hash.length == 64 &&
            [hash rangeOfCharacterFromSet:nonHex].location == NSNotFound;
        if (![fields[@"archive"] isEqualToString:file] || !validBundle || !validContainer ||
            !validHash || [attrs[NSFileSize] unsignedLongLongValue] == 0) continue;
        [backups addObject:@{
            @"archive": file,
            @"bundleIdentifier": fields[@"bundle_id"],
            @"containerIdentifier": fields[@"container_id"] ?: @"",
            @"createdAt": fields[@"created_at"] ?: @"",
            @"sha256": hash,
            @"sizeBytes": attrs[NSFileSize] ?: @0
        }];
    }
    [backups sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"createdAt"] compare:a[@"createdAt"]];
    }];
    return backups;
}

static NSDictionary *ForwardMaintenanceRequest(NSDictionary *request) {
    NSData *payload = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (!payload || payload.length > 32768) return @{@"ok": @NO, @"error": @"维护请求无效或过大。"};
    NSMutableData *line = [payload mutableCopy];
    const uint8_t newline = '\n';
    [line appendBytes:&newline length:1];

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"无法创建 Helper 连接：%s", strerror(errno)]};
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, "/var/run/com.idevelab.maintenance.sock", sizeof(address.sun_path));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int saved = errno; close(fd);
        return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"Root Helper 尚未启动或不可访问：%s", strerror(saved)]};
    }
    struct timeval timeout = {.tv_sec = 300, .tv_usec = 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    const uint8_t *bytes = line.bytes;
    size_t offset = 0;
    while (offset < line.length) {
        ssize_t sent = send(fd, bytes + offset, line.length - offset, 0);
        if (sent < 0 && errno == EINTR) continue;
        if (sent <= 0) { int saved = errno; close(fd); return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"发送到 Root Helper 失败：%s", strerror(saved)]}; }
        offset += (size_t)sent;
    }
    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[4096];
    BOOL complete = NO;
    while (response.length < 131072 && !complete) {
        ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        uint8_t *newlinePtr = memchr(buffer, '\n', (size_t)count);
        size_t appendCount = newlinePtr ? (size_t)(newlinePtr - buffer) : (size_t)count;
        [response appendBytes:buffer length:appendCount];
        complete = newlinePtr != NULL;
    }
    close(fd);
    id object = complete ? [NSJSONSerialization JSONObjectWithData:response options:NSJSONReadingFragmentsAllowed error:nil] : nil;
    if (![object isKindOfClass:NSDictionary.class]) return @{@"ok": @NO, @"error": @"Root Helper 未返回有效响应。"};
    return object;
}

static NSDictionary *ProcessRequest(NSString *method, NSString *target) {
    NSString *path = [[target componentsSeparatedByString:@"?"] firstObject] ?: @"/";
    if ([path isEqualToString:@"/maintenance"] && [method isEqualToString:@"GET"]) {
        NSURLComponents *components = [NSURLComponents componentsWithString:[@"http://127.0.0.1" stringByAppendingString:target]];
        NSString *json = nil;
        for (NSURLQueryItem *item in components.queryItems) if ([item.name isEqualToString:@"request"]) { json = item.value; break; }
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        id object = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil] : nil;
        if (![object isKindOfClass:NSDictionary.class]) return @{@"ok": @NO, @"error": @"维护请求格式无效。"};
        NSDictionary *request = object;
        NSNumber *pid = request[@"managerPID"];
        if (![pid isKindOfClass:NSNumber.class] || pid.intValue <= 1) return @{@"ok": @NO, @"error": @"缺少有效的 Manager 进程标识。"};
        return ForwardMaintenanceRequest(request);
    }
    if (![method isEqualToString:@"GET"]) {
        return @{@"ok": @NO, @"error": @"method not allowed"};
    }
    if ([path isEqualToString:@"/status"]) {
        return @{@"ok": @YES, @"service": @"iDeviceLab Rootless Core", @"version": @"0.3.4-alpha11", @"port": @(kPort), @"mode": @"read-only"};
    }
    if ([path isEqualToString:@"/system"]) return SystemSummary();
    if ([path isEqualToString:@"/apps"]) return @{@"ok": @YES, @"apps": InstalledApplications()};
    if ([path isEqualToString:@"/tools"]) return @{@"ok": @YES, @"tools": InstalledMaintenanceTools()};
    if ([path isEqualToString:@"/profiles"]) return @{@"ok": @YES, @"profiles": InstalledProfiles(), @"directory": @"/var/mobile/Library/Preferences/com.modhw.ios.profiles"};
    if ([path isEqualToString:@"/backups"]) return @{@"ok": @YES, @"backups": AvailableBackups()};
    return @{@"ok": @NO, @"error": @"not found"};
}

static void Reply(int fd, NSDictionary *payload, int status) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil] ?: [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *reason = status == 200 ? @"OK" : (status == 405 ? @"Method Not Allowed" : @"Not Found");
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n", status, reason, (unsigned long)body.length];
    const char *headerBytes = header.UTF8String;
    size_t headerLength = strlen(headerBytes);
    size_t headerOffset = 0;
    while (headerOffset < headerLength) {
        ssize_t sent = send(fd, headerBytes + headerOffset, headerLength - headerOffset, 0);
        if (sent < 0 && errno == EINTR) continue;
        if (sent <= 0) return;
        headerOffset += (size_t)sent;
    }
    size_t bodyOffset = 0;
    while (bodyOffset < body.length) {
        ssize_t sent = send(fd, (const uint8_t *)body.bytes + bodyOffset, body.length - bodyOffset, 0);
        if (sent < 0 && errno == EINTR) continue;
        if (sent <= 0) return;
        bodyOffset += (size_t)sent;
    }
}

int main(void) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        fprintf(stderr, "[idevelab-core] starting version 0.3.4-alpha11 pid=%d uid=%d\n", getpid(), getuid());
        fflush(stderr);
        int server = socket(AF_INET, SOCK_STREAM, 0);
        if (server < 0) { fprintf(stderr, "[idevelab-core] socket failed errno=%d (%s)\n", errno, strerror(errno)); return 1; }
        int yes = 1;
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        struct sockaddr_in addr = {0};
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(kPort);
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) < 0) { int saved = errno; fprintf(stderr, "[idevelab-core] bind 127.0.0.1:%d failed errno=%d (%s)\n", kPort, saved, strerror(saved)); close(server); return 2; }
        if (listen(server, 8) < 0) { int saved = errno; fprintf(stderr, "[idevelab-core] listen failed errno=%d (%s)\n", saved, strerror(saved)); close(server); return 3; }
        fprintf(stderr, "[idevelab-core] LISTENING 127.0.0.1:%d\n", kPort);
        fflush(stderr);
        for (;;) {
            int client = accept(server, NULL, NULL);
            if (client < 0) {
                if (errno == EINTR) continue;
                sleep(1);
                continue;
            }
            struct timeval timeout = {.tv_sec = 2, .tv_usec = 0};
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            char buffer[8192] = {0};
            ssize_t count = recv(client, buffer, sizeof(buffer) - 1, 0);
            if (count > 0) {
                @autoreleasepool {
                    NSString *request = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)count encoding:NSUTF8StringEncoding];
                    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
                    NSArray *first = lines.firstObject ? [lines.firstObject componentsSeparatedByString:@" "] : @[];
                    if (first.count >= 2) {
                        NSString *method = first[0], *target = first[1];
                        NSString *path = [[target componentsSeparatedByString:@"?"] firstObject] ?: @"";
                        BOOL known = [path isEqualToString:@"/maintenance"] ||
                                     [path isEqualToString:@"/status"] ||
                                     [path isEqualToString:@"/system"] ||
                                     [path isEqualToString:@"/apps"] ||
                                     [path isEqualToString:@"/tools"] ||
                                     [path isEqualToString:@"/profiles"] ||
                                     [path isEqualToString:@"/backups"];
                        NSDictionary *result = ProcessRequest(method, target);
                        int status = ![method isEqualToString:@"GET"] ? 405 : (known ? 200 : 404);
                        Reply(client, result, status);
                    } else {
                        Reply(client, @{@"ok": @NO, @"error": @"malformed request"}, 404);
                    }
                }
            }
            close(client);
        }
    }
    return 0;
}
