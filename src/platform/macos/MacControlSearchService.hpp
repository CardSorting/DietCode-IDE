#pragma once

#import <Foundation/Foundation.h>

@class DietCodeControlWindowBridge;

@interface MacControlSearchService : NSObject

- (instancetype)initWithWindowBridge:(DietCodeControlWindowBridge*)windowBridge;

- (NSDictionary*)workspaceGrep:(NSDictionary*)params 
                    outErrCode:(NSString**)outErrCode 
                     outErrMsg:(NSString**)outErrMsg;

- (NSDictionary*)searchFiles:(NSDictionary*)params 
                  outErrCode:(NSString**)outErrCode 
                   outErrMsg:(NSString**)outErrMsg;

- (NSDictionary*)searchText:(NSDictionary*)params 
                 outErrCode:(NSString**)outErrCode 
                  outErrMsg:(NSString**)outErrMsg;

- (NSDictionary*)searchTodo:(NSDictionary*)params 
                 outErrCode:(NSString**)outErrCode 
                  outErrMsg:(NSString**)outErrMsg;

- (NSDictionary*)searchDiagnostics:(NSDictionary*)params 
                        outErrCode:(NSString**)outErrCode 
                         outErrMsg:(NSString**)outErrMsg;

@end
