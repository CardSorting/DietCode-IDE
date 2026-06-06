#import "MacControlPatchService.hpp"
#import "MacControlWindowBridge.hpp"
#import "MacControlSupport.hpp"
#import "MacControlPathSecurity.hpp"
#import "MacControlSerialization.hpp"
#import "MacControlDiffParsing.hpp"
#import "SymbolIndexService.hpp"
#import "DiffAnalysisService.hpp"

#include <filesystem>
#include <string>
#include <vector>

@implementation MacControlPatchService {
    DietCodeControlWindowBridge* _windowBridge;
    NSMutableArray<NSDictionary*>* _lastPatchRecords;
}

- (instancetype)initWithWindowBridge:(DietCodeControlWindowBridge*)bridge {
    self = [super init];
    if (self) {
        _windowBridge = bridge;
        _lastPatchRecords = [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSDictionary*>*)lastPatchRecords {
    return [_lastPatchRecords copy];
}

- (NSDictionary*)validatePatchAtPath:(NSString*)path patch:(NSString*)patch currentText:(NSString*)currentTextOverride {
    return [self validatePatchAtPath:path patch:patch currentText:currentTextOverride options:@{}];
}

- (NSDictionary*)validatePatchAtPath:(NSString*)path 
                               patch:(NSString*)patch 
                          currentText:(NSString*)currentTextOverride 
                              options:(NSDictionary*)options {
    NSString* ws = [_windowBridge workspacePath];
    NSString* targetPath = AbsolutePathForRPCPath(path, ws);
    BOOL insideWorkspace = ws.length > 0 && PathIsInsideWorkspace(targetPath, ws);
    BOOL targetExists = targetPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:targetPath];
    NSArray* hunks = HunkSummariesFromPatch(patch ?: @"");
    NSInteger changedLineCount = ChangedLineCountFromHunks(hunks);
    BOOL requiresConfirmation = (patch.length > kMaxPatchBytesBeforeConfirmation) || changedLineCount > 200;

    NSMutableDictionary* result = [@{
        @"ok": @NO,
        @"targetFileExists": @(targetExists),
        @"insideWorkspace": @(insideWorkspace),
        @"patchAppliesCleanly": @NO,
        @"changedLineCount": @(changedLineCount),
        @"affectedHunks": hunks,
        @"affectedSymbols": @[],
        @"requiresConfirmation": @(requiresConfirmation),
        @"rejectedReason": @""
    } mutableCopy];

    if (!insideWorkspace) {
        result[@"rejectedReason"] = @"Target file is outside workspace.";
        return result;
    }
    if (!targetExists) {
        result[@"rejectedReason"] = @"Target file does not exist.";
        return result;
    }
    if (patch.length == 0) {
        result[@"rejectedReason"] = @"Patch is empty.";
        return result;
    }

    NSString* currentText = currentTextOverride ?: [_windowBridge textForFileAtPath:targetPath];
    if (!currentText) {
        result[@"rejectedReason"] = @"Target file is not readable.";
        return result;
    }

    NSArray* symbols = [DietCodeSymbolIndexService symbolsForFileContent:currentText extension:[[targetPath pathExtension] lowercaseString]];
    NSDictionary* preview = [DietCodeDiffAnalysisService previewPatchAtPath:targetPath patch:patch currentText:currentText symbols:symbols];
    BOOL clean = [preview[@"ok"] boolValue];
    result[@"patchAppliesCleanly"] = @(clean);
    result[@"affectedSymbols"] = AffectedSymbolsForPatch(patch, symbols);
    result[@"preview"] = preview;

    if (!clean) {
        result[@"rejectedReason"] = preview[@"error"] ?: @"Patch does not apply cleanly.";
        return result;
    }

    BOOL ignoreSyntax = YES; // Default is YES (relaxed)
    if (options[@"ignoreSyntax"] != nil) {
        ignoreSyntax = [options[@"ignoreSyntax"] boolValue];
    } else if (options[@"force"] != nil) {
        ignoreSyntax = [options[@"force"] boolValue];
    }

    if ([preview[@"syntaxDanger"] boolValue]) {
        // Hoist syntaxDanger flag and a human-readable syntaxWarning to the root of
        // the validation dict so agents can check validation.syntaxDanger without
        // having to inspect the nested preview object.
        result[@"syntaxDanger"] = @YES;
        result[@"syntaxWarning"] = preview[@"syntaxErrors"] ?: @"Patch introduces syntax risk.";
        if (!ignoreSyntax) {
            result[@"rejectedReason"] = preview[@"syntaxErrors"] ?: @"Patch introduces syntax risk.";
            return result;
        }
    } else {
        result[@"syntaxDanger"] = @NO;
    }

    result[@"ok"] = @YES;
    result[@"rejectedReason"] = @"";
    return result;
}

- (NSDictionary*)applyPatch:(NSDictionary*)params 
                      error:(NSString**)errorOut 
                  errorCode:(NSString**)errorCodeOut {
    NSString* targetPath = params[@"path"];
    NSString* patchStr = params[@"patch"];
    if (!targetPath || patchStr.length == 0) {
        if (errorCodeOut) *errorCodeOut = @"invalid_params";
        if (errorOut) *errorOut = @"path and patch parameters required.";
        return nil;
    }
    
    NSDictionary* validation = [self validatePatchAtPath:targetPath patch:patchStr currentText:nil options:params];
    if (![validation[@"ok"] boolValue]) {
        if (errorCodeOut) *errorCodeOut = @"patch_failed";
        if (errorOut) *errorOut = validation[@"rejectedReason"] ?: @"Patch validation failed.";
        return nil;
    }
    
    if ([validation[@"requiresConfirmation"] boolValue] && ![params[@"confirm"] boolValue]) {
        if (errorCodeOut) *errorCodeOut = @"confirmation_required";
        if (errorOut) *errorOut = @"Patch requires confirmation.";
        return nil;
    }
    
    NSString* ws = [_windowBridge workspacePath];
    NSString* absPath = AbsolutePathForRPCPath(targetPath, ws);
    NSString* beforeText = [_windowBridge textForFileAtPath:absPath];
    
    NSString* errStr = nil;
    BOOL ok = [_windowBridge applyPatchAtPath:absPath patchString:patchStr errorOut:&errStr];
    if (!ok) {
        if (errorCodeOut) *errorCodeOut = @"patch_failed";
        if (errorOut) *errorOut = errStr ?: @"Unknown patch application error.";
        return nil;
    }
    
    NSString* afterText = [_windowBridge textForFileAtPath:absPath] ?: @"";
    [_lastPatchRecords removeAllObjects];
    [_lastPatchRecords addObject:@{
        @"path": absPath,
        @"beforeText": beforeText ?: @"",
        @"beforeHash": StableHashForString(beforeText ?: @""),
        @"postHash": StableHashForString(afterText)
    }];
    
    return @{ @"patched": @YES, @"path": absPath, @"validation": validation };
}

- (NSDictionary*)applyPatchBatch:(NSDictionary*)params 
                           error:(NSString**)errorOut 
                       errorCode:(NSString**)errorCodeOut {
    NSArray* patches = params[@"patches"];
    BOOL dryRun = params[@"dryRun"] ? [params[@"dryRun"] boolValue] : YES;
    if (![patches isKindOfClass:[NSArray class]] || patches.count == 0) {
        if (errorCodeOut) *errorCodeOut = @"invalid_params";
        if (errorOut) *errorOut = @"patches array required.";
        return nil;
    }
    
    if (patches.count > (NSUInteger)kMaxBatchPatchCount) {
        if (errorCodeOut) *errorCodeOut = @"too_many_results";
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Batch patch count exceeds limit of %ld.", (long)kMaxBatchPatchCount];
        return nil;
    }
    
    NSString* ws = [_windowBridge workspacePath];
    NSUInteger combinedBytes = 0;
    NSMutableArray* results = [NSMutableArray array];
    NSMutableArray* records = [NSMutableArray array];
    BOOL needsConfirm = NO;
    
    for (NSDictionary* item in patches) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            if (errorCodeOut) *errorCodeOut = @"invalid_params";
            if (errorOut) *errorOut = @"Each batch patch must be an object.";
            return nil;
        }
        NSString* relPath = item[@"path"];
        NSString* patchStr = item[@"patch"];
        if (relPath.length == 0 || patchStr.length == 0) {
            if (errorCodeOut) *errorCodeOut = @"invalid_params";
            if (errorOut) *errorOut = @"Each batch patch requires path and patch.";
            return nil;
        }
        NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
        combinedBytes += [patchStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        NSDictionary* validation = [self validatePatchAtPath:absPath patch:patchStr currentText:nil options:params];
        if ([validation[@"requiresConfirmation"] boolValue]) needsConfirm = YES;
        [results addObject:@{ @"path": absPath ?: @"", @"validation": validation }];
        if (![validation[@"ok"] boolValue]) {
            return @{ @"dryRun": @(dryRun), @"applied": @NO, @"results": results };
        }
        NSString* beforeText = [_windowBridge textForFileAtPath:absPath];
        [records addObject:@{ @"path": absPath ?: @"", @"beforeText": beforeText ?: @"", @"beforeHash": StableHashForString(beforeText ?: @""), @"patch": patchStr ?: @"" }];
    }
    
    if ((combinedBytes > kMaxPatchBytesBeforeConfirmation || needsConfirm) && ![params[@"confirm"] boolValue]) {
        if (errorCodeOut) *errorCodeOut = @"confirmation_required";
        if (errorOut) *errorOut = @"Batch patch requires confirmation.";
        return nil;
    }
    
    if (dryRun) {
        return @{ @"dryRun": @YES, @"applied": @NO, @"results": results };
    }
    
    NSMutableArray* applied = [NSMutableArray array];
    for (NSDictionary* record in records) {
        NSString* errStr = nil;
        BOOL ok = [_windowBridge applyPatchAtPath:record[@"path"] patchString:record[@"patch"] errorOut:&errStr];
        if (!ok) {
            NSString* restoreErr = nil;
            [self restorePatchRecords:applied error:&restoreErr];
            if (errorCodeOut) *errorCodeOut = @"patch_failed";
            if (errorOut) *errorOut = errStr ?: restoreErr ?: @"Batch patch failed.";
            return nil;
        }
        NSMutableDictionary* appliedRecord = [record mutableCopy];
        NSString* afterText = [_windowBridge textForFileAtPath:record[@"path"]] ?: @"";
        appliedRecord[@"postHash"] = StableHashForString(afterText);
        [applied addObject:appliedRecord];
    }
    
    [_lastPatchRecords removeAllObjects];
    [_lastPatchRecords addObjectsFromArray:applied];
    
    return @{ @"dryRun": @NO, @"applied": @YES, @"results": results };
}

- (NSDictionary*)revertLastPatchWithError:(NSString**)errorOut 
                                errorCode:(NSString**)errorCodeOut {
    if (_lastPatchRecords.count == 0) {
        if (errorCodeOut) *errorCodeOut = @"invalid_request";
        if (errorOut) *errorOut = @"No RPC patch available to revert.";
        return nil;
    }
    
    NSString* errStr = nil;
    BOOL ok = [self restorePatchRecords:_lastPatchRecords error:&errStr];
    if (!ok) {
        if (errorCodeOut) *errorCodeOut = [errStr hasPrefix:@"Rollback conflict"] ? @"rollback_conflict" : @"rollback_failed";
        if (errorOut) *errorOut = errStr ?: @"Failed to revert last RPC patch.";
        return nil;
    }
    
    NSMutableArray* paths = [NSMutableArray array];
    for (NSDictionary* record in _lastPatchRecords) {
        [paths addObject:record[@"path"] ?: @""];
    }
    [_lastPatchRecords removeAllObjects];
    
    return @{ @"reverted": @YES, @"files": paths };
}

- (void)recordMutationRecords:(NSArray<NSDictionary*>*)records {
    [_lastPatchRecords removeAllObjects];
    [_lastPatchRecords addObjectsFromArray:records ?: @[]];
}

- (BOOL)restorePatchRecords:(NSArray<NSDictionary*>*)records error:(NSString**)errorOut {
    NSString* ws = [_windowBridge workspacePath];
    if (ws.length == 0) {
        if (errorOut) *errorOut = @"No active workspace.";
        return NO;
    }
    
    // First pass: validation
    for (NSDictionary* record in records.reverseObjectEnumerator) {
        NSString* path = record[@"path"];
        NSString* beforeText = record[@"beforeText"];
        NSString* expectedPostHash = record[@"postHash"];
        NSString* beforeHash = record[@"beforeHash"];
        BOOL existedBefore = record[@"existed"] ? [record[@"existed"] boolValue] : YES;
        
        if (!path || beforeText == nil) {
            if (errorOut) *errorOut = @"Cannot restore patch because a target buffer record is invalid.";
            return NO;
        }
        
        NSString* absPath = AbsolutePathForRPCPath(path, ws);
        if (!PathIsInsideWorkspace(absPath, ws)) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Target path escapes workspace: %@", path];
            return NO;
        }
        
        NSString* currentText = [_windowBridge textForFileAtPath:absPath];
        if (currentText == nil && existedBefore) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Cannot restore patch because target buffer is unavailable: %@", path];
            return NO;
        }
        
        if (currentText != nil && IsTextBinary(currentText)) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"File is binary: %@", path];
            return NO;
        }
        
        if (currentText != nil && expectedPostHash.length > 0 && ![StableHashForString(currentText) isEqualToString:expectedPostHash]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Rollback conflict for %@: current buffer no longer matches the expected postimage.", path];
            return NO;
        }
        
        if (beforeHash.length > 0 && ![StableHashForString(beforeText) isEqualToString:beforeHash]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Preimage hash mismatch for %@", path];
            return NO;
        }
    }
    
    // Second pass: apply
    for (NSDictionary* record in records.reverseObjectEnumerator) {
        NSString* path = record[@"path"];
        NSString* beforeText = record[@"beforeText"];
        NSString* absPath = AbsolutePathForRPCPath(path, ws);
        BOOL existedBefore = record[@"existed"] ? [record[@"existed"] boolValue] : YES;
        if (!existedBefore) {
            NSError* deleteErr = nil;
            if ([[NSFileManager defaultManager] fileExistsAtPath:absPath] &&
                ![[NSFileManager defaultManager] removeItemAtPath:absPath error:&deleteErr]) {
                if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to remove created file %@: %@", path, deleteErr.localizedDescription];
                return NO;
            }
            continue;
        }
        NSString* currentText = [_windowBridge textForFileAtPath:absPath];
        BOOL ok = currentText != nil && [_windowBridge replaceTextInRange:NSMakeRange(0, currentText.length) withText:beforeText forFileAtPath:absPath];
        NSError* writeErr = nil;
        BOOL writeOk = [beforeText writeToFile:absPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
        if (!ok && !writeOk) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to restore %@", path];
            return NO;
        }
    }
    return YES;
}

@end
