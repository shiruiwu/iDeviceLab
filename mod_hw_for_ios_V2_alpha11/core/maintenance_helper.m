#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <sys/sysctl.h>
#include <pwd.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <poll.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdio.h>
#include <limits.h>
#include <sys/time.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>

#ifndef CS_VALID
#define CS_VALID 0x0000001
#endif
#ifndef CS_KILLED
#define CS_KILLED 0x1000000
#endif
#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_OPS_CDHASH
#define CS_OPS_CDHASH 5
#endif
#ifndef CS_CDHASH_LEN
#define CS_CDHASH_LEN 20
#endif

static int QueryCSOps(pid_t pid, unsigned int operation, void *buffer, size_t length) {
    typedef int (*CSOpsFunction)(pid_t, unsigned int, void *, size_t);
    CSOpsFunction function = (CSOpsFunction)dlsym(RTLD_DEFAULT, "csops");
    return function ? function(pid, operation, buffer, length) : -1;
}

extern char **environ;

static const char *kSocketPath = "/var/run/com.idevelab.maintenance.sock";
static const char *kPinPath = "/var/jb/var/root/Library/Preferences/com.idevelab.manager-cdhash";
static const size_t kRequestLimit = 4096;
static const size_t kOutputLimit = 65536;

static NSDictionary *Failure(NSString *message) {
    return @{@"ok": @NO, @"error": message ?: @"操作失败"};
}

static void SendJSON(int fd, NSDictionary *object) {
    NSError *error = nil;
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:object options:0 error:&error] mutableCopy];
    if (!data) data = [[NSMutableData alloc] initWithData:[@"{\"ok\":false,\"error\":\"response serialization failed\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    const uint8_t newline = '\n';
    [data appendBytes:&newline length:1];
    const uint8_t *bytes = data.bytes;
    size_t offset = 0;
    while (offset < data.length) {
        ssize_t count = send(fd, bytes + offset, data.length - offset, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (size_t)count;
    }
}

static BOOL ReadRequest(int fd, NSDictionary **result) {
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[512];
    while (data.length < kRequestLimit) {
        ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        const uint8_t *newline = memchr(buffer, '\n', (size_t)count);
        size_t appendCount = newline ? (size_t)(newline - buffer) : (size_t)count;
        if (data.length + appendCount > kRequestLimit) return NO;
        [data appendBytes:buffer length:appendCount];
        if (newline) break;
    }
    if (data.length == 0 || data.length >= kRequestLimit) return NO;
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
    if (![object isKindOfClass:NSDictionary.class]) return NO;
    *result = object;
    return YES;
}

static BOOL IsHexString(NSString *value, NSUInteger length) {
    if (![value isKindOfClass:NSString.class] || value.length != length) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static BOOL ValidBundleID(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length < 3 || value.length > 255 ||
        [value hasPrefix:@"."] || [value hasSuffix:@"."] || [value containsString:@".."]) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-"] invertedSet];
    if ([value rangeOfCharacterFromSet:invalid].location != NSNotFound) return NO;
    return [value containsString:@"."];
}

static BOOL ValidArchiveName(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length < 8 || value.length > 160 ||
        ![value hasSuffix:@".tar.gz"] || [value hasPrefix:@"."] ||
        [value containsString:@".."] || [value containsString:@"/"] ||
        [value containsString:@"\\"]) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"] invertedSet];
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static BOOL ReadPinnedHash(uint8_t output[CS_CDHASH_LEN]) {
    struct stat st;
    if (lstat(kPinPath, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 ||
        st.st_gid != 0 || (st.st_mode & 07777) != 0600) return NO;
    FILE *file = fopen(kPinPath, "r");
    if (!file) return NO;
    char text[64] = {0};
    size_t count = fread(text, 1, sizeof(text) - 1, file);
    fclose(file);
    if (!((count == 40) || (count == 41 && text[40] == '\n'))) return NO;
    for (size_t i = 0; i < CS_CDHASH_LEN; i++) {
        char pair[3] = {text[i * 2], text[i * 2 + 1], 0};
        char *end = NULL;
        long value = strtol(pair, &end, 16);
        if (!end || *end != '\0' || value < 0 || value > 255) return NO;
        output[i] = (uint8_t)value;
    }
    return YES;
}

static BOOL PeerPID(int fd, pid_t *pid) {
    socklen_t length = sizeof(*pid);
    *pid = 0;
    return getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, pid, &length) == 0 && length == sizeof(*pid) && *pid > 0;
}

static BOOL PeerIsMobile(int fd, pid_t *pid) {
    uid_t uid = (uid_t)-1;
    gid_t gid = (gid_t)-1;
    struct passwd *mobile = getpwnam("mobile");
    if (!mobile || getpeereid(fd, &uid, &gid) != 0 || uid != mobile->pw_uid) return NO;
    return PeerPID(fd, pid);
}

static BOOL PeerMatchesPinned(pid_t pid) {
    uint32_t status = 0;
    if (QueryCSOps(pid, CS_OPS_STATUS, &status, sizeof(status)) != 0 ||
        (status & CS_VALID) == 0 || (status & CS_KILLED) != 0) return NO;
    uint8_t expected[CS_CDHASH_LEN] = {0};
    uint8_t actual[CS_CDHASH_LEN] = {0};
    if (!ReadPinnedHash(expected) || QueryCSOps(pid, CS_OPS_CDHASH, actual, sizeof(actual)) != 0) return NO;
    return memcmp(expected, actual, sizeof(expected)) == 0;
}


static BOOL ProcessExecutablePath(pid_t pid, char output[4096]) {
    if (pid <= 1) return NO;
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int) + 2 || size > 1024 * 1024) return NO;
    char *buffer = calloc(1, size + 1);
    if (!buffer) return NO;
    BOOL success = NO;
    if (sysctl(mib, 3, buffer, &size, NULL, 0) == 0 && size > sizeof(int)) {
        char *cursor = buffer + sizeof(int);
        char *end = buffer + size;
        while (cursor < end && *cursor == '\0') cursor++;
        size_t length = strnlen(cursor, (size_t)(end - cursor));
        if (length > 0 && length < 4096) {
            memcpy(output, cursor, length);
            output[length] = '\0';
            success = YES;
        }
    }
    free(buffer);
    return success;
}

static BOOL PairManagerProcess(pid_t pid, NSString **message) {
    if (pid <= 1) {
        if (message) *message = @"Manager 进程标识无效。";
        return NO;
    }
    char executable[4096] = {0};
    if (!ProcessExecutablePath(pid, executable)) {
        if (message) *message = @"无法读取管理器进程路径。";
        return NO;
    }
    NSString *executablePath = [NSString stringWithUTF8String:executable];
    NSRange marker = [executablePath rangeOfString:@".app/" options:NSBackwardsSearch];
    if (marker.location == NSNotFound) {
        if (message) *message = @"请求配对的进程不是应用程序。";
        return NO;
    }
    NSString *appPath = [executablePath substringToIndex:marker.location + 4];
    if (![appPath.lastPathComponent isEqualToString:@"ModHWManager.app"]) {
        if (message) *message = @"只有 iDeviceLab Manager 可以发起配对。";
        return NO;
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = info[@"CFBundleIdentifier"];
    if (![bundleID isEqualToString:@"com.modhw.manager"] &&
        ![bundleID isEqualToString:@"com.modhw.manager.sandboxed"]) {
        if (message) *message = @"Manager Bundle ID 不匹配。";
        return NO;
    }

    uint32_t status = 0;
    uint8_t hash[CS_CDHASH_LEN] = {0};
    if (QueryCSOps(pid, CS_OPS_STATUS, &status, sizeof(status)) != 0 ||
        (status & CS_VALID) == 0 || (status & CS_KILLED) != 0 ||
        QueryCSOps(pid, CS_OPS_CDHASH, hash, sizeof(hash)) != 0) {
        if (message) *message = @"无法验证 Manager 代码签名。";
        return NO;
    }
    char hex[CS_CDHASH_LEN * 2 + 1] = {0};
    for (size_t i = 0; i < CS_CDHASH_LEN; i++) snprintf(hex + i * 2, 3, "%02x", hash[i]);

    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/jb/var/root/Library/Preferences"
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0700}
                                                    error:&directoryError];
    struct stat directoryStat;
    if (lstat("/var/jb/var/root/Library/Preferences", &directoryStat) != 0 ||
        !S_ISDIR(directoryStat.st_mode) || directoryStat.st_uid != 0 ||
        chmod("/var/jb/var/root/Library/Preferences", 0700) != 0) {
        if (message) *message = @"无法安全创建 Manager 配对目录。";
        return NO;
    }

    char temporary[512];
    snprintf(temporary, sizeof(temporary), "%s.tmp.%d", kPinPath, getpid());
    int fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) {
        if (message) *message = [NSString stringWithFormat:@"无法创建配对记录：%s", strerror(errno)];
        return NO;
    }
    size_t length = strlen(hex);
    ssize_t written = write(fd, hex, length);
    BOOL saved = written == (ssize_t)length && fsync(fd) == 0 &&
                 fchown(fd, 0, 0) == 0 && fchmod(fd, 0600) == 0;
    close(fd);
    if (!saved || rename(temporary, kPinPath) != 0) {
        unlink(temporary);
        if (message) *message = @"写入 Manager 配对记录失败。";
        return NO;
    }
    uint8_t persistedHash[CS_CDHASH_LEN] = {0};
    if (!ReadPinnedHash(persistedHash) || memcmp(hash, persistedHash, sizeof(hash)) != 0) {
        unlink(kPinPath);
        if (message) *message = @"配对记录写入后校验失败，已清除无效记录。";
        return NO;
    }
    uint32_t finalStatus = 0;
    uint8_t finalHash[CS_CDHASH_LEN] = {0};
    if (QueryCSOps(pid, CS_OPS_STATUS, &finalStatus, sizeof(finalStatus)) != 0 ||
        (finalStatus & CS_VALID) == 0 || (finalStatus & CS_KILLED) != 0 ||
        QueryCSOps(pid, CS_OPS_CDHASH, finalHash, sizeof(finalHash)) != 0 ||
        memcmp(hash, finalHash, sizeof(hash)) != 0) {
        unlink(kPinPath);
        if (message) *message = @"配对期间 Manager 进程已退出或签名发生变化，请重新打开管理器后配对。";
        return NO;
    }
    if (message) *message = @"Manager 已完成签名配对。现在可以使用受限维护功能。";
    return YES;
}

static double MonotonicSeconds(void) {
    struct timespec ts = {0};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ((double)ts.tv_nsec / 1000000000.0);
}

static int RunFixedTool(const char *path, NSArray<NSString *> *arguments, NSString **output, BOOL *timedOut, BOOL *truncated) {
    int pipes[2] = {-1, -1};
    if (pipe(pipes) != 0) return 127;
    fcntl(pipes[0], F_SETFL, fcntl(pipes[0], F_GETFL) | O_NONBLOCK);

    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipes[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipes[0]);
    posix_spawn_file_actions_addclose(&actions, pipes[1]);
    posix_spawnattr_init(&attributes);
    posix_spawnattr_setpgroup(&attributes, 0);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);

    char *argv[5] = {(char *)path, NULL, NULL, NULL, NULL};
    for (NSUInteger i = 0; i < arguments.count && i < 3; i++) argv[i + 1] = (char *)arguments[i].UTF8String;
    pid_t child = 0;
    int spawnError = posix_spawn(&child, path, &actions, &attributes, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    close(pipes[1]);
    if (spawnError != 0) {
        close(pipes[0]);
        return 127;
    }

    NSMutableData *captured = [NSMutableData data];
    BOOL childExited = NO, eof = NO;
    int childStatus = 0;
    double deadline = MonotonicSeconds() + 300.0;
    *timedOut = NO;
    *truncated = NO;

    while (!childExited || !eof) {
        struct pollfd descriptor = {.fd = pipes[0], .events = POLLIN | POLLHUP, .revents = 0};
        int pollResult = poll(&descriptor, 1, 500);
        if (pollResult > 0 && (descriptor.revents & (POLLIN | POLLHUP))) {
            uint8_t buffer[4096];
            for (;;) {
                ssize_t count = read(pipes[0], buffer, sizeof(buffer));
                if (count > 0) {
                    size_t remaining = captured.length < kOutputLimit ? kOutputLimit - captured.length : 0;
                    size_t keep = MIN((size_t)count, remaining);
                    if (keep > 0) [captured appendBytes:buffer length:keep];
                    if (keep < (size_t)count) *truncated = YES;
                    continue;
                }
                if (count == 0) eof = YES;
                if (count < 0 && errno == EINTR) continue;
                break;
            }
        }

        if (!childExited) {
            pid_t waited = waitpid(child, &childStatus, WNOHANG);
            if (waited == child) childExited = YES;
        }
        if (MonotonicSeconds() > deadline && (!childExited || !eof)) {
            *timedOut = YES;
            kill(-child, SIGTERM);
            usleep(500000);
            kill(-child, SIGKILL);
            if (!childExited) {
                while (waitpid(child, &childStatus, 0) < 0 && errno == EINTR) {}
                childExited = YES;
            }
            if (!eof) {
                uint8_t discard[4096];
                while (read(pipes[0], discard, sizeof(discard)) > 0) {}
                eof = YES;
            }
        }
        if (pollResult < 0 && errno != EINTR) break;
    }
    close(pipes[0]);
    *output = [[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] ?: @"（输出包含非 UTF-8 数据）";
    if (*timedOut) return 124;
    if (WIFEXITED(childStatus)) return WEXITSTATUS(childStatus);
    if (WIFSIGNALED(childStatus)) return 128 + WTERMSIG(childStatus);
    return 1;
}


static BOOL PeerIsTrustedCore(int fd, pid_t *peerPID) {
    if (!PeerIsMobile(fd, peerPID)) return NO;
    char executable[4096] = {0};
    char actualPath[PATH_MAX] = {0};
    char expectedPath[PATH_MAX] = {0};
    if (!ProcessExecutablePath(*peerPID, executable) ||
        !realpath(executable, actualPath) ||
        !realpath("/var/jb/usr/libexec/idevelab-core", expectedPath)) return NO;
    return strcmp(actualPath, expectedPath) == 0;
}

static BOOL MatchesCharacterSet(NSString *value, NSUInteger minimum, NSUInteger maximum, NSString *allowedCharacters) {
    if (![value isKindOfClass:NSString.class] || value.length < minimum || value.length > maximum) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:allowedCharacters] invertedSet];
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static BOOL ValidIMEI(NSString *value) {
    if (!MatchesCharacterSet(value, 15, 15, @"0123456789")) return NO;
    NSInteger sum = 0;
    for (NSInteger index = 13; index >= 0; index--) {
        NSInteger digit = [value characterAtIndex:(NSUInteger)index] - '0';
        if (((13 - index) % 2) == 0) {
            NSInteger doubled = digit * 2;
            sum += (doubled / 10) + (doubled % 10);
        } else {
            sum += digit;
        }
    }
    sum += [value characterAtIndex:14] - '0';
    return (sum % 10) == 0;
}

static BOOL ValidMACAddress(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *compact = [[value stringByReplacingOccurrencesOfString:@":" withString:@""] uppercaseString];
    return MatchesCharacterSet(compact, 12, 12, @"0123456789ABCDEF");
}

static BOOL ValidateHookProfile(NSDictionary *profile, NSString **errorMessage) {
    if (![profile isKindOfClass:NSDictionary.class] || profile.count == 0 || profile.count > 15) {
        if (errorMessage) *errorMessage = @"Hook 配置必须是非空字典，最多 15 个字段。";
        return NO;
    }
    NSSet *stringKeys = [NSSet setWithArray:@[
        @"SerialNumber", @"InternationalMobileEquipmentIdentity", @"MobileEquipmentIdentifier",
        @"WifiAddress", @"BluetoothAddress", @"UniqueDeviceID", @"ProductId", @"UniqueChipId",
        @"ProductType", @"HWModelStr", @"IDFA", @"IDFV"
    ]];
    NSSet *booleanKeys = [NSSet setWithArray:@[
        @"UniqueDeviceIDData", @"WifiAddressData", @"BluetoothAddressData"
    ]];
    for (id rawKey in profile) {
        if (![rawKey isKindOfClass:NSString.class] ||
            (![stringKeys containsObject:rawKey] && ![booleanKeys containsObject:rawKey])) {
            if (errorMessage) *errorMessage = @"Hook 配置包含未允许的字段。";
            return NO;
        }
        id value = profile[rawKey];
        if ([stringKeys containsObject:rawKey]) {
            if (![value isKindOfClass:NSString.class]) {
                if (errorMessage) *errorMessage = [NSString stringWithFormat:@"%@ 必须是字符串。", rawKey];
                return NO;
            }
            NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            BOOL valid = NO;
            if ([rawKey isEqualToString:@"SerialNumber"]) {
                valid = MatchesCharacterSet(text, 1, 32, @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
            } else if ([rawKey isEqualToString:@"InternationalMobileEquipmentIdentity"]) {
                valid = ValidIMEI(text);
            } else if ([rawKey isEqualToString:@"MobileEquipmentIdentifier"]) {
                valid = MatchesCharacterSet(text, 14, 14, @"0123456789ABCDEFabcdef");
            } else if ([rawKey isEqualToString:@"WifiAddress"] || [rawKey isEqualToString:@"BluetoothAddress"]) {
                valid = ValidMACAddress(text);
            } else if ([rawKey isEqualToString:@"UniqueDeviceID"]) {
                valid = MatchesCharacterSet(text, 40, 40, @"0123456789ABCDEFabcdef");
            } else if ([rawKey isEqualToString:@"ProductId"]) {
                valid = MatchesCharacterSet(text, 12, 12, @"0123456789ABCDEFabcdef");
            } else if ([rawKey isEqualToString:@"UniqueChipId"]) {
                valid = MatchesCharacterSet(text, 12, 12, @"0123456789ABCDEFabcdef");
            } else if ([rawKey isEqualToString:@"ProductType"]) {
                valid = MatchesCharacterSet(text, 1, 32, @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789,.");
            } else if ([rawKey isEqualToString:@"HWModelStr"]) {
                valid = MatchesCharacterSet(text, 1, 32, @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
            } else if ([rawKey isEqualToString:@"IDFA"] || [rawKey isEqualToString:@"IDFV"]) {
                valid = [[NSUUID alloc] initWithUUIDString:text] != nil;
            }
            if (!valid) {
                if (errorMessage) *errorMessage = [NSString stringWithFormat:@"%@ 格式无效。", rawKey];
                return NO;
            }
        } else {
            if (![value isKindOfClass:NSNumber.class] ||
                CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) {
                if (errorMessage) *errorMessage = [NSString stringWithFormat:@"%@ 必须是布尔值。", rawKey];
                return NO;
            }
        }
    }
    NSString *udid = profile[@"UniqueDeviceID"];
    if (![udid isKindOfClass:NSString.class] || !MatchesCharacterSet(udid, 40, 40, @"0123456789ABCDEFabcdef")) {
        if (errorMessage) *errorMessage = @"必须提供 40 位十六进制 UniqueDeviceID。";
        return NO;
    }
    return YES;
}

static BOOL EnsureRootMobileDirectory(NSString *path, mode_t mode, gid_t mobileGID) {
    struct stat metadata;
    if (lstat(path.fileSystemRepresentation, &metadata) == 0) {
        if (!S_ISDIR(metadata.st_mode)) return NO;
    } else if (errno == ENOENT) {
        if (mkdir(path.fileSystemRepresentation, mode) != 0 && errno != EEXIST) return NO;
    } else {
        return NO;
    }
    if (lstat(path.fileSystemRepresentation, &metadata) != 0 || !S_ISDIR(metadata.st_mode)) return NO;
    return chown(path.fileSystemRepresentation, 0, mobileGID) == 0 &&
           chmod(path.fileSystemRepresentation, mode) == 0;
}

static BOOL WriteSecureFile(NSString *path, NSData *data, gid_t mobileGID) {
    NSString *temporary = [path stringByAppendingFormat:@".tmp.%d", getpid()];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) return NO;
    const uint8_t *bytes = data.bytes;
    size_t offset = 0;
    BOOL okay = YES;
    while (offset < data.length) {
        ssize_t count = write(fd, bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { okay = NO; break; }
        offset += (size_t)count;
    }
    if (okay) okay = fchown(fd, 0, mobileGID) == 0 && fchmod(fd, 0640) == 0 && fsync(fd) == 0;
    close(fd);
    if (!okay || rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        unlink(temporary.fileSystemRepresentation);
        return NO;
    }
    struct stat metadata;
    return lstat(path.fileSystemRepresentation, &metadata) == 0 &&
           S_ISREG(metadata.st_mode) && metadata.st_uid == 0 &&
           metadata.st_gid == mobileGID && (metadata.st_mode & 07777) == 0640;
}

static BOOL AddBundleToSubstrateFilter(NSString *bundleID, NSString **message) {
    NSString *path = @"/var/jb/Library/MobileSubstrate/DynamicLibraries/mod_hw_for_ios.plist";
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![root isKindOfClass:NSDictionary.class]) {
        if (message) *message = @"无法读取 Hook 注入过滤配置文件。";
        return NO;
    }
    NSMutableDictionary *updated = [root mutableCopy];
    NSDictionary *filter = root[@"Filter"];
    if (![filter isKindOfClass:NSDictionary.class]) {
        if (message) *message = @"Hook 注入过滤配置缺少 Filter 字典。";
        return NO;
    }
    NSMutableDictionary *updatedFilter = [filter mutableCopy];
    NSArray *existing = filter[@"Bundles"];
    if (![existing isKindOfClass:NSArray.class]) existing = @[];
    NSMutableArray *bundles = [existing mutableCopy];
    if (![bundles containsObject:bundleID]) [bundles addObject:bundleID];
    updatedFilter[@"Bundles"] = bundles;
    updated[@"Filter"] = updatedFilter;

    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:updated
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (!data) {
        if (message) *message = [NSString stringWithFormat:@"Hook 注入过滤配置序列化失败：%@", error.localizedDescription ?: @"未知错误"];
        return NO;
    }
    struct stat oldStat;
    if (lstat(path.fileSystemRepresentation, &oldStat) != 0 ||
        !S_ISREG(oldStat.st_mode) || oldStat.st_uid != 0) {
        if (message) *message = @"Hook 注入过滤配置文件权限或类型不安全。";
        return NO;
    }
    NSString *temporary = [path stringByAppendingFormat:@".tmp.%d", getpid()];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0644);
    if (fd < 0) {
        if (message) *message = [NSString stringWithFormat:@"无法创建 Hook 过滤配置临时文件：%s", strerror(errno)];
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    size_t offset = 0;
    BOOL okay = YES;
    while (offset < data.length) {
        ssize_t count = write(fd, bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { okay = NO; break; }
        offset += (size_t)count;
    }
    if (okay) okay = fchown(fd, 0, oldStat.st_gid) == 0 && fchmod(fd, oldStat.st_mode & 0777) == 0 && fsync(fd) == 0;
    close(fd);
    if (!okay || rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        unlink(temporary.fileSystemRepresentation);
        if (message) *message = @"Hook 过滤配置原子写入失败。";
        return NO;
    }
    NSDictionary *verified = [NSDictionary dictionaryWithContentsOfFile:path];
    NSArray *verifiedBundles = [verified[@"Filter"] isKindOfClass:NSDictionary.class] ? verified[@"Filter"][@"Bundles"] : nil;
    if (![verifiedBundles isKindOfClass:NSArray.class] || ![verifiedBundles containsObject:bundleID]) {
        if (message) *message = @"Hook 过滤配置写入后回读校验失败。";
        return NO;
    }
    return YES;
}

static BOOL ApplyHookProfile(NSString *bundleID, NSDictionary *profile, BOOL global, NSString **message) {
    NSString *validationError = nil;
    if ((!global && !ValidBundleID(bundleID)) || !ValidateHookProfile(profile, &validationError)) {
        if (message) *message = validationError ?: @"Bundle ID 无效。";
        return NO;
    }
    struct passwd *mobile = getpwnam("mobile");
    if (!mobile) {
        if (message) *message = @"找不到 mobile 账户。";
        return NO;
    }
    NSString *preferences = @"/var/mobile/Library/Preferences";
    struct stat parentMetadata;
    if (lstat(preferences.fileSystemRepresentation, &parentMetadata) != 0 || !S_ISDIR(parentMetadata.st_mode)) {
        if (message) *message = @"Hook 配置父目录不存在或不是普通目录。";
        return NO;
    }
    NSString *root = [preferences stringByAppendingPathComponent:@"com.modhw.ios.profiles"];
    NSString *backupRoot = [root stringByAppendingPathComponent:(global ? @"global-backups" : @"backups")];
    if (!EnsureRootMobileDirectory(root, 0750, mobile->pw_gid) ||
        !EnsureRootMobileDirectory(backupRoot, 0750, mobile->pw_gid)) {
        if (message) *message = @"无法安全创建或验证 Hook 配置目录。";
        return NO;
    }

    NSString *target = global ? [preferences stringByAppendingPathComponent:@"com.modhw.ios.devices.plist"] : [[root stringByAppendingPathComponent:bundleID] stringByAppendingPathExtension:@"plist"];
    struct stat existing;
    BOOL hasExisting = lstat(target.fileSystemRepresentation, &existing) == 0;
    if (hasExisting && !S_ISREG(existing.st_mode)) {
        if (message) *message = @"目标配置不是普通文件，拒绝覆盖。";
        return NO;
    }
    if (!hasExisting && errno != ENOENT) {
        if (message) *message = @"无法检查目标配置文件。";
        return NO;
    }

    NSString *backupPath = nil;
    if (hasExisting) {
        NSData *oldData = [NSData dataWithContentsOfFile:target options:NSDataReadingMappedIfSafe error:nil];
        if (!oldData || oldData.length == 0) {
            if (message) *message = @"无法读取旧配置，未进行覆盖。";
            return NO;
        }
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *backupLabel = global ? @"global" : bundleID;
        NSString *backupName = [NSString stringWithFormat:@"%@-%@-%d.plist", backupLabel, [formatter stringFromDate:[NSDate date]], getpid()];
        backupPath = [backupRoot stringByAppendingPathComponent:backupName];
        if (!WriteSecureFile(backupPath, oldData, mobile->pw_gid)) {
            if (message) *message = @"旧配置备份失败，已取消写入。";
            return NO;
        }
    }

    NSError *serializationError = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:profile
                                                                    format:NSPropertyListXMLFormat_v1_0
                                                                   options:0
                                                                     error:&serializationError];
    if (!plistData) {
        if (message) *message = [NSString stringWithFormat:@"Hook 配置序列化失败：%@", serializationError.localizedDescription ?: @"未知错误"];
        return NO;
    }
    if (!WriteSecureFile(target, plistData, mobile->pw_gid)) {
        if (message) *message = @"Hook 配置原子写入失败；旧文件保持不变。";
        return NO;
    }
    if (!global && !AddBundleToSubstrateFilter(bundleID, &validationError)) {
        if (message) *message = validationError ?: @"Hook 注入目标登记失败。配置已保存，但尚未启用注入。";
        return NO;
    }
    if (message) {
        *message = backupPath
            ? [NSString stringWithFormat:@"已应用%@ Hook 配置。目标已加入注入白名单；请强制关闭并重新打开目标 App。旧配置备份：%@。", global ? @"全局" : [NSString stringWithFormat:@"App %@", bundleID], backupPath]
            : [NSString stringWithFormat:@"已应用%@ Hook 配置。目标已加入注入白名单；请强制关闭并重新打开目标 App。", global ? @"全局" : [NSString stringWithFormat:@"App %@", bundleID]];
    }
    return YES;
}
static NSDictionary *ExecuteRequest(NSDictionary *request) {
    NSString *action = request[@"action"];
    if (![action isKindOfClass:NSString.class]) return Failure(@"缺少操作类型。");

    if ([action isEqualToString:@"status"]) {
        return @{@"ok": @YES, @"paired": @NO, @"helper": @"Alpha11 Maintenance Helper"};
    }

    BOOL isGlobalProfile = [action isEqualToString:@"apply-global-profile"];
    if (isGlobalProfile || [action isEqualToString:@"apply-profile"]) {
        NSString *bundleID = request[@"bundleID"];
        BOOL confirm = [request[@"confirm"] isKindOfClass:NSNumber.class] && [request[@"confirm"] boolValue];
        if (!confirm) return Failure(@"应用 Hook 配置必须明确确认。");
        NSString *message = nil;
        if (!ApplyHookProfile(isGlobalProfile ? nil : bundleID, request[@"profile"], isGlobalProfile, &message))
            return Failure(message ?: @"Hook 配置应用失败。");
        return @{@"ok": @YES, @"action": action, @"output": message ?: @"Hook 配置已写入。"};
    }

    NSString *path = nil;
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    NSString *bundleID = request[@"bundleID"];
    NSString *archive = request[@"archive"];
    BOOL confirm = [request[@"confirm"] isKindOfClass:NSNumber.class] && [request[@"confirm"] boolValue];

    if ([action isEqualToString:@"backup"]) {
        if (!ValidBundleID(bundleID)) return Failure(@"Bundle ID 格式无效。");
        path = @"/var/jb/usr/bin/mod-hw-app-backup";
        [arguments addObject:bundleID];
    } else if ([action isEqualToString:@"verify"]) {
        if (!ValidArchiveName(archive)) return Failure(@"备份文件名无效。");
        path = @"/var/jb/usr/bin/mod-hw-app-backup-verify";
        [arguments addObject:archive];
    } else if ([action isEqualToString:@"restore"]) {
        if (!ValidBundleID(bundleID) || !ValidArchiveName(archive) || !confirm)
            return Failure(@"还原必须提供有效 Bundle ID、备份文件名和明确确认。");
        path = @"/var/jb/usr/bin/mod-hw-app-restore";
        [arguments addObjectsFromArray:@[bundleID, archive, @"--confirm"]];
    } else if ([action isEqualToString:@"clean"]) {
        if (!ValidBundleID(bundleID) || !confirm)
            return Failure(@"清理必须提供有效 Bundle ID 和明确确认。");
        path = @"/var/jb/usr/bin/mod-hw-app-clean";
        [arguments addObjectsFromArray:@[bundleID, @"--confirm"]];
    } else if ([action isEqualToString:@"config-backup"]) {
        path = @"/var/jb/usr/bin/mod-hw-config-backup";
    } else if ([action isEqualToString:@"config-restore"]) {
        if (!confirm) return Failure(@"配置还原必须明确确认。");
        path = @"/var/jb/usr/bin/mod-hw-config-restore";
    } else if ([action isEqualToString:@"keychain-diagnose"]) {
        if (!ValidBundleID(bundleID)) return Failure(@"Bundle ID 格式无效。");
        path = @"/var/jb/usr/bin/mod-hw-keychain-diagnose";
        [arguments addObject:bundleID];
    } else if ([action isEqualToString:@"diagnose-config"]) {
        path = @"/var/jb/usr/bin/mod-hw-diagnose";
    } else if ([action isEqualToString:@"selftest"]) {
        path = @"/var/jb/usr/bin/mod-hw-selftest";
    } else if ([action isEqualToString:@"acceptance-iphone12"]) {
        path = @"/var/jb/usr/bin/mod-hw-acceptance-iphone12";
    } else {
        return Failure(@"只允许 status、backup、verify、restore、clean、config-backup、config-restore、keychain-diagnose、diagnose-config、selftest、acceptance-iphone12。");
    }

    if (access(path.fileSystemRepresentation, X_OK) != 0) return Failure(@"维护脚本未安装或不可执行。");
    NSString *output = @"";
    BOOL timedOut = NO, truncated = NO;
    int exitCode = RunFixedTool(path.fileSystemRepresentation, arguments, &output, &timedOut, &truncated);
    NSMutableDictionary *response = [@{
        @"ok": (exitCode == 0 ? @YES : @NO),
        @"action": action,
        @"exitCode": @(exitCode),
        @"output": output
    } mutableCopy];
    if (timedOut) response[@"error"] = @"操作超过 300 秒，已终止执行。";
    if (truncated) response[@"outputTruncated"] = @YES;
    return response;
}

static void HandleClient(int fd) {
    struct timeval timeout = {.tv_sec = 5, .tv_usec = 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    pid_t peer = 0;
    if (!PeerIsTrustedCore(fd, &peer)) {
        SendJSON(fd, Failure(@"仅允许已安装的 iDeviceLab Core 服务连接。"));
        return;
    }
    NSDictionary *request = nil;
    if (!ReadRequest(fd, &request)) {
        SendJSON(fd, Failure(@"请求格式无效或超过长度限制。"));
        return;
    }
    NSString *action = request[@"action"];
    NSNumber *managerPIDValue = request[@"managerPID"];
    if (![managerPIDValue isKindOfClass:NSNumber.class] ||
        managerPIDValue.longLongValue <= 1 || managerPIDValue.longLongValue > INT_MAX) {
        SendJSON(fd, Failure(@"缺少有效的 Manager 进程标识。"));
        return;
    }
    pid_t managerPID = (pid_t)managerPIDValue.intValue;
    if (managerPID <= 1) {
        SendJSON(fd, Failure(@"Manager 进程标识无效。"));
        return;
    }
    if ([action isEqualToString:@"status"]) {
        BOOL paired = PeerMatchesPinned(managerPID);
        SendJSON(fd, @{@"ok": @YES, @"paired": @(paired), @"helper": @"Alpha11 Maintenance Helper"});
        return;
    }
    if ([action isEqualToString:@"pair"]) {
        NSString *message = nil;
        BOOL paired = PairManagerProcess(managerPID, &message);
        SendJSON(fd, paired
            ? @{@"ok": @YES, @"paired": @YES, @"action": @"pair", @"output": message ?: @"配对成功。"}
            : @{@"ok": @NO, @"paired": @NO, @"action": @"pair", @"error": message ?: @"配对失败。"});
        return;
    }
    if (!PeerMatchesPinned(managerPID)) {
        SendJSON(fd, Failure(@"管理器尚未配对或签名已变化；请在管理器设置中点击“直接配对权限助手”。"));
        return;
    }
    SendJSON(fd, ExecuteRequest(request));
}

int main(void) {
    @autoreleasepool {
        if (geteuid() != 0) return 1;
        signal(SIGPIPE, SIG_IGN);
        setenv("PATH", "/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin", 1);
        setenv("HOME", "/var/root", 1);
        struct passwd *mobile = getpwnam("mobile");
        if (!mobile) return 2;

        struct stat existing;
        if (lstat(kSocketPath, &existing) == 0) {
            if (!S_ISSOCK(existing.st_mode) || existing.st_uid != 0) return 3;
            if (unlink(kSocketPath) != 0) return 4;
        } else if (errno != ENOENT) {
            return 5;
        }

        int server = socket(AF_UNIX, SOCK_STREAM, 0);
        if (server < 0) return 6;
        struct sockaddr_un address = {0};
        address.sun_family = AF_UNIX;
        strlcpy(address.sun_path, kSocketPath, sizeof(address.sun_path));
        if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0) {
            close(server);
            return 7;
        }
        if (chown(kSocketPath, 0, mobile->pw_gid) != 0 || chmod(kSocketPath, 0660) != 0 ||
            listen(server, 8) != 0) {
            unlink(kSocketPath);
            close(server);
            return 8;
        }

        for (;;) {
            int client = accept(server, NULL, NULL);
            if (client < 0) {
                if (errno == EINTR) continue;
                sleep(1);
                continue;
            }
            @autoreleasepool { HandleClient(client); }
            close(client);
        }
    }
    return 0;
}
