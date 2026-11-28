#import <dlfcn.h>
#import <Foundation/Foundation.h>
#import "HookUtil.h"

static void *SubstrateHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Rootless Dopamine installs jailbreak frameworks under /var/jb.
        // Keep the rootful locations only as compatibility fallbacks.
        const char *paths[] = {
            "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            "/var/jb/usr/lib/libsubstrate.dylib",
            "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            "/usr/lib/libsubstrate.dylib",
            NULL
        };
        for (NSUInteger i = 0; paths[i] != NULL; i++) {
            handle = dlopen(paths[i], RTLD_NOW | RTLD_GLOBAL);
            if (handle != NULL) {
                NSLog(@"[mod_hw] Loaded Substrate runtime from %s", paths[i]);
                break;
            }
        }
    });
    return handle;
}

static void *SubstrateSymbol(const char *name) {
    if (name == NULL) return NULL;
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol != NULL) return symbol;
    void *handle = SubstrateHandle();
    if (handle != NULL) {
        symbol = dlsym(handle, name);
        if (symbol != NULL) return symbol;
    }
    NSLog(@"[mod_hw] Substrate symbol unavailable: %s", name);
    return NULL;
}

void _HookFunction(const char *lib, const char *fun, void *hook, void **old) {
    void *image = (lib != NULL) ? dlopen(lib, RTLD_LAZY | RTLD_LOCAL) : NULL;
    void *symbol = (image != NULL && fun != NULL) ? dlsym(image, fun) : NULL;
    void (*hookFunction)(void *, void *, void **) =
        (void (*)(void *, void *, void **))SubstrateSymbol("MSHookFunction");
    if (symbol != NULL && hookFunction != NULL && hook != NULL && old != NULL) {
        hookFunction(symbol, hook, old);
    } else {
        if (old != NULL) *old = NULL;
        NSLog(@"[mod_hw] _HookFunction skipped: library=%s symbol=%s runtime=%s",
              lib ?: "(null)", fun ?: "(null)", hookFunction ? "available" : "missing");
    }
}

void CallMSHookFunction(void *symbol, void *hook, void **old) {
    void (*hookFunction)(void *, void *, void **) =
        (void (*)(void *, void *, void **))SubstrateSymbol("MSHookFunction");
    if (symbol == NULL || hook == NULL || old == NULL || hookFunction == NULL) {
        if (old != NULL) *old = NULL;
        NSLog(@"[mod_hw] MSHookFunction not installed: target=%p hook=%p runtime=%s",
              symbol, hook, hookFunction ? "available" : "missing");
        return;
    }
    hookFunction(symbol, hook, old);
    NSLog(@"[mod_hw] MSHookFunction invoked: target=%p original=%p", symbol, *old);
}

void* CallMSFindSymbol(MSImageRef image, const char *name) {
    void *(*findSymbol)(MSImageRef, const char *) =
        (void *(*)(MSImageRef, const char *))SubstrateSymbol("MSFindSymbol");
    if (findSymbol == NULL || name == NULL) return NULL;
    return findSymbol(image, name);
}

MSImageRef CallMSGetImageByName(const char *file) {
    MSImageRef (*getImage)(const char *) =
        (MSImageRef (*)(const char *))SubstrateSymbol("MSGetImageByName");
    if (getImage == NULL || file == NULL) return NULL;
    return getImage(file);
}

void _HookMessage(Class cls, const char *msg, void *hook, void **old) {
    if (cls == Nil || msg == NULL || hook == NULL || old == NULL) {
        if (old != NULL) *old = NULL;
        return;
    }
    char name[1024];
    size_t length = strnlen(msg, sizeof(name) - 1);
    for (size_t i = 0; i < length; i++) name[i] = (msg[i] == '_') ? ':' : msg[i];
    name[length] = '\0';
    SEL selector = sel_registerName(name);
    void (*hookMessage)(Class, SEL, void *, void **) =
        (void (*)(Class, SEL, void *, void **))SubstrateSymbol("MSHookMessageEx");
    if (hookMessage != NULL) {
        hookMessage(cls, selector, hook, old);
        NSLog(@"[mod_hw] MSHookMessageEx invoked: %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector));
        return;
    }
    Method method = class_getInstanceMethod(cls, selector);
    if (method != NULL) {
        *old = (void *)method_setImplementation(method, (IMP)hook);
        NSLog(@"[mod_hw] Objective-C method fallback installed: %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector));
    } else {
        *old = NULL;
        NSLog(@"[mod_hw] Objective-C method not found: %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector));
    }
}
