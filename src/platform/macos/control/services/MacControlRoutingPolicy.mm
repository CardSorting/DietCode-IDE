#import "MacControlRoutingPolicy.hpp"

// Queue contract (grep: rg 'MacControlIsReadQueueMethod|executeNestedMethod' src/platform/macos/control):
// - Methods listed here are read-affine and MUST run on com.dietcode.runtime.read.
// - All other RPC methods default to com.dietcode.runtime.execution unless UI-bound.
// - Nested runtime calls (task/combo executors) must use executeNestedMethod, not executeMethod.
// - UI mutations inside workbench steps dispatch to the main queue via MacControlWindowBridge.

BOOL MacControlIsReadQueueMethod(NSString* method) {
    static NSSet<NSString*>* readMethods = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        readMethods = [NSSet setWithArray:@[
            @"workspace.grep",
            @"workspace.getRoot",
            @"workspace.findFiles",
            @"workspace.getRecentFiles",
            @"search.text",
            @"search.files",
            @"search.todo",
            @"search.semantic",
            @"search.diagnostics",
            @"diagnostics.list",
            @"diagnostics.summary",
            @"diagnostics.cluster",
            @"diagnostics.forFile",
            @"workspace.listFiles",
            @"recovery.scan",
            @"recovery.schemaInfo",
            @"recovery.list",
            @"combo.list",
            @"file.read",
            @"file.readBatch",
            @"file.readRange",
            @"file.readAround",
            @"file.getChunks",
            @"file.stat",
            @"file.statBatch",
            @"git.status",
            @"git.diff",
            @"analysis.workspaceSummary",
            @"analysis.searchRanked",
            @"analysis.fileSummary",
            @"analysis.relatedFiles",
            @"symbols.document",
            @"symbols.outline",
            @"symbols.hierarchy",
            @"symbols.activeDocument",
            @"symbols.references",
            @"editor.getActiveFile",
            @"editor.getOpenFiles",
            @"editor.getText",
            @"editor.getSelection",
            @"diff.workspaceInfo",
            @"diff.stats",
            @"diff.file",
            @"diff.chunk",
            @"diff.hunks",
            @"diff.current",
            @"diff.staged",
            @"diff.unstaged",
            @"diff.summary",
            @"buffers.snapshot",
            @"buffers.dirty",
            @"buffers.active",
            @"buffers.unsavedDiff",
            @"changes.current",
            @"changes.summary",
            @"patch.chunk",
            @"patch.hunks",
            @"problems.list",
            @"language.diagnostics",
            @"verify.last",
            @"verify.status",
            @"verify.failures",
            @"terminal.status",
            @"terminal.jobs",
            @"terminal.history",
            @"terminal.getOutput",
            @"session.info",
            @"session.workflowState",
            @"session.recentCommands",
            @"session.lastSearches",
            @"system.info"
        ]];
    });
    return [readMethods containsObject:method];
}
