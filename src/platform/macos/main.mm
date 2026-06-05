#include "MacAppDelegate.hpp"

#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    BOOL headless = NO;
    for (int i = 1; i < argc; ++i) {
      if (strcmp(argv[i], "--headless") == 0) {
        headless = YES;
        break;
      }
    }

    NSApplication *app = [NSApplication sharedApplication];
    if (headless) {
      [app setActivationPolicy:NSApplicationActivationPolicyProhibited];
    } else {
      [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    }

    DietCodeAppDelegate *delegate = [[DietCodeAppDelegate alloc] init];
    delegate.isHeadless = headless;
    [app setDelegate:delegate];
    [app run];
  }

  return 0;
}

