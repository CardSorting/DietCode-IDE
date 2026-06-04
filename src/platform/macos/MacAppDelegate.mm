#include "platform/macos/MacAppDelegate.hpp"

#include "platform/macos/MacMenu.hpp"
#include "platform/macos/MacWindow.hpp"

#import <Cocoa/Cocoa.h>

@implementation DietCodeAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    self.windowController = [[DietCodeWindowController alloc] init];
    [DietCodeMenuBuilder installMainMenuWithTarget:self.windowController];
    [self.windowController showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    if (self.windowController != nil && ![self.windowController confirmCloseIfNeeded]) {
        return NSTerminateCancel;
    }
    return NSTerminateNow;
}

@end
