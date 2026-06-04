#include "MacAppDelegate.hpp"
#include "MacMenu.hpp"
#include "MacWindow.hpp"

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
    if (self.windowController != nil) {
        [self.windowController cleanupProcesses];
    }
    return NSTerminateNow;
}

@end
