#pragma once

#import <Cocoa/Cocoa.h>

@class DietCodeWindowController;

@interface DietCodeAppDelegate : NSObject <NSApplicationDelegate>

@property(nonatomic, strong) DietCodeWindowController* windowController;

@end
