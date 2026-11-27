#import <Foundation/Foundation.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/codesign.h>
#include <sys/sysctl.h>
#include <pwd.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <poll.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>

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
    if (count < 40) return NO;
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
    if (csops(pid, CS_OPS_STATUS, &status, sizeof(status)) != 0 ||
        (status & CS_VALID) == 0 || (status & CS_KILLED) != 0) return NO;
    uint8_t expected[CS_CDHASH_LEN] = {0};
    uint8_t actual[CS_CDHASH_LEN] = {0};
    if (!ReadPinnedHash(expected) || csops(pid, CS_OPS_CDHASH, actual, sizeof(actual)) != 0) return NO;
    return memcmp(expected, actual, sizeof(expected)) == 0;
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

static NSDictionary *ExecuteRequest(NSDictionary *request) {
    NSString *action = request[@"action"];
    if (![action isKindOfClass:NSString.class]) return Failure(@"缺少操作类型。");

    if ([action isEqualToString:@"status"]) {
        return @{@"ok": @YES, @"paired": @NO, @"helper": @"Alpha11 Maintenance Helper"};
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
    } else {
        return Failure(@"只允许 status、backup、verify、restore、clean。");
    }

    if (access(path.fileSystemRepresentation, X_OK) != 0) return Failure(@"维护脚本未安装或不可执行。");
    NSString *output = @"";
    BOOL timedOut = NO, truncated = NO;
    int exitCode = RunFixedTool(path.fileSystemRepresentation, arguments, &output, &timedOut, &truncated);
    NSMutableDictionary *response = [@{
        @"ok": @(exitCode == 0),
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
    if (!PeerIsMobile(fd, &peer)) {
        SendJSON(fd, Failure(@"仅允许本机 mobile 用户连接。"));
        return;
    }
    NSDictionary *request = nil;
    if (!ReadRequest(fd, &request)) {
        SendJSON(fd, Failure(@"请求格式无效或超过长度限制。"));
        return;
    }
    NSString *action = request[@"action"];
    if ([action isEqualToString:@"status"]) {
        BOOL paired = PeerMatchesPinned(peer);
        SendJSON(fd, @{@"ok": @YES, @"paired": @(paired), @"helper": @"Alpha11 Maintenance Helper"});
        return;
    }
    if (!PeerMatchesPinned(peer)) {
        SendJSON(fd, Failure(@"管理器尚未配对或签名已变化；请在越狱终端重新配对。"));
        return;
    }
    SendJSON(fd, ExecuteRequest(request));
}

int main(void) {
    @autoreleasepool {
        if (geteuid() != 0) return 1;
        signal(SIGPIPE, SIG_IGN);
        struct passwd *mobile = getpwnam("mobile");
        if (!mobile) return 2;

        struct stat existing;
        if (lstat(kSocketPath, &existing) == 0) {
            if (!S_ISSOCK(existing.st_mode)) return 3;
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
