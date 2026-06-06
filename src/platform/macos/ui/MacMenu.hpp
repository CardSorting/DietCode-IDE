#pragma once

#import <Cocoa/Cocoa.h>

@class DietCodeWindowController;

@interface DietCodeMenuBuilder : NSObject

+ (void)installMainMenuWithTarget:(DietCodeWindowController*)target;

@end
