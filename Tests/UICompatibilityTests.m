// Copyright 2026 The DirStat Authors.

#import "OmniCompatibility.h"
#import "DIXTableView.h"
#import "DIXOutlineView.h"
#import "OAToolbarWindowControllerEx.h"
#import <objc/runtime.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL %s line %d: %s\n", __FILE__, __LINE__, #condition); \
        @throw [NSException exceptionWithName:@"TestFailure" \
            reason:[NSString stringWithUTF8String:#condition] userInfo:nil]; \
    } \
} while (0)

static NSPasteboard *copyTestPasteboard;

static NSPasteboard *PrivateGeneralPasteboard(id receiver, SEL selector)
{
    return copyTestPasteboard;
}

@interface UnsupportedCopyDataSource : NSObject <NSTableViewDataSource, NSOutlineViewDataSource>
@end
@implementation UnsupportedCopyDataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return 1; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return @"selected file";
}
- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item { return item ? 0 : 1; }
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item { return @"selected file"; }
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item { return NO; }
- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    return item;
}
@end

@interface CopyDataSource : UnsupportedCopyDataSource
@property(nonatomic) NSUInteger tableWrites;
@property(nonatomic) NSUInteger outlineWrites;
@end
@implementation CopyDataSource
- (BOOL)tableView:(NSTableView *)table writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard
{
    CHECK(pasteboard == copyTestPasteboard);
    CHECK([rows isEqualToIndexSet:[NSIndexSet indexSetWithIndex:0]]);
    self.tableWrites++;
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    return [pasteboard setString:@"table file" forType:NSPasteboardTypeString];
}
- (BOOL)outlineView:(NSOutlineView *)outline writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard
{
    CHECK(pasteboard == copyTestPasteboard);
    CHECK([items isEqualToArray:@[@"selected file"]]);
    self.outlineWrites++;
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    return [pasteboard setString:@"outline file" forType:NSPasteboardTypeString];
}
@end

static void TestFileCopy(void)
{
    copyTestPasteboard = [NSPasteboard pasteboardWithUniqueName];
    CHECK(copyTestPasteboard != nil);
    Method generalPasteboard = class_getClassMethod([NSPasteboard class], @selector(generalPasteboard));
    IMP originalGeneralPasteboard = method_setImplementation(generalPasteboard, (IMP)PrivateGeneralPasteboard);
    @try {
        for (Class tableClass in @[[DIXTableView class], [DIXOutlineView class]]) {
            CopyDataSource *source = [[[CopyDataSource alloc] init] autorelease];
            NSTableView *table = [[[tableClass alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)] autorelease];
            [table addTableColumn:[[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease]];
            [table setDataSource:source];
            [table reloadData];
            NSMenuItem *copyItem = [[[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"] autorelease];

            CHECK([table respondsToSelector:@selector(copy:)]);
            CHECK(![(id)table validateMenuItem:copyItem]);
            [copyTestPasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
            CHECK([copyTestPasteboard setString:@"keep when nothing is selected" forType:NSPasteboardTypeString]);
            [table performSelector:@selector(copy:) withObject:copyItem];
            CHECK(source.tableWrites == 0 && source.outlineWrites == 0);
            CHECK([[copyTestPasteboard stringForType:NSPasteboardTypeString]
                isEqualToString:@"keep when nothing is selected"]);

            [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            CHECK([(id)table validateMenuItem:copyItem]);
            NSMenuItem *selectAllItem = [[[NSMenuItem alloc] initWithTitle:@"Select All"
                action:@selector(selectAll:) keyEquivalent:@"a"] autorelease];
            CHECK([(id)table validateMenuItem:selectAllItem] == [table validateUserInterfaceItem:selectAllItem]);
            [table performSelector:@selector(copy:) withObject:copyItem];
            BOOL isOutline = [table isKindOfClass:[NSOutlineView class]];
            CHECK(source.tableWrites == (isOutline ? 0 : 1));
            CHECK(source.outlineWrites == (isOutline ? 1 : 0));
            CHECK([[copyTestPasteboard stringForType:NSPasteboardTypeString]
                isEqualToString:isOutline ? @"outline file" : @"table file"]);

            // A selected row alone cannot enable Copy if the data source cannot write it.
            UnsupportedCopyDataSource *unsupported = [[[UnsupportedCopyDataSource alloc] init] autorelease];
            [table setDataSource:unsupported];
            [table reloadData];
            [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            CHECK(![(id)table validateMenuItem:copyItem]);
            [table setDataSource:nil];
        }
    } @finally {
        method_setImplementation(generalPasteboard, originalGeneralPasteboard);
        [copyTestPasteboard declareTypes:@[] owner:nil];
        [copyTestPasteboard releaseGlobally];
        copyTestPasteboard = nil;
    }
}

static void TestToolbarTitleForwarding(void)
{
    OAToolbarItem *item = [[[OAToolbarItem alloc] initWithItemIdentifier:@"ShowPackageContents"] autorelease];
    [item setLabel:@"Show Package Contents"];
    NSToolbarItemValidationAdapter *adapter = [[[NSToolbarItemValidationAdapter alloc] init] autorelease];
    [adapter setToolbarItem:item];

    // MainWindowController validates toolbar items through this real menu adapter.
    NSMenuItem *menuAdapter = (NSMenuItem *)adapter;
    CHECK([[menuAdapter title] isEqualToString:@"Show Package Contents"]);
    [menuAdapter setTitle:@"Hide Package Contents"];
    CHECK([[item label] isEqualToString:@"Hide Package Contents"]);
    CHECK([[menuAdapter title] isEqualToString:@"Hide Package Contents"]);
    [adapter setToolbarItem:nil];
}

void TestCopyAndToolbar(void)
{
    [NSApplication sharedApplication];
    TestFileCopy();
    TestToolbarTitleForwarding();
    puts("PASS: file and selection-list Copy, copy validation, toolbar title forwarding");
}
