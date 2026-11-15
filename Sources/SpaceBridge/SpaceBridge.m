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

BOOL SSAddWindowToSpace(uint32_t windowID, uint64_t spaceID) {
    if (windowID == 0 || spaceID == 0) return NO;
    void (*fn)(int, CFArrayRef, CFArrayRef) = symbol("SLSAddWindowsToSpaces");
    if (!fn) fn = symbol("CGSAddWindowsToSpaces");
    if (!fn) return NO;
    int cid = connection();
    if (cid == 0) return NO;
    fn(cid, (__bridge CFArrayRef)@[@(windowID)], (__bridge CFArrayRef)@[@(spaceID)]);
    return YES;
}

BOOL SSRemoveWindowFromSpaces(uint32_t windowID, NSArray<NSNumber *> *spaceIDs) {
    if (windowID == 0 || spaceIDs.count == 0) return NO;
    void (*fn)(int, CFArrayRef, CFArrayRef) = symbol("SLSRemoveWindowsFromSpaces");
    if (!fn) fn = symbol("CGSRemoveWindowsFromSpaces");
    if (!fn) return NO;
    int cid = connection();
    if (cid == 0) return NO;
    fn(cid, (__bridge CFArrayRef)@[@(windowID)], (__bridge CFArrayRef)spaceIDs);
    return YES;
}

BOOL SSPostSyntheticSwipe(BOOL isRight) {
    double magic = 1.401298464324817e-45;
    double dX = isRight ? 400.0 : -400.0;
    double vX = isRight ? 2.0 : -2.0;
    int dir = isRight ? 1 : 0;

    CGEventRef e1 = CGEventCreate(NULL);
    CGEventRef e2 = CGEventCreate(NULL);
    if (!e1 || !e2) {
        if (e1) CFRelease(e1);
        if (e2) CFRelease(e2);
        return NO;
    }

    CGEventSetIntegerValueField(e1, 55, 29);
    CGEventSetIntegerValueField(e2, 55, 30);
    CGEventSetIntegerValueField(e2, 110, 23);
    CGEventSetIntegerValueField(e2, 132, 1); // Phase = Began
    CGEventSetIntegerValueField(e2, 135, dir);
    CGEventSetIntegerValueField(e2, 123, 1);
    CGEventSetDoubleValueField(e2, 119, 0.0);
    CGEventSetDoubleValueField(e2, 139, magic);

    CGEventPost(kCGHIDEventTap, e2);
    CGEventPost(kCGHIDEventTap, e1);
    CFRelease(e1);
    CFRelease(e2);

    CGEventRef e3 = CGEventCreate(NULL);
    CGEventRef e4 = CGEventCreate(NULL);
    if (!e3 || !e4) {
        if (e3) CFRelease(e3);
        if (e4) CFRelease(e4);
        return NO;
    }

    CGEventSetIntegerValueField(e3, 55, 29);
    CGEventSetIntegerValueField(e4, 55, 30);
    CGEventSetIntegerValueField(e4, 110, 23);
    CGEventSetIntegerValueField(e4, 132, 4); // Phase = Ended
    CGEventSetDoubleValueField(e4, 124, vX);
    CGEventSetIntegerValueField(e4, 135, dir);
    CGEventSetIntegerValueField(e4, 123, 1);
    CGEventSetDoubleValueField(e4, 119, 0.0);
    CGEventSetDoubleValueField(e4, 129, dX);
    CGEventSetDoubleValueField(e4, 130, 0.0);
    CGEventSetDoubleValueField(e4, 139, magic);

    CGEventPost(kCGHIDEventTap, e4);
    CGEventPost(kCGHIDEventTap, e3);
    CFRelease(e3);
    CFRelease(e4);

    return YES;
}

uint32_t SSWindowID(AXUIElementRef window) {
    AXError (*fn)(AXUIElementRef, uint32_t *) = symbol("_AXUIElementGetWindow");
    uint32_t wid = 0;
    if (fn) fn(window, &wid);
    return wid;
}
