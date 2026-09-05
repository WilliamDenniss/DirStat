// Copyright 2026 The DirStat Authors.

#import "SelectionListController.h"

BOOL g_EnableLogging = NO;

// SelectionListController references this document-model class by identity.
// This standalone lifetime harness does not exercise document-model methods.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation FileKindStatistic
@end
#pragma clang diagnostic pop

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); \
        @throw [NSException exceptionWithName:@"TestFailure" \
            reason:[NSString stringWithUTF8String:#condition] userInfo:nil]; \
    } \
} while (0)

@interface LifecyclePopup : GenericArrayController
{
    BOOL *_destroyed;
}
- (instancetype)initWithDestructionFlag:(BOOL *)flag;
@end
@implementation LifecyclePopup
- (instancetype)initWithDestructionFlag:(BOOL *)flag
{
    self = [super init];
    if (self) _destroyed = flag;
    return self;
}
- (void)dealloc
{
    *_destroyed = YES;
    [super dealloc];
}
@end

@interface LifecycleSelection : SelectionListController
- (void)connectPopup:(GenericArrayController *)popup windowController:(NSWindowController *)controller;
- (void)seedIndexCache;
- (NSUInteger)cachedIndexCount;
@end
@implementation LifecycleSelection
- (void)connectPopup:(GenericArrayController *)popup windowController:(NSWindowController *)controller
{
    // Match the nib's non-owning outlet connections.
    _kindsPopupController = popup;
    _windowController = controller;
}
- (void)seedIndexCache
{
    [_indexes release];
    _indexes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"cached", @"kind", nil];
}
- (NSUInteger)cachedIndexCount { return [_indexes count]; }
@end

static void TestReleaseOrdersWithoutWindowClose(void)
{
    for (NSUInteger popupFirst = 0; popupFirst < 2; popupFirst++) {
        BOOL destroyed = NO;
        @autoreleasepool {
            LifecyclePopup *popup = [[LifecyclePopup alloc] initWithDestructionFlag:&destroyed];
            LifecycleSelection *selection = [[LifecycleSelection alloc] init];
            [selection connectPopup:popup windowController:nil];
            [selection awakeFromNib];
            if (popupFirst) {
                [popup release];
                CHECK(!destroyed);
            }
            [selection release];
            if (!popupFirst) {
                CHECK(!destroyed);
                [popup release];
            }
        }
        CHECK(destroyed);
    }

    // Partial nib initialization must not remove an observation never added.
    BOOL destroyed = NO;
    LifecyclePopup *popup = [[LifecyclePopup alloc] initWithDestructionFlag:&destroyed];
    LifecycleSelection *selection = [[LifecycleSelection alloc] init];
    [selection connectPopup:popup windowController:nil];
    [selection release];
    [popup release];
    CHECK(destroyed);
}

static NSWindow *MakeWindow(void)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    return window;
}

static void TestWindowClose(void)
{
    BOOL destroyed = NO;
    NSWindow *window = MakeWindow();
    NSWindow *otherWindow = MakeWindow();
    NSWindowController *windowController = [[NSWindowController alloc] initWithWindow:window];
    LifecyclePopup *popup = [[LifecyclePopup alloc] initWithDestructionFlag:&destroyed];
    LifecycleSelection *selection = [[LifecycleSelection alloc] init];
    [selection connectPopup:popup windowController:windowController];
    [selection awakeFromNib];
    [selection awakeFromNib];

    @autoreleasepool {
        [selection seedIndexCache];
        [popup rearrangeObjects];
        CHECK([selection cachedIndexCount] == 0);

        // Closing a different window must leave this observation active.
        [otherWindow close];
        [selection seedIndexCache];
        [popup rearrangeObjects];
        CHECK([selection cachedIndexCount] == 0);

        [window close];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillCloseNotification object:window];
        [selection seedIndexCache];
        [popup rearrangeObjects];
        CHECK([selection cachedIndexCount] == 1);
    }

    // Closing the window must release the observation's ownership too.
    [popup release];
    CHECK(destroyed);
    [selection release];
    [windowController release];
    [window release];
    [otherWindow release];
}

int main(void)
{
    @autoreleasepool {
        @try {
            [NSApplication sharedApplication];
            TestReleaseOrdersWithoutWindowClose();
            TestWindowClose();
            puts("PASS: both controller release orders, partial initialization, window-specific and repeated cleanup");
        } @catch (NSException *exception) {
            fprintf(stderr, "%s\n", [[exception description] UTF8String]);
            return 1;
        }
    }
    return 0;
}
