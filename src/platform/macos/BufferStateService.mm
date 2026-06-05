#import "BufferStateService.hpp"

@implementation DietCodeBufferStateService

+ (NSString*)unsavedDiffForTab:(id)tab {
    NSString* path = [tab valueForKey:@"path"];
    BOOL dirty = [[tab valueForKey:@"dirty"] boolValue];
    if (!dirty || path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return @"";
    }

    NSTextView* tv = [tab valueForKey:@"textView"];
    NSString* currentText = tv.string ?: @"";

    NSString* tempDir = NSTemporaryDirectory() ?: @"/tmp";
    NSString* tempPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"dietcode_buffer_diff_%u.txt", arc4random()]];

    @try {
    NSError* err = nil;
    unlink([tempPath UTF8String]);
    [currentText writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) return @"";

    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/diff"];
    [task setArguments:@[@"-u", path, tempPath]];

    NSPipe* outPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:outPipe];

    @try {
        [task launch];
        NSData* data = [[outPipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString* diff = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return diff ?: @"";
    } @catch (NSException* e) {
        return @"";
    }

    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    }
}

+ (NSArray<NSDictionary*>*)snapshotForTabs:(NSArray*)tabs {
    NSMutableArray* result = [NSMutableArray array];
    for (id tab in tabs) {
        NSString* path = [tab valueForKey:@"path"] ?: @"";
        BOOL dirty = [[tab valueForKey:@"dirty"] boolValue];
        BOOL isReadOnly = [[tab valueForKey:@"isReadOnly"] boolValue];
        BOOL isDiff = [[tab valueForKey:@"isDiff"] boolValue];
        BOOL isLargeFile = [[tab valueForKey:@"isLargeFile"] boolValue];

        NSTextView* tv = [tab valueForKey:@"textView"];
        NSString* text = tv.string ?: @"";
        NSRange sel = tv ? tv.selectedRange : NSMakeRange(0, 0);

        NSInteger lineCount = 0;
        if (text.length > 0) {
            lineCount = [[text componentsSeparatedByString:@"\n"] count];
        }

        NSString* unsavedDiff = @"";
        if (dirty) {
            unsavedDiff = [self unsavedDiffForTab:tab];
        }

        [result addObject:@{
            @"path": path,
            @"dirty": @(dirty),
            @"isReadOnly": @(isReadOnly),
            @"isDiff": @(isDiff),
            @"isLargeFile": @(isLargeFile),
            @"selectionStart": @(sel.location),
            @"selectionEnd": @(sel.location + sel.length),
            @"lines": @(lineCount),
            @"text": text,
            @"unsavedDiff": unsavedDiff
        }];
    }
    return result;
}

@end
