#import <Foundation/Foundation.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/codesign.h>
#include <fcntl.h>
#include <stdio.h>
#include <limits.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

static const char *kPinDirectory = "/var/jb/var/root/Library/Preferences";
static const char *kPinPath = "/var/jb/var/root/Library/Preferences/com.idevelab.manager-cdhash";

static BOOL ProcessExecutablePath(pid_t pid, char output[4096]) {
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

static BOOL ReadCodeHash(pid_t pid, uint8_t output[CS_CDHASH_LEN]) {
    uint32_t status = 0;
    if (csops(pid, CS_OPS_STATUS, &status, sizeof(status)) != 0 ||
        (status & CS_VALID) == 0 || (status & CS_KILLED) != 0) return NO;
    return csops(pid, CS_OPS_CDHASH, output, CS_CDHASH_LEN) == 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (geteuid() != 0) {
            fprintf(stderr, "必须以 root 身份运行：su -c mod-hw-manager-pair <PID>\n");
            return 1;
        }
        if (argc != 2) {
            fprintf(stderr, "用法：mod-hw-manager-pair <管理器进程 PID>\n");
            return 2;
        }
        char *end = NULL;
        long rawPID = strtol(argv[1], &end, 10);
        if (!end || *end != '\0' || rawPID <= 1 || rawPID > INT_MAX) {
            fprintf(stderr, "PID 无效。\n");
            return 2;
        }
        pid_t pid = (pid_t)rawPID;
        char executable[4096] = {0};
        if (!ProcessExecutablePath(pid, executable)) {
            fprintf(stderr, "无法读取该进程的可执行路径；未配对。\n");
            return 3;
        }
        NSString *executablePath = [NSString stringWithUTF8String:executable];
        NSRange marker = [executablePath rangeOfString:@".app/" options:NSBackwardsSearch];
        if (marker.location == NSNotFound) {
            fprintf(stderr, "目标进程不是应用包中的可执行文件：%s\n", executable);
            return 4;
        }
        NSString *appPath = [executablePath substringToIndex:marker.location + 4];
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *bundleID = info[@"CFBundleIdentifier"];
        if (![bundleID isEqualToString:@"com.modhw.manager"] ||
            ![appPath.lastPathComponent isEqualToString:@"ModHWManager.app"]) {
            fprintf(stderr, "Bundle ID 或应用名称不匹配：%s\n", executable);
            return 5;
        }

        uint8_t hash[CS_CDHASH_LEN] = {0};
        if (!ReadCodeHash(pid, hash)) {
            fprintf(stderr, "无法验证管理器代码签名；未配对。\n");
            return 6;
        }
        char hex[CS_CDHASH_LEN * 2 + 1] = {0};
        for (size_t i = 0; i < CS_CDHASH_LEN; i++) snprintf(hex + i * 2, 3, "%02x", hash[i]);

        fprintf(stderr, "将配对以下管理器进程：\nPID: %d\n路径: %s\nBundle ID: %s\nCDHash: %s\n", pid, executable, bundleID.UTF8String, hex);
        fprintf(stderr, "配对后仅此签名的管理器可调用受限维护助手；管理器更新后需要重新配对。\n输入 PAIR 确认：");
        char confirmation[32] = {0};
        if (!fgets(confirmation, sizeof(confirmation), stdin) || strcmp(confirmation, "PAIR\n") != 0) {
            fprintf(stderr, "已取消，未更改配对记录。\n");
            return 7;
        }

        NSError *directoryError = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:[NSString stringWithUTF8String:kPinDirectory]
                                   withIntermediateDirectories:YES
                                                    attributes:@{NSFilePosixPermissions: @0700}
                                                         error:&directoryError];
        struct stat directoryStat;
        if (lstat(kPinDirectory, &directoryStat) != 0 || !S_ISDIR(directoryStat.st_mode) ||
            directoryStat.st_uid != 0 || chmod(kPinDirectory, 0700) != 0) {
            fprintf(stderr, "配对目录不安全或不可写。\n");
            return 8;
        }

        char temporary[512];
        snprintf(temporary, sizeof(temporary), "%s.tmp.%d", kPinPath, getpid());
        int fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (fd < 0) {
            fprintf(stderr, "无法创建配对记录：%s\n", strerror(errno));
            return 9;
        }
        size_t length = strlen(hex);
        ssize_t written = write(fd, hex, length);
        BOOL saved = written == (ssize_t)length && fsync(fd) == 0 &&
                     fchown(fd, 0, 0) == 0 && fchmod(fd, 0600) == 0;
        close(fd);
        if (!saved || rename(temporary, kPinPath) != 0) {
            unlink(temporary);
            fprintf(stderr, "写入配对记录失败。\n");
            return 10;
        }
        fprintf(stdout, "管理器配对成功。现在可在管理器内直接执行受限维护操作。\n");
        return 0;
    }
}
