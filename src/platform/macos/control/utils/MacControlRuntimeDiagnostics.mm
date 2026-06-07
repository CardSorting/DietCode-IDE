#import "MacControlRuntimeDiagnostics.hpp"
#import "MacControlSerialization.hpp"

#include <fstream>
#include <sys/stat.h>
#include <unistd.h>

namespace dietcode::platform::macos {

NSString* MacControlRuntimeDiagnosticLogPath(void) {
    NSString* home = NSHomeDirectory();
    NSString* dietcodeDir = [home stringByAppendingPathComponent:@".dietcode"];
    return [dietcodeDir stringByAppendingPathComponent:@"agent-runtime.ndjson"];
}

static BOOL RuntimeDiagnosticLogIsSafe(NSString* logPath) {
    struct stat st;
    if (lstat([logPath UTF8String], &st) == 0) {
        if (S_ISLNK(st.st_mode) || st.st_uid != getuid()) {
            unlink([logPath UTF8String]);
        }
    }
    NSString* parent = [logPath stringByDeletingLastPathComponent];
    if (lstat([parent UTF8String], &st) == 0) {
        if (S_ISLNK(st.st_mode) || st.st_uid != getuid()) {
            return NO;
        }
    }
    return YES;
}

static void RotateRuntimeDiagnosticLogIfNeeded(NSString* logPath) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSDictionary* attrs = [fm attributesOfItemAtPath:logPath error:nil];
    if (!attrs) return;
    unsigned long long size = [attrs fileSize];
    if (size < 5 * 1024 * 1024) return;

    NSString* path3 = [logPath stringByAppendingString:@".3"];
    NSString* path2 = [logPath stringByAppendingString:@".2"];
    NSString* path1 = [logPath stringByAppendingString:@".1"];
    if ([fm fileExistsAtPath:path3]) [fm removeItemAtPath:path3 error:nil];
    if ([fm fileExistsAtPath:path2]) [fm moveItemAtPath:path2 toPath:path3 error:nil];
    if ([fm fileExistsAtPath:path1]) [fm moveItemAtPath:path1 toPath:path2 error:nil];
    if ([fm fileExistsAtPath:logPath]) [fm moveItemAtPath:logPath toPath:path1 error:nil];
}

NSDictionary* MacControlRpcErrorDiagnosticMetadata(NSString* stringCode) {
    NSString* code = stringCode.length > 0 ? stringCode : @"internal_error";
    NSString* category = @"domain";
    BOOL retryable = NO;
    NSString* recoveryHint = @"rg string_code docs/error-codes.md";

    if ([code isEqualToString:@"invalid_request"] || [code isEqualToString:@"invalid_params"] ||
        [code isEqualToString:@"request_too_large"] || [code isEqualToString:@"too_many_results"]) {
        category = @"validation";
        recoveryHint = @"fix_request_params";
    } else if ([code isEqualToString:@"method_not_found"]) {
        category = @"resource";
        recoveryHint = @"rpc.describe_or_rpc.methods";
    } else if ([code isEqualToString:@"permission_denied"]) {
        category = @"auth";
        recoveryHint = @"check_session_token";
    } else if ([code isEqualToString:@"response_serialization_failed"] || [code isEqualToString:@"response_too_large"]) {
        category = @"serialization";
        recoveryHint = @"reduce_response_payload";
    } else if ([code isEqualToString:@"internal_error"]) {
        category = @"transport";
        retryable = YES;
        recoveryHint = @"make verify-agent-runtime";
    } else if ([code isEqualToString:@"transport_error"]) {
        category = @"transport";
        retryable = YES;
        recoveryHint = @"dietcode_agent_client.py --diagnose";
    } else if ([code isEqualToString:@"not_found"] || [code isEqualToString:@"task_not_active"]) {
        category = @"resource";
        recoveryHint = @"verify_task_or_resource_id";
    } else if ([code isEqualToString:@"outside_workspace"] || [code isEqualToString:@"outside_scope"]) {
        category = @"validation";
        recoveryHint = @"use_workspace_relative_path";
    } else if ([code isEqualToString:@"verification_failed"] || [code isEqualToString:@"verify_failed"] ||
               [code isEqualToString:@"patch_failed"]) {
        category = @"domain";
        recoveryHint = @"inspect_verify_or_patch_output";
    } else if ([code isEqualToString:@"rollback_failed"] || [code isEqualToString:@"backup_corrupt"]) {
        category = @"recovery";
        recoveryHint = @"recovery.list_or_recovery.scan";
    }

    return @{
        @"category": category,
        @"retryable": @(retryable),
        @"recovery_hint": recoveryHint,
    };
}

void MacControlAppendRuntimeDiagnosticLine(NSDictionary* fields) {
    if (![fields isKindOfClass:[NSDictionary class]]) return;
    NSString* logPath = MacControlRuntimeDiagnosticLogPath();
    if (!RuntimeDiagnosticLogIsSafe(logPath)) return;

    NSMutableDictionary* line = [NSMutableDictionary dictionaryWithDictionary:fields];
    if (!line[@"type"]) line[@"type"] = @"runtime_diagnostic";
    if (!line[@"timestamp"]) line[@"timestamp"] = ISODateString([NSDate date]);

    NSError* err = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:line options:0 error:&err];
    if (err || !data || data.length > 8192) return;

    static NSString* syncToken = @"com.dietcode.runtime.diagnostic.log";
    @synchronized(syncToken) {
        RotateRuntimeDiagnosticLogIfNeeded(logPath);
        std::ofstream out([logPath UTF8String], std::ios::app);
        if (out.is_open()) {
            out.write(reinterpret_cast<const char*>(data.bytes), data.length);
            out.put('\n');
            out.close();
        }
    }
}

} // namespace dietcode::platform::macos
