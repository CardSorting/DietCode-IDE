#import "MacControlWorkspaceState.hpp"
#import "MacControlWindowBridge.hpp"
#import "MacControlSupport.hpp"
#import "MacControlPathSecurity.hpp"

@implementation MacControlWorkspaceState {
    NSInteger _revisionCounter;
    NSDictionary* _lastMutationReceipt;
    NSArray<NSString*>* _lastChangedFiles;
    NSString* _lastMutationSource;
    BOOL _externalChangeDetected;
    NSMutableDictionary<NSString*, NSDictionary*>* _completedOperations;
    NSMutableDictionary<NSString*, NSString*>* _trackedFileHashes;
    NSMutableSet<NSString*>* _externallyChangedPaths;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _revisionCounter = 1;
        _lastChangedFiles = @[];
        _lastMutationSource = @"none";
        _completedOperations = [NSMutableDictionary dictionary];
        _trackedFileHashes = [NSMutableDictionary dictionary];
        _externallyChangedPaths = [NSMutableSet set];
    }
    return self;
}

- (NSInteger)revisionId {
    return _revisionCounter;
}

- (NSDictionary*)lastMutationReceipt {
    return _lastMutationReceipt ?: @{};
}

- (NSArray<NSString*>*)lastChangedFiles {
    return _lastChangedFiles ?: @[];
}

- (NSString*)lastMutationSource {
    return _lastMutationSource ?: @"none";
}

- (BOOL)externalChangeDetected {
    return _externalChangeDetected;
}

- (void)bumpRevision {
    _revisionCounter++;
}

- (NSDictionary*)revisionPayloadWithWorkspace:(NSString*)workspacePath {
    return @{
        @"revisionId": @(_revisionCounter),
        @"workspacePath": workspacePath ?: @"",
        @"changedFiles": self.lastChangedFiles,
        @"lastMutationReceipt": self.lastMutationReceipt,
        @"lastMutationSource": self.lastMutationSource,
        @"externalChangeDetected": @(_externalChangeDetected),
        @"externallyChangedPaths": _externallyChangedPaths.allObjects ?: @[],
        @"mode": @"workspace_revision"
    };
}

static NSString* ReadHashForPath(NSString* absPath, DietCodeControlWindowBridge* windowBridge) {
    NSString* readSource = nil;
    NSString* text = TextForSearchAtPath([windowBridge textForFileAtPath:absPath], absPath, &readSource);
    if (!text) {
        NSError* err = nil;
        text = [NSString stringWithContentsOfFile:absPath encoding:NSUTF8StringEncoding error:&err];
    }
    return StableHashForString(text ?: @"");
}

- (NSDictionary*)snapshotPayloadWithWorkspace:(NSString*)workspacePath
                                 sinceRevision:(NSNumber*)sinceRevision
                                         paths:(NSArray<NSString*>*)paths
                                  snapshotMode:(NSString*)snapshotMode
                                      maxFiles:(NSNumber*)maxFiles
                                  windowBridge:(DietCodeControlWindowBridge*)windowBridge {
    NSInteger since = sinceRevision ? [sinceRevision integerValue] : 0;
    NSInteger limit = maxFiles ? MAX([maxFiles integerValue], 1) : 100;
    if (limit > 500) limit = 500;
    NSString* mode = snapshotMode.length > 0 ? snapshotMode : @"mutated_only";
    NSMutableArray* changedFiles = [NSMutableArray array];
    NSMutableDictionary* fileHashes = [NSMutableDictionary dictionary];
    BOOL externalDetected = NO;
    NSInteger filesSkipped = 0;
    NSInteger filesHashed = 0;
    BOOL truncated = NO;

    NSMutableArray<NSString*>* inspectPaths = [NSMutableArray array];
    if ([mode isEqualToString:@"explicit_paths"]) {
        for (NSString* p in paths ?: @[]) {
            if (p.length > 0) [inspectPaths addObject:p];
        }
    } else if ([mode isEqualToString:@"tracked_files"]) {
        for (NSString* tracked in _trackedFileHashes.allKeys) {
            [inspectPaths addObject:tracked];
        }
    } else {
        NSMutableSet<NSString*>* mutated = [NSMutableSet set];
        for (NSString* p in paths ?: @[]) {
            if (p.length > 0) [mutated addObject:p];
        }
        for (NSString* p in self.lastChangedFiles) [mutated addObject:p];
        for (NSString* p in _externallyChangedPaths) [mutated addObject:p];
        for (NSString* tracked in _trackedFileHashes.allKeys) [mutated addObject:tracked];
        inspectPaths = [NSMutableArray arrayWithArray:[[mutated allObjects] sortedArrayUsingSelector:@selector(compare:)]];
    }

    for (NSString* relPath in inspectPaths) {
        if (filesHashed >= limit) {
            truncated = YES;
            filesSkipped++;
            continue;
        }
        NSString* absPath = AbsolutePathForRPCPath(relPath, workspacePath);
        if (!absPath || !PathIsInsideWorkspace(absPath, workspacePath)) {
            filesSkipped++;
            continue;
        }
        if (PathIsSymlink(absPath)) {
            filesSkipped++;
            continue;
        }
        NSString* currentHash = ReadHashForPath(absPath, windowBridge);
        fileHashes[relPath] = currentHash;
        filesHashed++;
        NSString* priorHash = _trackedFileHashes[relPath];
        if (since > 0 && since < _revisionCounter && priorHash.length > 0 && ![priorHash isEqualToString:currentHash]) {
            [changedFiles addObject:@{
                @"path": relPath,
                @"priorContentHash": priorHash,
                @"currentContentHash": currentHash,
                @"source": [_externallyChangedPaths containsObject:relPath] ? @"external" : @"unknown"
            }];
            externalDetected = YES;
        }
    }

    BOOL complete = !truncated && filesSkipped == 0;
    return @{
        @"revisionId": @(_revisionCounter),
        @"snapshotId": [NSString stringWithFormat:@"snap-%ld", (long)_revisionCounter],
        @"sinceRevision": @(since),
        @"revisionDelta": @(MAX(0, _revisionCounter - since)),
        @"snapshotMode": mode,
        @"fileHashes": fileHashes,
        @"changedFiles": changedFiles,
        @"filesHashed": @(filesHashed),
        @"filesSkipped": @(filesSkipped),
        @"complete": @(complete),
        @"truncated": @(truncated),
        @"hashAlgorithm": @"fnv1a_16hex",
        @"externalChangeDetected": @(externalDetected || _externalChangeDetected),
        @"mode": @"workspace_snapshot"
    };
}

- (NSDictionary*)operationStatusForKey:(NSString*)idempotencyKey {
    if (idempotencyKey.length == 0) {
        return @{ @"status": @"unknown", @"reason": @"idempotencyKey required" };
    }
    NSDictionary* record = _completedOperations[idempotencyKey];
    if (!record) {
        return @{ @"status": @"unknown", @"idempotencyKey": idempotencyKey };
    }
    NSMutableDictionary* payload = [record mutableCopy];
    payload[@"status"] = @"completed";
    return payload;
}

- (void)trackHashesForPaths:(NSArray<NSString*>*)paths workspace:(NSString*)ws windowBridge:(DietCodeControlWindowBridge*)windowBridge {
    for (NSString* relPath in paths) {
        NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
        if (!absPath) continue;
        _trackedFileHashes[relPath] = ReadHashForPath(absPath, windowBridge);
    }
}

- (void)recordAgentMutationWithReceipt:(NSDictionary*)receipt
                          changedPaths:(NSArray<NSString*>*)paths
                        idempotencyKey:(NSString*)idempotencyKey
                        revisionBefore:(NSInteger)revisionBefore {
    NSInteger revisionAfter = _revisionCounter + 1;
    [self bumpRevision];
    _lastMutationReceipt = receipt ?: @{};
    _lastChangedFiles = paths ?: @[];
    _lastMutationSource = @"agent";
    [_externallyChangedPaths minusSet:[NSSet setWithArray:paths ?: @[]]];
    if (_externallyChangedPaths.count == 0) _externalChangeDetected = NO;

    if (idempotencyKey.length > 0) {
        _completedOperations[idempotencyKey] = @{
            @"idempotencyKey": idempotencyKey,
            @"mutationReceipt": receipt ?: @{},
            @"revisionBefore": @(revisionBefore),
            @"revisionAfter": @(revisionAfter),
            @"changedFiles": paths ?: @[],
            @"completedAt": @([[NSDate date] timeIntervalSince1970])
        };
    }
}

- (void)recordBatchMutationWithReceipt:(NSDictionary*)batchReceipt
                           changedPaths:(NSArray<NSString*>*)paths
                         idempotencyKey:(NSString*)idempotencyKey
                         revisionBefore:(NSInteger)revisionBefore {
    NSInteger revisionAfter = _revisionCounter + 1;
    [self bumpRevision];
    _lastMutationReceipt = batchReceipt ?: @{};
    _lastChangedFiles = paths ?: @[];
    _lastMutationSource = @"agent";
    [_externallyChangedPaths minusSet:[NSSet setWithArray:paths ?: @[]]];
    if (_externallyChangedPaths.count == 0) _externalChangeDetected = NO;

    if (idempotencyKey.length > 0) {
        _completedOperations[idempotencyKey] = @{
            @"idempotencyKey": idempotencyKey,
            @"batchMutationReceipt": batchReceipt ?: @{},
            @"revisionBefore": @(revisionBefore),
            @"revisionAfter": @(revisionAfter),
            @"changedFiles": paths ?: @[],
            @"completedAt": @([[NSDate date] timeIntervalSince1970])
        };
    }
}

- (void)noteExternalChangeForPath:(NSString*)path {
    if (path.length == 0) return;
    [_externallyChangedPaths addObject:path];
    _externalChangeDetected = YES;
    _lastMutationSource = @"external";
}

- (void)clearExternalChangeFlag {
    _externalChangeDetected = NO;
    [_externallyChangedPaths removeAllObjects];
}

@end
