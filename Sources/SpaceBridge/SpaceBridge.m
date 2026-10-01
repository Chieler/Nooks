#import "SpaceBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

static void *symbol(const char *name) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_GLOBAL);
    });
    return dlsym(RTLD_DEFAULT, name);
}

static int connection(void) {
    int (*fn)(void) = symbol("SLSMainConnectionID");
    if (!fn) fn = symbol("CGSMainConnectionID");
    return fn ? fn() : 0;
}

NSArray<NSDictionary *> *SSCopyDisplays(void) {
    CFArrayRef (*fn)(int) = symbol("SLSCopyManagedDisplaySpaces");
    if (!fn) fn = symbol("CGSCopyManagedDisplaySpaces");
    return fn ? CFBridgingRelease(fn(connection())) ?: @[] : @[];
}

NSArray<NSNumber *> *SSCopyWindowSpaces(uint32_t windowID) {
    CFArrayRef (*fn)(int, int, CFArrayRef) = symbol("SLSCopySpacesForWindows");
    if (!fn) fn = symbol("CGSCopySpacesForWindows");
    return fn ? CFBridgingRelease(fn(connection(), 7, (__bridge CFArrayRef)@[@(windowID)])) ?: @[] : @[];
}

BOOL SSToggleMissionControl(void) {
    CGError (*fn)(CFStringRef, int) = symbol("CoreDockSendNotification");
    return fn && fn(CFSTR("com.apple.expose.awake"), 0) == kCGErrorSuccess;
}

static void *switchSymbol(void) {
    void *fn = symbol("CGSManagedDisplaySetCurrentSpace");
    if (!fn) fn = symbol("SLSManagedDisplaySetCurrentSpace");
    return fn;
}

BOOL SSCanSwitchSpaces(void) {
    return switchSymbol() != NULL;
}

BOOL SSSetCurrentSpace(NSString *displayIdentifier, uint64_t spaceID) {
    void (*fn)(int, CFStringRef, uint64_t) = switchSymbol();
    if (!fn || displayIdentifier.length == 0 || spaceID == 0) return NO;
    fn(connection(), (__bridge CFStringRef)displayIdentifier, spaceID);
    return YES;
}

uint32_t SSWindowID(AXUIElementRef window) {
    AXError (*fn)(AXUIElementRef, uint32_t *) = symbol("_AXUIElementGetWindow");
    uint32_t wid = 0;
    if (fn) fn(window, &wid);
    return wid;
}
