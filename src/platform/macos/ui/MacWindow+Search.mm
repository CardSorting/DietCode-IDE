#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"
#include "search/FindInFile.hpp"
#include "editor/TextBuffer.hpp"
#include "utils/PathExclusion.hpp"

using namespace dietcode::platform::macos;
using namespace dietcode::utils;

@implementation DietCodeWindowController (Search)

- (void)setupSearchUI {
    NSStackView* searchStack = [[NSStackView alloc] init];
    [searchStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [searchStack setSpacing:12];
    [searchStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [searchStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.searchSidebarView addSubview:searchStack];

    [searchStack addArrangedSubview:MakeLabel(@"SEARCH WORKSPACE", 13, NSFontWeightBold)];
    
    NSTextField* searchField = [[NSTextField alloc] init];
    [searchField setPlaceholderString:@"Search term..."];
    [searchField setIdentifier:@"SearchInput"];
    [searchField setAccessibilityLabel:@"Workspace search query input"];
    [searchStack addArrangedSubview:searchField];

    NSButton* caseCheck = [NSButton buttonWithTitle:@"Case Sensitive" target:nil action:nil];
    [caseCheck setButtonType:NSButtonTypeSwitch];
    [caseCheck setIdentifier:@"CaseSensitive"];
    [caseCheck setAccessibilityLabel:@"Search case sensitivity checkbox"];
    [searchStack addArrangedSubview:caseCheck];

    NSStackView* searchButtons = [[NSStackView alloc] init];
    [searchButtons setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [searchButtons setSpacing:8];
    
    NSButton* startSearchBtn = [NSButton buttonWithTitle:@"Search" target:self action:@selector(startWorkspaceSearch:)];
    [startSearchBtn setBezelStyle:NSBezelStyleRounded];
    [startSearchBtn setAccessibilityLabel:@"Start search button"];
    NSButton* cancelSearchBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelWorkspaceSearch:)];
    [cancelSearchBtn setBezelStyle:NSBezelStyleRounded];
    [cancelSearchBtn setAccessibilityLabel:@"Cancel search button"];
    [searchButtons addArrangedSubview:startSearchBtn];
    [searchButtons addArrangedSubview:cancelSearchBtn];
    [searchStack addArrangedSubview:searchButtons];

    // Search Results Scroll View directly in Search Sidebar
    NSScrollView* searchScroll = [[NSScrollView alloc] init];
    [searchScroll setHasVerticalScroller:YES];
    [searchScroll setHasHorizontalScroller:YES];
    [searchScroll setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    self.searchResultsTextView = [[DietCodeNavigationTextView alloc] initWithFrame:searchScroll.bounds];
    [(DietCodeNavigationTextView*)self.searchResultsTextView setNavigationTarget:self];
    [self.searchResultsTextView setEditable:NO];
    [self.searchResultsTextView setRichText:NO];
    [self.searchResultsTextView setFont:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]];
    [searchScroll setDocumentView:self.searchResultsTextView];
    [self addPlaceholder:@"No search results.\nEnter a term above and click Search." toTextView:self.searchResultsTextView];
    [self updatePlaceholderVisibility:self.searchResultsTextView];
    
    [searchStack addArrangedSubview:searchScroll];

    [NSLayoutConstraint activateConstraints:@[
        [searchStack.leadingAnchor constraintEqualToAnchor:self.searchSidebarView.leadingAnchor],
        [searchStack.trailingAnchor constraintEqualToAnchor:self.searchSidebarView.trailingAnchor],
        [searchStack.topAnchor constraintEqualToAnchor:self.searchSidebarView.topAnchor],
        [searchStack.bottomAnchor constraintEqualToAnchor:self.searchSidebarView.bottomAnchor],
        [searchScroll.widthAnchor constraintEqualToAnchor:searchStack.widthAnchor]
    ]];
}

- (void)startWorkspaceSearch:(id)sender {
    if (self.openedFolderPath == nil) {
        [self appendSearchResult:@"Please open a folder workspace first.\n"];
        [self selectActivity:@"search"];
        return;
    }
    
    NSView* searchPanel = self.searchSidebarView;
    NSTextField* searchInput = nil;
    NSButton* caseCheck = nil;
    
    // Find inputs in the subviews
    for (NSView* v in [searchPanel.subviews[0] arrangedSubviews]) {
        if ([v.identifier isEqualToString:@"SearchInput"]) {
            searchInput = (NSTextField*)v;
        } else if ([v.identifier isEqualToString:@"CaseSensitive"]) {
            caseCheck = (NSButton*)v;
        }
    }
    
    NSString* query = searchInput.stringValue;
    if (query.length == 0) return;
    
    if (![self.sessionLastSearches containsObject:query]) {
        [self.sessionLastSearches insertObject:query atIndex:0];
        if (self.sessionLastSearches.count > 50) {
            [self.sessionLastSearches removeLastObject];
        }
    }

    BOOL caseSensitive = (caseCheck.state == NSControlStateValueOn);
    
    [self.searchResultsTextView setString:@""];
    [self updatePlaceholderVisibility:self.searchResultsTextView];
    self.searchCancelled = NO;
    
    [self selectActivity:@"search"];
    [self appendSearchResult:[NSString stringWithFormat:@"Searching for '%@' in %@...\n\n", query, self.openedFolderPath]];

    std::string stdQuery = StdStringFromNSString(query);
    std::string folder = StdStringFromNSString(self.openedFolderPath);
    
    __weak DietCodeWindowController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DietCodeWindowController* strongSelf = weakSelf;
        if (!strongSelf) return;
        
        std::error_code ec;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(folder, ec)) {
            if (strongSelf.searchCancelled) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf appendSearchResult:@"\nSearch cancelled.\n"];
                });
                return;
            }
            
            if (entry.is_regular_file()) {
                std::filesystem::path p = entry.path();
                if (isPathExcluded(p)) {
                    continue;
                }
                
                auto readRes = strongSelf->fileService_.readTextFile(p);
                if (readRes.ok) {
                    dietcode::editor::TextBuffer tempBuf(readRes.contents);
                    auto matches = dietcode::search::findInFile(tempBuf, stdQuery, {.caseSensitive = (bool)caseSensitive});
                    if (!matches.empty()) {
                        NSString* filePath = NSStringFromStdString(p.string());
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [strongSelf appendSearchResult:[NSString stringWithFormat:@"File: %@\n", filePath]];
                            for (const auto& m : matches) {
                                [strongSelf appendSearchResult:[NSString stringWithFormat:@"  Line %zu, Col %zu: %s\n", m.line + 1, m.column + 1, m.lineText.c_str()]];
                            }
                            [strongSelf appendSearchResult:@"\n"];
                        });
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf appendSearchResult:@"Search finished.\n"];
        });
    });
}

- (void)cancelWorkspaceSearch:(id)sender {
    self.searchCancelled = YES;
}

- (void)appendSearchResult:(NSString*)text {
    NSTextStorage* storage = self.searchResultsTextView.textStorage;
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [self isDarkTheme] ? [NSColor whiteColor] : [NSColor blackColor]
    }]];
}

- (void)navigateFromProblemsOrSearchText:(NSString*)line sender:(id)sender {
    if (sender == self.searchResultsTextView) {
        NSRange range = [self.searchResultsTextView selectedRange];
        NSUInteger pos = range.location;
        NSString* text = self.searchResultsTextView.string;
        
        NSInteger lineNum = 1;
        NSInteger colNum = 1;
        
        NSScanner* scanner = [NSScanner scannerWithString:line];
        [scanner scanUpToString:@"Line " intoString:NULL];
        [scanner scanString:@"Line " intoString:NULL];
        NSInteger val = 0;
        if ([scanner scanInteger:&val]) {
            lineNum = val;
        }
        [scanner scanUpToString:@"Col " intoString:NULL];
        [scanner scanString:@"Col " intoString:NULL];
        if ([scanner scanInteger:&val]) {
            colNum = val;
        }
        
        NSString* filePath = nil;
        NSRange searchRange = NSMakeRange(0, pos);
        while (searchRange.length > 0) {
            NSRange lineRange = [text lineRangeForRange:NSMakeRange(searchRange.location + searchRange.length - 1, 0)];
            NSString* prevLine = [text substringWithRange:lineRange];
            prevLine = [prevLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([prevLine hasPrefix:@"File: "]) {
                filePath = [prevLine substringFromIndex:6];
                break;
            }
            if (lineRange.location == 0) {
                break;
            }
            searchRange.length = lineRange.location;
        }
        
        if (filePath) {
            NSString* absolutePath = filePath;
            if (![filePath isAbsolutePath] && self.openedFolderPath) {
                absolutePath = [self.openedFolderPath stringByAppendingPathComponent:filePath];
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:absolutePath]) {
                [self openFileAtPath:absolutePath line:lineNum column:colNum];
            }
        }
    }
    
    if (sender == self.errorsTextView) {
        NSArray* parts = [line componentsSeparatedByString:@":"];
        if (parts.count >= 3) {
            NSUInteger lineIndex = NSNotFound;
            for (NSUInteger idx = 0; idx < parts.count; idx++) {
                NSString* p = parts[idx];
                if (p.length > 0 && [p rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
                    lineIndex = idx;
                    break;
                }
            }
            
            if (lineIndex != NSNotFound && lineIndex > 0) {
                NSMutableArray* pathParts = [NSMutableArray array];
                for (NSUInteger idx = 0; idx < lineIndex; idx++) {
                    [pathParts addObject:parts[idx]];
                }
                NSString* filePath = [pathParts componentsJoinedByString:@":"];
                
                NSInteger lineNum = [parts[lineIndex] integerValue];
                NSInteger colNum = 1;
                if (lineIndex + 1 < parts.count) {
                    NSString* colPart = parts[lineIndex + 1];
                    if (colPart.length > 0 && [colPart rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
                        colNum = [colPart integerValue];
                    }
                }
                
                NSString* absolutePath = filePath;
                if (![filePath isAbsolutePath] && self.openedFolderPath) {
                    absolutePath = [self.openedFolderPath stringByAppendingPathComponent:filePath];
                }
                if ([[NSFileManager defaultManager] fileExistsAtPath:absolutePath]) {
                    [self openFileAtPath:absolutePath line:lineNum column:colNum];
                }
            }
        }
    }
}

@end
