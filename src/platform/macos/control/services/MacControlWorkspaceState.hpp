#pragma once

#import <Foundation/Foundation.h>

@class DietCodeControlWindowBridge;

// INVARIANT: Monotonic workspace revision + operation registry for transaction kernel.
@interface MacControlWorkspaceState : NSObject

@property (nonatomic, readonly) NSInteger revisionId;
@property (nonatomic, readonly, copy) NSDictionary* lastMutationReceipt;
@property (nonatomic, readonly, copy) NSArray<NSString*>* lastChangedFiles;
@property (nonatomic, readonly, copy) NSString* lastMutationSource;
@property (nonatomic, readonly) BOOL externalChangeDetected;

- (NSDictionary*)revisionPayloadWithWorkspace:(NSString*)workspacePath;
- (NSDictionary*)snapshotPayloadWithWorkspace:(NSString*)workspacePath
                                 sinceRevision:(NSNumber*)sinceRevision
                                         paths:(NSArray<NSString*>*)paths
                                  windowBridge:(DietCodeControlWindowBridge*)windowBridge;
- (NSDictionary*)operationStatusForKey:(NSString*)idempotencyKey;

- (void)recordAgentMutationWithReceipt:(NSDictionary*)receipt
                          changedPaths:(NSArray<NSString*>*)paths
                        idempotencyKey:(NSString*)idempotencyKey
                        revisionBefore:(NSInteger)revisionBefore;
- (void)recordBatchMutationWithReceipt:(NSDictionary*)batchReceipt
                           changedPaths:(NSArray<NSString*>*)paths
                         idempotencyKey:(NSString*)idempotencyKey
                         revisionBefore:(NSInteger)revisionBefore;
- (void)noteExternalChangeForPath:(NSString*)path;
- (void)clearExternalChangeFlag;
- (void)trackHashesForPaths:(NSArray<NSString*>*)paths workspace:(NSString*)ws windowBridge:(DietCodeControlWindowBridge*)windowBridge;

@end
