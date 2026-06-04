#include "MacAppDelegate.hpp"

#import <Cocoa/Cocoa.h>

int main() {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        DietCodeAppDelegate* delegate = [[DietCodeAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }

    return 0;
}
