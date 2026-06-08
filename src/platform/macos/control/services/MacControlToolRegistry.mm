#import "MacControlToolRegistry.hpp"

static NSDictionary* ToolEntry(
    NSString* method,
    NSString* stability,
    BOOL deterministic,
    BOOL agentSafe,
    BOOL mutates,
    BOOL idempotency,
    NSString* replacement,
    BOOL deprecated) {
    NSMutableDictionary* entry = [@{
        @"method": method,
        @"stability": stability,
        @"deterministic": @(deterministic),
        @"agentSafe": @(agentSafe),
        @"mutatesWorkspace": @(mutates),
        @"supportsIdempotencyKey": @(idempotency),
        @"supportsDryRun": @(NO),
        @"requiresConfirmation": @(mutates),
        @"deprecated": @(deprecated),
        @"contractVersion": @"1.0.0",
    } mutableCopy];
    if (replacement.length > 0) entry[@"replacementMethod"] = replacement;
    return entry;
}

static NSArray<NSDictionary*>* AgentToolEntries(void) {
    static NSArray<NSDictionary*>* entries = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        entries = @[
            ToolEntry(@"workspace.grep", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.literal", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.text", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.tokens", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.files", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.paths", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.todo", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.references", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"search.semantic", @"deprecated", NO, NO, NO, NO, @"search.literal", YES),
            ToolEntry(@"analysis.searchRanked", @"deprecated", NO, NO, NO, NO, @"search.literal", YES),
            ToolEntry(@"symbols.references", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"patch.validate", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"patch.apply", @"stable", YES, YES, YES, YES, nil, NO),
            ToolEntry(@"patch.applyBatch", @"stable", YES, YES, YES, YES, nil, NO),
            ToolEntry(@"file.stat", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"workspace.revision", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"workspace.snapshot", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"operation.status", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"tool.registry", @"stable", YES, YES, NO, NO, nil, NO),
            ToolEntry(@"tool.capabilities", @"stable", YES, YES, NO, NO, nil, NO),
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
    for (NSDictionary* entry in AgentToolEntries()) {
        NSString* method = entry[@"method"];
        if ([entry[@"agentSafe"] boolValue]) [agentSafe addObject:method];
        if ([entry[@"deprecated"] boolValue]) [deprecated addObject:method];
        if ([entry[@"deterministic"] boolValue] && [method hasPrefix:@"search."]) {
            [deterministicSearch addObject:method];
        }
    }
    [agentSafe sortUsingSelector:@selector(compare:)];
    [deprecated sortUsingSelector:@selector(compare:)];
    [deterministicSearch sortUsingSelector:@selector(compare:)];
    return @{
        @"mode": @"tool_capabilities",
        @"contractVersion": @"1.0.0",
        @"agentSafeMethods": agentSafe,
        @"deprecatedMethods": deprecated,
        @"deterministicSearchMethods": deterministicSearch,
        @"semanticSearchDisabled": @YES,
        @"rankingPolicy": @"none",
        @"scoringDisabled": @YES,
    };
}
