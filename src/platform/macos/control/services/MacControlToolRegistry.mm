#import "MacControlToolRegistry.hpp"

static NSDictionary* ToolEntry(
    NSString* method,
    NSString* stability,
    BOOL deterministic,
    BOOL agentSafe,
    BOOL mutates,
    BOOL idempotency,
    BOOL dryRun,
    NSString* replacement,
    BOOL deprecated,
    NSString* failureRecoveryHint,
    NSString* successNextCommand) {
    NSMutableDictionary* entry = [@{
        @"method": method,
        @"stability": stability,
        @"deterministic": @(deterministic),
        @"agentSafe": @(agentSafe),
        @"mutatesWorkspace": @(mutates),
        @"supportsIdempotencyKey": @(idempotency),
        @"supportsDryRun": @(dryRun),
        @"requiresConfirmation": @(mutates),
        @"deprecated": @(deprecated),
        @"contractVersion": @"1.0.0",
        @"failureRecoveryHint": failureRecoveryHint ?: @"rg string_code docs/error-codes.md",
        @"nextRecommendedCommand": successNextCommand ?: @"",
    } mutableCopy];
    if (replacement.length > 0) entry[@"replacementMethod"] = replacement;
    return entry;
}

static NSArray<NSDictionary*>* AgentToolEntries(void) {
    static NSArray<NSDictionary*>* entries = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        entries = @[
            ToolEntry(@"workspace.grep", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_include_globs_or_paginate", @"workspace.grep"),
            ToolEntry(@"search.literal", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_include_globs_or_paginate", @"search.literal"),
            ToolEntry(@"search.text", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_include_globs_or_paginate", @"search.text"),
            ToolEntry(@"search.tokens", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_include_globs_or_paginate", @"search.tokens"),
            ToolEntry(@"search.files", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_path_query", @"search.files"),
            ToolEntry(@"search.paths", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_path_query", @"search.paths"),
            ToolEntry(@"search.todo", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_include_globs", @"search.todo"),
            ToolEntry(@"search.references", @"stable", YES, YES, NO, NO, NO, nil, NO, @"verify_symbol_name", @"search.references"),
            ToolEntry(@"search.semantic", @"deprecated", NO, NO, NO, NO, NO, @"search.literal", YES, @"use_search_literal_or_search_tokens", @"search.literal"),
            ToolEntry(@"symbols.references", @"stable", YES, YES, NO, NO, NO, nil, NO, @"verify_symbol_name", @"symbols.references"),
            ToolEntry(@"patch.validate", @"stable", YES, YES, NO, NO, NO, nil, NO, @"fix_patch_or_target_path", @"patch.apply"),
            ToolEntry(@"patch.apply", @"stable", YES, YES, YES, YES, YES, nil, NO, @"revalidate_patch_with_patch.validate", @"workspace.revision"),
            ToolEntry(@"patch.applyBatch", @"stable", YES, YES, YES, YES, YES, nil, NO, @"revalidate_batch_patches", @"workspace.revision"),
            ToolEntry(@"file.stat", @"stable", YES, YES, NO, NO, NO, nil, NO, @"verify_workspace_relative_path", @"file.read"),
            ToolEntry(@"workspace.revision", @"stable", YES, YES, NO, NO, NO, nil, NO, @"workspace.openFolder", @"workspace.snapshot"),
            ToolEntry(@"workspace.snapshot", @"stable", YES, YES, NO, NO, NO, nil, NO, @"narrow_snapshot_paths", @"workspace.revision"),
            ToolEntry(@"operation.status", @"stable", YES, YES, NO, NO, NO, nil, NO, @"retry_with_same_idempotencyKey", @"workspace.revision"),
            ToolEntry(@"memory.status", @"stable", YES, YES, NO, NO, NO, nil, NO, @"retry_memory_status", @"memory.operation.recent"),
            ToolEntry(@"memory.operation.findByIdempotencyKey", @"stable", YES, YES, NO, NO, NO, nil, NO, @"retry_with_same_idempotencyKey", @"operation.status"),
            ToolEntry(@"memory.operation.recent", @"stable", YES, YES, NO, NO, NO, nil, NO, @"memory.status", @"memory.revision.lastMutation"),
            ToolEntry(@"memory.replay.get", @"stable", YES, YES, NO, NO, NO, nil, NO, @"retry_with_same_idempotencyKey", @"operation.status"),
            ToolEntry(@"memory.revision.lastMutation", @"stable", YES, YES, NO, NO, NO, nil, NO, @"workspace.revision", @"workspace.snapshot"),
            ToolEntry(@"memory.workflow.start", @"stable", YES, YES, NO, NO, NO, nil, NO, @"memory.workflow.get", @"memory.workflow.step"),
            ToolEntry(@"memory.workflow.get", @"stable", YES, YES, NO, NO, NO, nil, NO, @"memory.workflow.recent", @"memory.workflow.step"),
            ToolEntry(@"memory.verify.latest", @"stable", YES, YES, NO, NO, NO, nil, NO, @"memory.verify.history", @"memory.verify.record"),
            ToolEntry(@"tool.registry", @"stable", YES, YES, NO, NO, NO, nil, NO, @"rpc.describe_or_rpc.methods", @"tool.capabilities"),
            ToolEntry(@"tool.capabilities", @"stable", YES, YES, NO, NO, NO, nil, NO, @"rpc.describe_or_rpc.methods", @"tool.registry"),
        ];
    });
    return entries;
}

NSDictionary* MacControlToolEntryForMethod(NSString* method) {
    for (NSDictionary* entry in AgentToolEntries()) {
        if ([entry[@"method"] isEqualToString:method]) return entry;
    }
    return @{
        @"method": method ?: @"",
        @"stability": @"unknown",
        @"deterministic": @NO,
        @"agentSafe": @NO,
        @"mutatesWorkspace": @NO,
        @"supportsIdempotencyKey": @NO,
        @"supportsDryRun": @NO,
        @"requiresConfirmation": @NO,
        @"deprecated": @NO,
        @"contractVersion": @"1.0.0",
        @"failureRecoveryHint": @"rpc.describe_or_rpc.methods",
        @"nextRecommendedCommand": @"tool.registry",
    };
}

NSDictionary* MacControlToolRegistryPayload(void) {
    return @{
        @"mode": @"tool_registry",
        @"contractVersion": @"1.0.0",
        @"rankingPolicy": @"none",
        @"scoringDisabled": @YES,
        @"tools": AgentToolEntries(),
    };
}

NSDictionary* MacControlToolCapabilitiesSummary(void) {
    NSMutableArray* agentSafe = [NSMutableArray array];
    NSMutableArray* deprecated = [NSMutableArray array];
    NSMutableArray* deterministicSearch = [NSMutableArray array];
    NSMutableArray* mutating = [NSMutableArray array];
    for (NSDictionary* entry in AgentToolEntries()) {
        NSString* method = entry[@"method"];
        if ([entry[@"agentSafe"] boolValue]) [agentSafe addObject:method];
        if ([entry[@"deprecated"] boolValue]) [deprecated addObject:method];
        if ([entry[@"deterministic"] boolValue] && [method hasPrefix:@"search."]) {
            [deterministicSearch addObject:method];
        }
        if ([entry[@"mutatesWorkspace"] boolValue]) [mutating addObject:method];
    }
    NSMutableArray* internalNamespaces = [NSMutableArray arrayWithArray:@[
        @"analysis.",
        @"language.",
        @"chip.",
        @"combo.",
        @"recovery.",
        @"terminal.run",
        @"verify.run",
    ]];
    [agentSafe sortUsingSelector:@selector(compare:)];
    [deprecated sortUsingSelector:@selector(compare:)];
    [deterministicSearch sortUsingSelector:@selector(compare:)];
    [mutating sortUsingSelector:@selector(compare:)];
    [internalNamespaces sortUsingSelector:@selector(compare:)];
    return @{
        @"mode": @"tool_capabilities",
        @"contractVersion": @"1.0.0",
        @"agentSafeMethods": agentSafe,
        @"deprecatedMethods": deprecated,
        @"deterministicSearchMethods": deterministicSearch,
        @"mutatingMethods": mutating,
        @"internalNamespaces": internalNamespaces,
        @"semanticSearchDisabled": @YES,
        @"rankingPolicy": @"none",
        @"scoringDisabled": @YES,
    };
}
