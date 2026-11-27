#ifndef IDEVELAB_CODESIGN_COMPAT_H
#define IDEVELAB_CODESIGN_COMPAT_H

#include <sys/types.h>
#include <stddef.h>

/*
 * iOS 16 public SDKs may omit sys/codesign.h even though the XNU csops
 * interface is present on the target kernel. Keep the ABI constants aligned
 * with Apple's XNU bsd/sys/codesign.h and osfmk/kern/cs_blobs.h.
 */
#if __has_include(<sys/codesign.h>)
#include <sys/codesign.h>
#else
#define CS_OPS_STATUS 0
#define CS_OPS_CDHASH 5
#define CS_VALID 0x00000001
#define CS_KILLED 0x01000000
#define CS_CDHASH_LEN 20
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
#endif

#endif
