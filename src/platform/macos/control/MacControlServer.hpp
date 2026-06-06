#pragma once

#import <Cocoa/Cocoa.h>

@class DietCodeWindowController;

@interface DietCodeControlServer : NSObject

@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, weak, readonly) DietCodeWindowController* windowController;

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller;
- (void)start;
- (void)stop;
- (void)appendLogLine:(NSString*)line;
- (void)notifyEvent:(NSString*)type detail:(NSString*)detail;

@end
