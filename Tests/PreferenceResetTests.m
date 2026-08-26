// Copyright 2026 The DirStat Authors.

#import "OmniCompatibility.h"
#import "PrefsPanelController.h"
#import <objc/runtime.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL %s line %d: %s\n", __FILE__, __LINE__, #condition); \
        @throw [NSException exceptionWithName:@"TestFailure" \
            reason:[NSString stringWithUTF8String:#condition] userInfo:nil]; \
    } \
} while (0)

static NSString * const TestDomain = @"org.example.DIXPreferenceResetTests";
static NSString * const OtherDomain = @"org.example.UnrelatedApplication";
static NSDictionary *RegisteredValues(void)
{
    return @{@"General": @NO, @"Treemap": @YES, @"HiddenPane": @"default"};
}
static NSDictionary *ChangedValues(void)
{
    return @{@"General": @YES, @"Treemap": @NO, @"HiddenPane": @"changed",
        @"UnrelatedSetting": @"keep", @"KindColors": @"custom"};
}

// All writes, including a full-domain reset, stay in these in-memory dictionaries.
@interface ResetTestDefaults : NSUserDefaults
{
    NSMutableDictionary *_testDomains;
}
- (void)resetFixture;
@end
@implementation ResetTestDefaults
- (instancetype)init
{
    self = [super init];
    if (self) {
        _testDomains = [[NSMutableDictionary alloc] init];
        [self resetFixture];
    }
    return self;
}
- (void)dealloc { [_testDomains release]; [super dealloc]; }
- (void)resetFixture
{
    [_testDomains setObject:[NSMutableDictionary dictionaryWithDictionary:ChangedValues()] forKey:TestDomain];
    [_testDomains setObject:[NSMutableDictionary dictionaryWithDictionary:@{@"OtherSetting": @"untouched"}]
                    forKey:OtherDomain];
}
- (id)objectForKey:(NSString *)key
{
    return [[_testDomains objectForKey:TestDomain] objectForKey:key] ?: [RegisteredValues() objectForKey:key];
}
- (BOOL)boolForKey:(NSString *)key { return [[self objectForKey:key] boolValue]; }
- (NSInteger)integerForKey:(NSString *)key { return [[self objectForKey:key] integerValue]; }
- (float)floatForKey:(NSString *)key { return [[self objectForKey:key] floatValue]; }
- (double)doubleForKey:(NSString *)key { return [[self objectForKey:key] doubleValue]; }
- (NSString *)stringForKey:(NSString *)key { return [self objectForKey:key]; }
- (NSArray *)arrayForKey:(NSString *)key { return [self objectForKey:key]; }
- (NSDictionary *)dictionaryForKey:(NSString *)key { return [self objectForKey:key]; }
- (NSData *)dataForKey:(NSString *)key { return [self objectForKey:key]; }
- (NSArray *)stringArrayForKey:(NSString *)key { return [self objectForKey:key]; }
- (void)setObject:(id)value forKey:(NSString *)key
{
    if (value) [[_testDomains objectForKey:TestDomain] setObject:value forKey:key];
    else [self removeObjectForKey:key];
}
- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setFloat:(float)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setURL:(NSURL *)value forKey:(NSString *)key { [self setObject:value forKey:key]; }
- (void)removeObjectForKey:(NSString *)key { [[_testDomains objectForKey:TestDomain] removeObjectForKey:key]; }
- (NSDictionary *)volatileDomainForName:(NSString *)name
{
    return [name isEqualToString:NSRegistrationDomain] ? RegisteredValues() : @{};
}
- (NSDictionary *)persistentDomainForName:(NSString *)name { return [_testDomains objectForKey:name]; }
- (void)setPersistentDomain:(NSDictionary *)domain forName:(NSString *)name
{
    [_testDomains setObject:[NSMutableDictionary dictionaryWithDictionary:domain] forKey:name];
}
- (void)removePersistentDomainForName:(NSString *)name { [_testDomains removeObjectForKey:name]; }
- (void)registerDefaults:(NSDictionary *)defaults { /* Fixture registration remains fixed. */ }
- (void)setVolatileDomain:(NSDictionary *)domain forName:(NSString *)name { /* Never write outside the fixture. */ }
- (void)removeVolatileDomainForName:(NSString *)name { /* Never write outside the fixture. */ }
- (BOOL)synchronize { return YES; }
- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:RegisteredValues()];
    [result addEntriesFromDictionary:[_testDomains objectForKey:TestDomain] ?: @{}];
    return result;
}
@end

static ResetTestDefaults *resetTestDefaults;
static NSArray *resetTestRecords;
static NSEvent *resetTestEvent;
static NSAlert *resetTestAlert;
static void (^resetTestCompletion)(NSModalResponse);
static IMP originalBundleIdentifier;

@interface ResetTestPreferenceController : PrefsPanelController
@end
@implementation ResetTestPreferenceController
+ (NSArray *)allClientRecords { return resetTestRecords; }
@end

@interface ResetTestObserver : NSObject
@property(nonatomic) NSUInteger notificationCount;
@end
@implementation ResetTestObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                       change:(NSDictionary *)change context:(void *)context
{
    self.notificationCount++;
}
@end

static NSUserDefaults *PrivateStandardDefaults(id receiver, SEL selector) { return resetTestDefaults; }
static NSEvent *ControlledCurrentEvent(id receiver, SEL selector) { return resetTestEvent; }
static NSString *PrivateBundleIdentifier(id receiver, SEL selector)
{
    if (receiver == [NSBundle mainBundle]) return TestDomain;
    return ((NSString *(*)(id, SEL))originalBundleIdentifier)(receiver, selector);
}
static void CaptureResetAlert(id receiver, SEL selector, NSWindow *window, void (^completion)(NSModalResponse))
{
    CHECK(resetTestCompletion == nil);
    resetTestAlert = [receiver retain];
    resetTestCompletion = [completion copy];
}
static void SetModifiers(NSEventModifierFlags modifiers)
{
    resetTestEvent = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
        modifierFlags:modifiers timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
}
static void CompleteReset(NSModalResponse response)
{
    CHECK(resetTestAlert != nil && resetTestCompletion != nil);
    @try { resetTestCompletion(response); }
    @finally {
        [resetTestCompletion release];
        resetTestCompletion = nil;
        [resetTestAlert release];
        resetTestAlert = nil;
    }
}

void TestPreferenceReset(void)
{
    [NSApplication sharedApplication];
    ResetTestPreferenceController *controller = [[ResetTestPreferenceController alloc] init];
    NSPanel *panel = [[[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    [panel setReleasedWhenClosed:NO];
    NSTabView *tabs = [[[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    [[panel contentView] addSubview:tabs];
    NSMutableArray *clients = [NSMutableArray array];
    NSMutableArray *records = [NSMutableArray array];
    NSArray *descriptions = @[
        @{@"title": @"General", @"defaultsArray": @[@"General"]},
        @{@"title": @"Treemap", @"defaultsDictionary": @{@"Treemap": @YES}},
        @{@"title": @"Hidden", @"hidden": @YES, @"defaultsArray": @[@"HiddenPane"]}
    ];
    for (NSDictionary *description in descriptions) {
        NSString *title = [description objectForKey:@"title"];
        [records addObject:[[[OAPreferenceClientRecord alloc] initWithItemName:title
            bundle:[NSBundle mainBundle] description:description] autorelease]];
        if ([[description objectForKey:@"hidden"] boolValue]) continue;
        [clients addObject:[[[OAPreferenceClient alloc] initWithDescription:description] autorelease]];
        NSTabViewItem *tab = [[[NSTabViewItem alloc] initWithIdentifier:title] autorelease];
        [tab setLabel:title];
        [tabs addTabViewItem:tab];
    }
    resetTestRecords = records;
    [controller setValue:panel forKey:@"preferencePanel"];
    [controller setValue:clients forKey:@"preferenceClients"];
    [controller setValue:tabs forKey:@"preferenceTabView"];
    resetTestDefaults = [[ResetTestDefaults alloc] init];
    ResetTestObserver *observer = [[ResetTestObserver alloc] init];
    [resetTestDefaults addObserver:observer forKeyPath:@"General" options:0 context:NULL];

    Method defaultsMethod = class_getClassMethod([NSUserDefaults class], @selector(standardUserDefaults));
    Method eventMethod = class_getInstanceMethod([NSApplication class], @selector(currentEvent));
    Method bundleMethod = class_getInstanceMethod([NSBundle class], @selector(bundleIdentifier));
    Method alertMethod = class_getInstanceMethod([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:));
    IMP originalDefaults = method_setImplementation(defaultsMethod, (IMP)PrivateStandardDefaults);
    IMP originalEvent = method_setImplementation(eventMethod, (IMP)ControlledCurrentEvent);
    originalBundleIdentifier = method_setImplementation(bundleMethod, (IMP)PrivateBundleIdentifier);
    IMP originalAlert = method_setImplementation(alertMethod, (IMP)CaptureResetAlert);
    @try {
        NSArray *modifiers = @[@0, @(NSEventModifierFlagOption), @(NSEventModifierFlagOption | NSEventModifierFlagShift)];
        NSMutableArray *prompts = [NSMutableArray array];
        for (NSNumber *flags in modifiers) {
            [resetTestDefaults resetFixture];
            observer.notificationCount = 0;
            [tabs selectTabViewItemAtIndex:0];
            SetModifiers([flags unsignedIntegerValue]);
            [controller restoreDefaults:nil];
            CHECK(resetTestAlert != nil);
            [prompts addObject:[NSString stringWithFormat:@"%@\n%@", [resetTestAlert messageText], [resetTestAlert informativeText]]];
            CompleteReset(NSAlertSecondButtonReturn);
            CHECK([[resetTestDefaults persistentDomainForName:TestDomain] isEqualToDictionary:ChangedValues()]);
            CHECK(observer.notificationCount == 0);
        }
        CHECK([[NSSet setWithArray:prompts] count] == 3);

        // No modifier resets only the pane selected when Reset was clicked.
        [tabs selectTabViewItemAtIndex:0];
        SetModifiers(0);
        [controller restoreDefaults:nil];
        [tabs selectTabViewItemAtIndex:1];
        SetModifiers(NSEventModifierFlagOption | NSEventModifierFlagShift);
        CompleteReset(NSAlertFirstButtonReturn);
        CHECK(![resetTestDefaults boolForKey:@"General"]);
        CHECK(![resetTestDefaults boolForKey:@"Treemap"]);
        CHECK([[resetTestDefaults stringForKey:@"HiddenPane"] isEqualToString:@"changed"]);
        CHECK([[resetTestDefaults stringForKey:@"UnrelatedSetting"] isEqualToString:@"keep"]);
        CHECK(observer.notificationCount > 0);

        // Option includes registered panes that have never been opened/loaded.
        [resetTestDefaults resetFixture];
        observer.notificationCount = 0;
        SetModifiers(NSEventModifierFlagOption);
        [controller restoreDefaults:nil];
        SetModifiers(0);
        CompleteReset(NSAlertFirstButtonReturn);
        CHECK(![resetTestDefaults boolForKey:@"General"]);
        CHECK([resetTestDefaults boolForKey:@"Treemap"]);
        CHECK([[resetTestDefaults stringForKey:@"HiddenPane"] isEqualToString:@"default"]);
        CHECK([[resetTestDefaults stringForKey:@"UnrelatedSetting"] isEqualToString:@"keep"]);
        CHECK([[resetTestDefaults stringForKey:@"KindColors"] isEqualToString:@"custom"]);
        CHECK(observer.notificationCount > 0);

        // Option+Shift removes every stored app setting, preserving other domains.
        [resetTestDefaults resetFixture];
        observer.notificationCount = 0;
        SetModifiers(NSEventModifierFlagOption | NSEventModifierFlagShift);
        [controller restoreDefaults:nil];
        CompleteReset(NSAlertFirstButtonReturn);
        CHECK([[resetTestDefaults persistentDomainForName:TestDomain] count] == 0);
        CHECK([resetTestDefaults objectForKey:@"UnrelatedSetting"] == nil);
        CHECK([resetTestDefaults objectForKey:@"KindColors"] == nil);
        CHECK(![resetTestDefaults boolForKey:@"General"]);
        CHECK([resetTestDefaults boolForKey:@"Treemap"]);
        CHECK([[[resetTestDefaults persistentDomainForName:OtherDomain] objectForKey:@"OtherSetting"]
            isEqualToString:@"untouched"]);
        CHECK(observer.notificationCount > 0);
    } @finally {
        method_setImplementation(alertMethod, originalAlert);
        method_setImplementation(bundleMethod, originalBundleIdentifier);
        method_setImplementation(eventMethod, originalEvent);
        method_setImplementation(defaultsMethod, originalDefaults);
        [resetTestCompletion release];
        resetTestCompletion = nil;
        [resetTestAlert release];
        resetTestAlert = nil;
        resetTestEvent = nil;
        resetTestRecords = nil;
        [resetTestDefaults removeObserver:observer forKeyPath:@"General"];
        [observer release];
        [resetTestDefaults release];
        resetTestDefaults = nil;
        [controller release];
    }
    puts("PASS: selected-pane, all-pane and app-domain reset actions, confirmation/cancellation and KVO");
}
