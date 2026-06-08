#pragma once

#import "MacControlWindowBridge.hpp"

@class DietCodeWindowController;

@interface DietCodeLegacyWindowBridge : DietCodeControlWindowBridge

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller;

@end
