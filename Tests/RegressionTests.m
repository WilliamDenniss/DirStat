// Copyright 2026 The DirStat Authors.

#import "OmniCompatibility.h"
#import "AppsForItem.h"
#import "FSItem.h"
#import "NSURL-Extensions.h"
#import "NTFilePasteboardSource.h"

void TestCopyAndToolbar(void);
void TestPreferenceReset(void);

BOOL g_EnableLogging = NO;

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); \
        @throw [NSException exceptionWithName:@"TestFailure" \
            reason:[NSString stringWithUTF8String:#condition] userInfo:nil]; \
    } \
} while (0)

static NSArray *applicationCandidates;
static NSURL *defaultApplication;

@interface FixtureAppsForItem : AppsForItem
@end
@implementation FixtureAppsForItem
+ (NSArray *)applicationURLsForItemURL:(NSURL *)url { return applicationCandidates; }
- (NSURL *)defaultAppURL { return defaultApplication; }
@end

@interface DeferredPasteboardOwner : NSObject
{
    BOOL *_destroyed;
}
- (instancetype)initWithDestructionFlag:(BOOL *)flag;
@end
@implementation DeferredPasteboardOwner
- (instancetype)initWithDestructionFlag:(BOOL *)flag
{
    self = [super init];
    if (self) _destroyed = flag;
    return self;
}
- (void)pasteboard:(NSPasteboard *)pasteboard provideDataForType:(NSPasteboardType)type
{
    [pasteboard setString:@"deferred content" forType:type];
}
- (void)dealloc
{
    *_destroyed = YES;
    [super dealloc];
}
@end

static NSURL *MakeDirectory(NSURL *parent, NSString *name)
{
    NSURL *url = [parent URLByAppendingPathComponent:name isDirectory:YES];
    CHECK([[NSFileManager defaultManager] createDirectoryAtURL:url
                                 withIntermediateDirectories:YES attributes:nil error:NULL]);
    return url;
}

static NSURL *MakeFile(NSURL *parent, NSString *name, NSUInteger bytes)
{
    NSURL *url = [parent URLByAppendingPathComponent:name];
    CHECK([[NSMutableData dataWithLength:bytes] writeToURL:url atomically:YES]);
    return url;
}

static FSItem *ChildNamed(FSItem *parent, NSString *name)
{
    for (FSItem *child in [parent childEnumerator])
        if ([[child name] isEqualToString:name]) return child;
    return nil;
}

static void TestModelAfterRemoval(NSURL *fixture)
{
    NSURL *scanURL = MakeDirectory(fixture, @"scan");
    NSURL *largeURL = MakeDirectory(scanURL, @"large");
    NSURL *smallURL = MakeDirectory(scanURL, @"small");
    NSURL *removedURL = MakeFile(largeURL, @"remove.bin", 1024);
    MakeFile(largeURL, @"keep.bin", 64);
    MakeFile(smallURL, @"middle.bin", 256);

    FSItem *root = [[FSItem alloc] initWithURL:scanURL];
    [root loadChildren];
    FSItem *large = ChildNamed(root, @"large");
    FSItem *small = ChildNamed(root, @"small");
    FSItem *removed = ChildNamed(large, @"remove.bin");
    CHECK(large && small && removed);
    CHECK([root childAtIndex:0] == large);
    unsigned long long expectedSize = [root sizeValue] - [removed sizeValue];

    // Exercise the model update used after a successful filesystem removal.
    CHECK([[NSFileManager defaultManager] removeItemAtURL:removedURL error:NULL]);
    [large removeChild:removed updateParent:YES];
    CHECK([large childCount] == 1);
    CHECK([root sizeValue] == expectedSize);
    CHECK([root childAtIndex:0] == small);
    CHECK([root childAtIndex:1] == large);
    CHECK([large parent] == root);

    // Also exercise insertion into an empty list and equal-size siblings.
    FSItem *empty = [[FSItem alloc] initWithURL:MakeDirectory(fixture, @"empty")];
    FSItem *first = [[FSItem alloc] initWithURL:MakeFile(fixture, @"first.bin", 64)];
    FSItem *second = [[FSItem alloc] initWithURL:MakeFile(fixture, @"second.bin", 64)];
    [first recalculateSize:NO updateParent:NO];
    [second recalculateSize:NO updateParent:NO];
    [empty insertChild:first updateParent:YES];
    [empty insertChild:second updateParent:YES];
    CHECK([empty childCount] == 2);
    CHECK([empty sizeValue] == [first sizeValue] + [second sizeValue]);
    [first release];
    [second release];
    [empty release];
    [root release];
    puts("PASS: scan, removal totals, parent ordering, empty/equal-size insertion");
}

static void TestApplicationSorting(NSURL *fixture)
{
    NSURL *zeta = MakeDirectory(fixture, @"zeta.app");
    NSURL *alpha = MakeDirectory(fixture, @"Alpha.app");
    defaultApplication = MakeDirectory(fixture, @"beta.app");
    NSURL *ownApp = MakeDirectory(fixture, @"Disk Inventory X.app");
    NSURL *missing = [fixture URLByAppendingPathComponent:@"Gone.app"];
    applicationCandidates = @[zeta, missing, defaultApplication, ownApp, alpha];
    FixtureAppsForItem *apps = [[FixtureAppsForItem alloc] initWithItemURL:fixture];
    NSArray *result = [apps additionalAppURLs];
    CHECK([result isEqualToArray:(@[alpha, zeta])]);
    CHECK([apps additionalAppURLs] == result);
    [apps release];
    applicationCandidates = nil;
    defaultApplication = nil;
    puts("PASS: Open With sorting and default/self/missing-name filtering");
}

static void TestPasteboardLifetime(NSURL *fixture)
{
    // A private pasteboard leaves the user's clipboard untouched.
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    CHECK(pasteboard != nil);
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    CHECK([pasteboard setString:@"service probe" forType:NSPasteboardTypeString]);
    CHECK([[pasteboard stringForType:NSPasteboardTypeString] isEqualToString:@"service probe"]);
    BOOL destroyed = NO;
    @autoreleasepool {
        DeferredPasteboardOwner *owner = [[[DeferredPasteboardOwner alloc]
            initWithDestructionFlag:&destroyed] autorelease];
        [[OAPasteboardHelper helperWithPasteboard:pasteboard]
            declareTypes:@[NSPasteboardTypeString] owner:owner];
    }
    CHECK(!destroyed);
    CHECK([[pasteboard stringForType:NSPasteboardTypeString] isEqualToString:@"deferred content"]);
    CHECK(destroyed);

    destroyed = NO;
    @autoreleasepool {
        DeferredPasteboardOwner *owner = [[[DeferredPasteboardOwner alloc]
            initWithDestructionFlag:&destroyed] autorelease];
        [[OAPasteboardHelper helperWithPasteboard:pasteboard]
            declareTypes:@[NSPasteboardTypeString] owner:owner];
    }
    CHECK(!destroyed);
    [pasteboard declareTypes:@[] owner:nil];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!destroyed && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
    CHECK(destroyed);

    // Reusing a helper must survive synchronous revocation during declaration.
    BOOL oldOwnerDestroyed = NO;
    BOOL newOwnerDestroyed = NO;
    OAPasteboardHelper *helper;
    @autoreleasepool {
        helper = [OAPasteboardHelper helperWithPasteboard:pasteboard];
        DeferredPasteboardOwner *owner = [[[DeferredPasteboardOwner alloc]
            initWithDestructionFlag:&oldOwnerDestroyed] autorelease];
        [helper declareTypes:@[NSPasteboardTypeString] owner:owner];
    }
    @autoreleasepool {
        DeferredPasteboardOwner *owner = [[[DeferredPasteboardOwner alloc]
            initWithDestructionFlag:&newOwnerDestroyed] autorelease];
        [helper declareTypes:@[NSPasteboardTypeString] owner:owner];
    }
    CHECK(oldOwnerDestroyed);
    CHECK(!newOwnerDestroyed);
    CHECK([[pasteboard stringForType:NSPasteboardTypeString] isEqualToString:@"deferred content"]);
    CHECK(newOwnerDestroyed);

    NSURL *file = MakeFile(fixture, @"clipboard.txt", 20);
    @autoreleasepool {
        [NTFilePasteboardSource file:file toPasteboard:pasteboard
            types:@[NSFilenamesPboardType, NSStringPboardType]];
    }
    CHECK([[pasteboard propertyListForType:NSFilenamesPboardType] isEqualToArray:@[[file path]]]);
    CHECK([[pasteboard stringForType:NSStringPboardType] isEqualToString:[file path]]);
    [pasteboard declareTypes:@[] owner:nil];
    [pasteboard releaseGlobally];
    puts("PASS: deferred pasteboard data; owner release on completion/replacement; helper reuse");
}

int main(void)
{
    @autoreleasepool {
        NSURL *fixture = MakeDirectory([NSURL fileURLWithPath:NSTemporaryDirectory()],
            [@"DIXRegression-" stringByAppendingString:[[NSUUID UUID] UUIDString]]);
        @try {
            TestModelAfterRemoval(fixture);
            TestApplicationSorting(fixture);
            TestPasteboardLifetime(fixture);
            TestCopyAndToolbar();
            TestPreferenceReset();
        } @catch (NSException *exception) {
            fprintf(stderr, "%s\n", [[exception description] UTF8String]);
            return 1;
        } @finally {
            CHECK([[NSFileManager defaultManager] removeItemAtURL:fixture error:NULL]);
        }
    }
    return 0;
}
