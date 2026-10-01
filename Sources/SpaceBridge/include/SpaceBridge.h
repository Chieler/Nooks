#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

NS_ASSUME_NONNULL_BEGIN
NSArray<NSDictionary *> *SSCopyDisplays(void);
NSArray<NSNumber *> *SSCopyWindowSpaces(uint32_t windowID);
BOOL SSToggleMissionControl(void);
BOOL SSCanSwitchSpaces(void);
BOOL SSSetCurrentSpace(NSString *displayIdentifier, uint64_t spaceID);
uint32_t SSWindowID(AXUIElementRef window);
NS_ASSUME_NONNULL_END
