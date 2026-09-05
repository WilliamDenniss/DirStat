// Copyright 2026 The DirStat Authors.
//
//  OmniCompatibility.m
//  Disk Inventory X
//

#import "OmniCompatibility.h"

@implementation OAApplication

+ (void)initialize
{
    if (self != [OAApplication class])
        return;

    NSDictionary *registrations = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OFRegistrations"];
    NSDictionary *defaults = [[registrations objectForKey:@"NSUserDefaults"] objectForKey:@"defaultsDictionary"];
    if (defaults != nil)
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

@end

@implementation OAController

+ (instancetype)sharedController
{
    static OAController *sharedController = nil;
    if (sharedController == nil)
    {
        NSString *className = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OFControllerClass"];
        Class controllerClass = NSClassFromString(className);
        if (controllerClass == Nil || ![controllerClass isSubclassOfClass:[OAController class]])
            controllerClass = self;
        sharedController = [[controllerClass alloc] init];
    }
    return (id)sharedController;
}

@end

@implementation NSString (DIXOmniCompatibility)

+ (BOOL)isEmptyString:(NSString *)string
{
    return string == nil || [string length] == 0;
}

+ (NSString *)horizontalEllipsisString
{
    return @"\u2026";
}

@end


@implementation NSDictionary (DIXOmniCompatibility)

- (BOOL)boolForKey:(id)key
{
    return [[self objectForKey:key] boolValue];
}

@end


@implementation NSMutableDictionary (DIXOmniCompatibility)

- (void)setBoolValue:(BOOL)value forKey:(id<NSCopying>)key
{
    [self setObject:[NSNumber numberWithBool:value] forKey:key];
}

@end


static SEL DIXPasteboardWriterForTable(NSTableView *table)
{
    return [table isKindOfClass:[NSOutlineView class]]
        ? @selector(outlineView:writeItems:toPasteboard:)
        : @selector(tableView:writeRowsWithIndexes:toPasteboard:);
}

@implementation NSTableView (DIXOmniCompatibility)

- (void)setFont:(NSFont *)font
{
    for (NSTableColumn *column in [self tableColumns])
    {
        id cell = [column dataCell];
        if ([cell respondsToSelector:@selector(setFont:)])
            [cell setFont:font];
    }
    [self reloadData];
}

- (IBAction)copy:(id)sender
{
    NSIndexSet *rows = [self selectedRowIndexes];
    id source = [self dataSource];
    if ([rows count] == 0 || ![source respondsToSelector:DIXPasteboardWriterForTable(self)])
        return;

    BOOL copied;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    if ([self isKindOfClass:[NSOutlineView class]])
    {
        NSOutlineView *outline = (NSOutlineView *)self;
        NSMutableArray *items = [NSMutableArray arrayWithCapacity:[rows count]];
        [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
            [items addObject:[outline itemAtRow:row]];
        }];
        copied = [source outlineView:outline writeItems:items toPasteboard:pasteboard];
    }
    else
        copied = [source tableView:self writeRowsWithIndexes:rows toPasteboard:pasteboard];

    if (!copied)
        NSBeep();
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(copy:))
        return [self numberOfSelectedRows] > 0 &&
            [[self dataSource] respondsToSelector:DIXPasteboardWriterForTable(self)];

    return [self validateUserInterfaceItem:item];
}

@end


@implementation OASplitView

- (void)setPositionAutosaveName:(NSString *)name
{
    [self setAutosaveName:name];
}

@end


@implementation OAToolbarItem

@synthesize delegate = _itemValidationDelegate;

- (NSString *)title
{
    return [self label];
}

- (void)setTitle:(NSString *)title
{
    // The menu validation adapter uses titles to update toolbar labels.
    [self setLabel:title];
}

- (void)validate
{
    if ([_itemValidationDelegate respondsToSelector:@selector(validateToolbarItem:)])
        [self setEnabled:[_itemValidationDelegate validateToolbarItem:self]];
    else
        [super validate];
}

@end


@implementation OAToolbarWindowController

- (void)dealloc
{
    [_toolbarConfiguration release];
    [super dealloc];
}

- (NSString *)toolbarConfigurationName
{
    return nil;
}

- (NSDictionary *)toolbarConfiguration
{
    if (_toolbarConfiguration == nil)
    {
        NSString *configurationName = [self toolbarConfigurationName];
        NSString *path = [[NSBundle mainBundle] pathForResource:configurationName ofType:@"toolbar"];
        _toolbarConfiguration = [[NSDictionary alloc] initWithContentsOfFile:path];
    }
    return _toolbarConfiguration;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    NSString *configurationName = [self toolbarConfigurationName];
    if ([NSString isEmptyString:configurationName] || [self toolbarConfiguration] == nil)
        return;

    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:configurationName] autorelease];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:YES];
    [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [[self window] setToolbar:toolbar];
}

- (NSDictionary *)toolbarInfoForItem:(NSString *)identifier
{
    return [[[self toolbarConfiguration] objectForKey:@"itemInfoByIdentifier"] objectForKey:identifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [[self toolbarConfiguration] objectForKey:@"allowedItemIdentifiers"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [[self toolbarConfiguration] objectForKey:@"defaultItemIdentifiers"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)willBeInserted
{
    NSDictionary *itemInfo = [self toolbarInfoForItem:identifier];
    if (itemInfo == nil)
        return nil;

    OAToolbarItem *item = [[[OAToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];

    NSString *label = [itemInfo objectForKey:@"label"];
    if ([NSString isEmptyString:label])
        label = identifier;
    [item setLabel:NSLocalizedString(label, @"")];

    NSString *paletteLabel = [itemInfo objectForKey:@"paletteLabel"];
    [item setPaletteLabel:[NSString isEmptyString:paletteLabel] ? [item label] : NSLocalizedString(paletteLabel, @"")];

    NSString *toolTip = [itemInfo objectForKey:@"toolTip"];
    if (![NSString isEmptyString:toolTip])
        [item setToolTip:NSLocalizedString(toolTip, @"")];

    NSString *imageName = [itemInfo objectForKey:@"imageName"];
    if (![NSString isEmptyString:imageName])
        [item setImage:[NSImage imageNamed:imageName]];

    NSString *actionName = [itemInfo objectForKey:@"action"];
    if (![NSString isEmptyString:actionName])
        [item setAction:NSSelectorFromString(actionName)];

    NSString *targetName = [itemInfo objectForKey:@"target"];
    if ([targetName isEqualToString:@"firstResponder"])
        [item setTarget:nil];
    else if (![NSString isEmptyString:targetName])
        [item setTarget:[self valueForKeyPath:targetName]];
    else
        [item setTarget:self];

    return item;
}

@end


@implementation OAPasteboardHelper

+ (instancetype)helperWithPasteboard:(NSPasteboard *)pasteboard
{
    OAPasteboardHelper *helper = [[[self alloc] init] autorelease];
    helper->_pasteboard = [pasteboard retain];
    helper->_ownersByType = [[NSMutableDictionary alloc] init];
    return helper;
}

- (void)dealloc
{
    [_ownersByType release];
    [_pasteboard release];
    [super dealloc];
}

- (void)declareTypes:(NSArray<NSPasteboardType> *)types owner:(id)owner
{
    // Redeclaration may synchronously revoke our previous ownership retain.
    [self retain];
    @try {
        BOOL hasPromises = owner != nil && [types count] != 0;
        [_pasteboard declareTypes:types owner:hasPromises ? self : nil];
        [_ownersByType removeAllObjects];

        if (hasPromises) {
            for (NSPasteboardType type in types)
                [_ownersByType setObject:owner forKey:type];
            if (!_isPasteboardOwner) {
                _isPasteboardOwner = YES;
                [self retain];
            }
        } else {
            [self pasteboardChangedOwner:_pasteboard];
        }
    } @finally {
        [self release];
    }
}

- (void)pasteboard:(NSPasteboard *)pasteboard provideDataForType:(NSPasteboardType)type
{
    [self retain];
    id owner = [[_ownersByType objectForKey:type] retain];
    @try {
        [owner pasteboard:pasteboard provideDataForType:type];
        if ([_ownersByType objectForKey:type] == owner)
            [_ownersByType removeObjectForKey:type];

        // AppKit sends no ownership-change notification after all promised
        // types have been provided. Release the lifetime retain here as well.
        if ([_ownersByType count] == 0)
            [self pasteboardChangedOwner:pasteboard];
    } @finally {
        [owner release];
        [self release];
    }
}

- (void)pasteboardChangedOwner:(NSPasteboard *)pasteboard
{
    if (!_isPasteboardOwner)
        return;

    _isPasteboardOwner = NO;
    [_ownersByType removeAllObjects];

    // Balance the ownership retain last because this may deallocate self.
    [self release];
}

@end


@implementation OAPreferenceClientRecord

- (instancetype)initWithItemName:(NSString *)itemName
                          bundle:(NSBundle *)bundle
                     description:(NSDictionary *)description
{
    self = [super init];
    if (self != nil)
    {
        _itemName = [itemName copy];
        _bundle = [bundle retain];
        _descriptionDictionary = [description copy];
    }
    return self;
}

- (void)dealloc
{
    [_itemName release];
    [_bundle release];
    [_descriptionDictionary release];
    [super dealloc];
}

- (NSString *)itemName { return _itemName; }
- (NSBundle *)bundle { return _bundle; }
- (NSDictionary *)descriptionDictionary { return _descriptionDictionary; }
- (NSDictionary *)defaultsDictionary { return [_descriptionDictionary objectForKey:@"defaultsDictionary"] ?: [NSDictionary dictionary]; }
- (NSArray *)defaultsArray { return [_descriptionDictionary objectForKey:@"defaultsArray"] ?: [NSArray array]; }

@end


static void DIXRemovePreferenceValues(NSArray<NSString *> *keys)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in keys)
    {
        [defaults willChangeValueForKey:key];
        [defaults removeObjectForKey:key];
        [defaults didChangeValueForKey:key];
    }
}

@implementation OAPreferenceClient

- (instancetype)initWithDescription:(NSDictionary *)description
{
    self = [super init];
    if (self != nil)
        _preferenceDescription = [description copy];
    return self;
}

- (void)dealloc
{
    [_preferenceDescription release];
    [_preferenceTopLevelObjects release];
    [super dealloc];
}

- (BOOL)loadPreferenceNibNamed:(NSString *)nibName bundle:(NSBundle *)bundle
{
    NSNib *nib = [[[NSNib alloc] initWithNibNamed:nibName bundle:bundle] autorelease];
    NSArray *topLevelObjects = nil;
    if (nib == nil || ![nib instantiateWithOwner:self topLevelObjects:&topLevelObjects])
        return NO;

    [_preferenceTopLevelObjects release];
    _preferenceTopLevelObjects = [topLevelObjects retain];
    return YES;
}

- (NSView *)preferenceView
{
    NSView *largestView = nil;
    for (id object in _preferenceTopLevelObjects)
    {
        if (![object isKindOfClass:[NSView class]])
            continue;
        if (largestView == nil || NSWidth([object frame]) * NSHeight([object frame]) >
                                  NSWidth([largestView frame]) * NSHeight([largestView frame]))
            largestView = object;
    }
    return largestView ?: controlBox;
}

- (NSArray *)preferenceKeys
{
    NSMutableArray *keys = [NSMutableArray arrayWithArray:[_preferenceDescription objectForKey:@"defaultsArray"] ?: [NSArray array]];
    [keys addObjectsFromArray:[[_preferenceDescription objectForKey:@"defaultsDictionary"] allKeys] ?: [NSArray array]];
    return keys;
}

- (void)restoreDefaultsNoPrompt
{
    DIXRemovePreferenceValues([self preferenceKeys]);
}

- (BOOL)haveAnyDefaultsChanged
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *registeredDefaults = [defaults volatileDomainForName:NSRegistrationDomain];
    for (NSString *key in [self preferenceKeys])
    {
        id value = [defaults objectForKey:key];
        id registeredValue = [registeredDefaults objectForKey:key];
        if (OFNOTEQUAL(value, registeredValue))
            return YES;
    }
    return NO;
}

@end


@implementation OAPreferenceController

+ (void)registerItemName:(NSString *)itemName
                  bundle:(NSBundle *)bundle
             description:(NSDictionary *)description
{
    // Registration is data-driven from Info.plist in this compatibility layer.
}

+ (NSArray<OAPreferenceClientRecord *> *)allClientRecords
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSDictionary *registrations = [[bundle infoDictionary] objectForKey:@"OFRegistrations"];
    NSString *registrationName = NSStringFromClass(self);
    NSDictionary *preferenceDescriptions = [registrations objectForKey:registrationName];
    if (preferenceDescriptions == nil)
        preferenceDescriptions = [registrations objectForKey:@"PrefsPanelController"];

    NSMutableArray *records = [NSMutableArray array];
    for (NSString *itemName in preferenceDescriptions)
    {
        OAPreferenceClientRecord *record = [[[OAPreferenceClientRecord alloc]
            initWithItemName:itemName
                      bundle:bundle
                 description:[preferenceDescriptions objectForKey:itemName]] autorelease];
        [records addObject:record];
    }

    [records sortUsingComparator:^NSComparisonResult(OAPreferenceClientRecord *left, OAPreferenceClientRecord *right) {
        NSNumber *leftOrdering = [[left descriptionDictionary] objectForKey:@"ordering"] ?: @0;
        NSNumber *rightOrdering = [[right descriptionDictionary] objectForKey:@"ordering"] ?: @0;
        return [leftOrdering compare:rightOrdering];
    }];
    return records;
}

- (void)dealloc
{
    [_preferencePanel release];
    [_preferenceTabView release];
    [_preferenceClients release];
    [super dealloc];
}

- (void)buildPreferencePanel
{
    const CGFloat buttonAreaHeight = 50.0;
    const NSSize panelSize = NSMakeSize(560.0, 420.0 + buttonAreaHeight);
    _preferencePanel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0, panelSize.width, panelSize.height)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [_preferencePanel setTitle:NSLocalizedString(@"Preferences", @"")];
    [_preferencePanel setReleasedWhenClosed:NO];
    [_preferencePanel center];

    NSRect tabFrame = NSMakeRect(0.0, buttonAreaHeight, panelSize.width, panelSize.height - buttonAreaHeight);
    _preferenceTabView = [[NSTabView alloc] initWithFrame:tabFrame];
    NSTabView *tabView = _preferenceTabView;
    [tabView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [[_preferencePanel contentView] addSubview:tabView];

    NSButton *resetButton = [[[NSButton alloc] initWithFrame:NSMakeRect(14.0, 10.0, 110.0, 32.0)] autorelease];
    [resetButton setButtonType:NSButtonTypeMomentaryPushIn];
    [resetButton setBezelStyle:NSBezelStyleRounded];
    [resetButton setTitle:NSLocalizedStringFromTable(@"Reset", @"Preferences", @"")];
    [resetButton setToolTip:NSLocalizedStringFromTable(@"Reset this pane. Hold Option to reset all panes, or Option-Shift to also reset other app settings.", @"Preferences", @"")];
    [resetButton sizeToFit];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(restoreDefaults:)];
    [[_preferencePanel contentView] addSubview:resetButton];

    _preferenceClients = [[NSMutableArray alloc] init];
    for (OAPreferenceClientRecord *record in [[self class] allClientRecords])
    {
        NSDictionary *description = [record descriptionDictionary];
        if ([[description objectForKey:@"hidden"] boolValue])
            continue;

        NSString *className = [description objectForKey:@"identifier"] ?: [record itemName];
        Class clientClass = NSClassFromString(className);
        if (clientClass == Nil || ![clientClass isSubclassOfClass:[OAPreferenceClient class]])
            clientClass = [OAPreferenceClient class];

        OAPreferenceClient *client = [[[clientClass alloc] initWithDescription:description] autorelease];
        if (![client loadPreferenceNibNamed:[description objectForKey:@"nib"] bundle:[record bundle]])
            continue;

        NSView *view = [client preferenceView];
        if (view == nil)
            continue;

        [view setFrame:NSMakeRect(0.0, 0.0, NSWidth(tabFrame) - 20.0, NSHeight(tabFrame) - 40.0)];
        [view setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

        NSTabViewItem *tabItem = [[[NSTabViewItem alloc] initWithIdentifier:className] autorelease];
        NSString *title = [description objectForKey:@"title"] ?: className;
        [tabItem setLabel:NSLocalizedStringFromTable(title, @"Preferences", @"")];
        [tabItem setView:view];
        [tabView addTabViewItem:tabItem];
        [_preferenceClients addObject:client];
    }
}

- (IBAction)showPreferencesPanel:(id)sender
{
    if (_preferencePanel == nil)
        [self buildPreferencePanel];
    [_preferencePanel makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)restoreDefaults:(id)sender
{
    if (_preferencePanel == nil || [_preferencePanel attachedSheet] != nil)
        return;

    NSEventModifierFlags modifiers = [[NSApp currentEvent] modifierFlags];
    BOOL resetAllPanes = (modifiers & NSEventModifierFlagOption) != 0;
    BOOL resetApplication = resetAllPanes && (modifiers & NSEventModifierFlagShift) != 0;
    OAPreferenceClient *currentClient = nil;
    NSString *message;
    NSString *informativeText;
    if (resetApplication)
    {
        message = NSLocalizedStringFromTable(@"Reset all preferences and other settings?", @"Preferences", @"");
        informativeText = NSLocalizedStringFromTable(@"All preferences and other saved settings for this app, including window sizes and toolbars, will return to their default values.", @"Preferences", @"");
    }
    else if (resetAllPanes)
    {
        message = NSLocalizedStringFromTable(@"Reset all preferences?", @"Preferences", @"");
        informativeText = NSLocalizedStringFromTable(@"All settings in these preference panes will return to their default values.", @"Preferences", @"");
    }
    else
    {
        NSTabViewItem *selectedTab = [_preferenceTabView selectedTabViewItem];
        NSInteger index = selectedTab == nil ? NSNotFound : [_preferenceTabView indexOfTabViewItem:selectedTab];
        if (index == NSNotFound || index < 0 || (NSUInteger)index >= [_preferenceClients count])
            return;
        currentClient = [_preferenceClients objectAtIndex:(NSUInteger)index];
        message = [NSString stringWithFormat:NSLocalizedStringFromTable(@"Reset %@ preferences?", @"Preferences", @""), [selectedTab label]];
        informativeText = NSLocalizedStringFromTable(@"Only settings in this preference pane will return to their default values.", @"Preferences", @"");
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:message];
    [alert setInformativeText:informativeText];
    [alert addButtonWithTitle:NSLocalizedStringFromTable(@"Reset", @"Preferences", @"")];
    [alert addButtonWithTitle:NSLocalizedStringFromTable(@"Cancel", @"Preferences", @"")];
    [alert beginSheetModalForWindow:_preferencePanel completionHandler:^(NSModalResponse returnCode) {
        if (resetAllPanes)
            [self _restoreDefaultsSheetDidEnd:[alert window] returnCode:(int)returnCode contextInfo:resetApplication ? (void *)1 : NULL];
        else if (returnCode == NSAlertFirstButtonReturn)
            [currentClient restoreDefaultsNoPrompt];
    }];
}

- (void)_restoreDefaultsSheetDidEnd:(NSWindow *)sheet
                         returnCode:(int)returnCode
                        contextInfo:(void *)contextInfo
{
    if (returnCode != NSAlertFirstButtonReturn)
        return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (contextInfo != NULL)
    {
        NSString *domainName = [[NSBundle mainBundle] bundleIdentifier];
        if ([domainName length] == 0)
            return;

        NSArray *keys = [[defaults persistentDomainForName:domainName] allKeys];
        for (NSString *key in keys)
            [defaults willChangeValueForKey:key];
        [defaults removePersistentDomainForName:domainName];
        for (NSString *key in [keys reverseObjectEnumerator])
            [defaults didChangeValueForKey:key];
    }
    else
    {
        NSMutableSet *keys = [NSMutableSet set];
        for (OAPreferenceClientRecord *record in [[self class] allClientRecords])
        {
            [keys addObjectsFromArray:[[record defaultsDictionary] allKeys]];
            [keys addObjectsFromArray:[record defaultsArray]];
        }
        DIXRemovePreferenceValues([keys allObjects]);
    }
}

@end
