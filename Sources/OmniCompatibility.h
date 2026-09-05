// Copyright 2026 The DirStat Authors.
//
//  OmniCompatibility.h
//  Disk Inventory X
//
//  Replacement implementations of the Omni framework APIs used by
//  Disk Inventory X, allowing it to build without the Omni frameworks.
//

#import <Cocoa/Cocoa.h>

#define OBPRECONDITION(condition) NSCAssert((condition), @"Precondition failed: %s", #condition)
#define OFNOTEQUAL(left, right) ((left) != (right) && ![(left) isEqual:(right)])

@interface OAApplication : NSApplication
@end

@interface OAController : NSObject
+ (instancetype)sharedController;
@end

@interface NSString (DIXOmniCompatibility)
+ (BOOL)isEmptyString:(NSString *)string;
+ (NSString *)horizontalEllipsisString;
@end

@interface NSDictionary (DIXOmniCompatibility)
- (BOOL)boolForKey:(id)key;
@end

@interface NSMutableDictionary (DIXOmniCompatibility)
- (void)setBoolValue:(BOOL)value forKey:(id<NSCopying>)key;
@end

@interface NSTableView (DIXOmniCompatibility) <NSMenuItemValidation>
- (void)setFont:(NSFont *)font;
- (IBAction)copy:(id)sender;
@end

@interface OASplitView : NSSplitView
- (void)setPositionAutosaveName:(NSString *)name;
@end

@interface OAToolbarItem : NSToolbarItem
{
    id _itemValidationDelegate;
}
@property(nonatomic, assign) id delegate;
- (NSString *)title;
- (void)setTitle:(NSString *)title;
@end

@interface OAToolbarWindowController : NSWindowController <NSToolbarDelegate>
{
    NSDictionary *_toolbarConfiguration;
}
- (NSString *)toolbarConfigurationName;
- (NSDictionary *)toolbarInfoForItem:(NSString *)identifier;
@end

@interface OAPasteboardHelper : NSObject <NSPasteboardTypeOwner>
{
    NSPasteboard *_pasteboard;
    NSMutableDictionary<NSPasteboardType, id> *_ownersByType;
    BOOL _isPasteboardOwner;
}
+ (instancetype)helperWithPasteboard:(NSPasteboard *)pasteboard;
- (void)declareTypes:(NSArray<NSPasteboardType> *)types owner:(id)owner;
@end

@interface OAPreferenceClientRecord : NSObject
{
    NSString *_itemName;
    NSBundle *_bundle;
    NSDictionary *_descriptionDictionary;
}
- (instancetype)initWithItemName:(NSString *)itemName
                          bundle:(NSBundle *)bundle
                     description:(NSDictionary *)description;
- (NSString *)itemName;
- (NSBundle *)bundle;
- (NSDictionary *)descriptionDictionary;
- (NSDictionary *)defaultsDictionary;
- (NSArray *)defaultsArray;
@end

@interface OAPreferenceClient : NSObject
{
@protected
    IBOutlet NSView *controlBox;
    NSDictionary *_preferenceDescription;
    NSArray *_preferenceTopLevelObjects;
}
- (instancetype)initWithDescription:(NSDictionary *)description;
- (BOOL)loadPreferenceNibNamed:(NSString *)nibName bundle:(NSBundle *)bundle;
- (NSView *)preferenceView;
- (void)restoreDefaultsNoPrompt;
- (BOOL)haveAnyDefaultsChanged;
@end

@interface OAPreferenceController : NSObject
{
    NSPanel *_preferencePanel;
    NSTabView *_preferenceTabView;
    NSMutableArray *_preferenceClients;
}
+ (void)registerItemName:(NSString *)itemName
                  bundle:(NSBundle *)bundle
             description:(NSDictionary *)description;
+ (NSArray<OAPreferenceClientRecord *> *)allClientRecords;
- (IBAction)showPreferencesPanel:(id)sender;
- (IBAction)restoreDefaults:(id)sender;
- (void)_restoreDefaultsSheetDidEnd:(NSWindow *)sheet
                         returnCode:(int)returnCode
                        contextInfo:(void *)contextInfo;
@end
