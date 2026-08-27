//
//  FSItemScannerTests.m
//  Disk Inventory XTests
//

#import <XCTest/XCTest.h>

#import "FSItem.h"
#import "NSURL-Extensions.h"
#import "VolumeScanProgress.h"

// Keep these tests as logic tests while exercising the production scanner.
// FSItem's pasteboard support is unrelated to traversal, but its class
// reference must still be satisfied when FSItem.m is linked into the bundle.
@interface NTFilePasteboardSource : NSObject
@end

@implementation NTFilePasteboardSource

+ (id)file:(NSURL *)URL toPasteboard:(NSPasteboard *)pasteboard types:(NSArray *)types
{
    return nil;
}

@end

BOOL g_EnableLogging = NO;

@interface DIXResourceIdentifierProbe : NSObject
{
    NSUInteger _requestCount;
    id _identifier;
}

@property(nonatomic, readonly) NSUInteger requestCount;
@property(nonatomic, retain) id identifier;

@end


@implementation DIXResourceIdentifierProbe

@synthesize identifier = _identifier;

- (void)dealloc
{
    [_identifier release];
    [super dealloc];
}

- (NSUInteger)requestCount
{
    return _requestCount;
}

- (BOOL)getResourceValue:(out id *)value
                   forKey:(NSURLResourceKey)key
                    error:(out NSError **)error
{
    _requestCount++;
    XCTAssertEqualObjects(key, NSURLFileResourceIdentifierKey);
    if ( value != NULL )
        *value = _identifier;
    if ( error != NULL )
        *error = nil;
    return YES;
}

@end

@interface FSItem (ScannerTesting)

- (void)loadChildrenAndSetKindStrings:(BOOL)setKindStrings
                      usePhysicalSize:(BOOL)usePhysicalSize;
+ (NSArray<NSURLResourceKey> *)resourceKeysForUsePhysicalSize:(BOOL)usePhysicalSize
							 collectVolumeProgressMetadata:(BOOL)collectVolumeProgressMetadata;

@end


@interface FSItemScannerDelegate : NSObject
{
    NSMutableArray *_events;
    BOOL _cancelOnFirstDiscoveredItem;
    BOOL _usePhysicalSize;
    BOOL _collectVolumeProgressMetadata;
    NSUInteger _volumeProgressMetadataRequestCount;
    VolumeScanProgress *_progress;
}

@property(nonatomic, readonly) NSArray *events;
@property(nonatomic) BOOL cancelOnFirstDiscoveredItem;
@property(nonatomic) BOOL usePhysicalSize;
@property(nonatomic) BOOL collectVolumeProgressMetadata;
@property(nonatomic, readonly) NSUInteger volumeProgressMetadataRequestCount;
@property(nonatomic, retain) VolumeScanProgress *progress;

@end


@implementation FSItemScannerDelegate

- (id)init
{
    self = [super init];
    if (self != nil)
        _events = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    [_events release];
    [_progress release];
    [super dealloc];
}

- (VolumeScanProgress *)progress
{
    return _progress;
}

- (void)setProgress:(VolumeScanProgress *)progress
{
    [progress retain];
    [_progress release];
    _progress = progress;
}

- (NSArray *)events
{
    return _events;
}

- (BOOL)cancelOnFirstDiscoveredItem
{
    return _cancelOnFirstDiscoveredItem;
}

- (void)setCancelOnFirstDiscoveredItem:(BOOL)cancel
{
    _cancelOnFirstDiscoveredItem = cancel;
}

- (BOOL)usePhysicalSize
{
    return _usePhysicalSize;
}

- (void)setUsePhysicalSize:(BOOL)usePhysicalSize
{
    _usePhysicalSize = usePhysicalSize;
}

- (BOOL)collectVolumeProgressMetadata
{
    return _collectVolumeProgressMetadata;
}

- (void)setCollectVolumeProgressMetadata:(BOOL)collectVolumeProgressMetadata
{
    _collectVolumeProgressMetadata = collectVolumeProgressMetadata;
}

- (NSUInteger)volumeProgressMetadataRequestCount
{
    return _volumeProgressMetadataRequestCount;
}

- (BOOL)fsItemEnteringFolder:(FSItem *)item
{
    [_events addObject:[NSString stringWithFormat:@"enter:%@", [item path]]];
    return YES;
}

- (BOOL)fsItemExittingFolder:(FSItem *)item
{
    [_events addObject:[NSString stringWithFormat:@"exit:%@", [item path]]];
    return YES;
}

- (BOOL)fsItemDidProcessItem:(FSItem *)item
{
    [_events addObject:[NSString stringWithFormat:@"process:%@", [item path]]];

    if (_progress != nil && ![item isFolder])
    {
        NSURL *URL = [item fileURL];
        NSNumber *allocatedSize = [URL physicalSize];
        NSNumber *linkCount = [URL getNumberValue:NSURLLinkCountKey];
        id identifier = nil;
        if ([linkCount unsignedIntegerValue] > 1)
            [URL getCachedResourceValue:&identifier forKey:NSURLFileResourceIdentifierKey error:nil];
        [_progress recordAllocatedBytes:[allocatedSize unsignedLongLongValue]
                         fileIdentifier:identifier
                              linkCount:linkCount == nil ? 1 : [linkCount unsignedIntegerValue]];
    }

    return !_cancelOnFirstDiscoveredItem;
}

- (BOOL)fsItemShouldUsePhysicalFileSize:(FSItem *)item
{
    return _usePhysicalSize;
}

- (BOOL)fsItemShouldCollectVolumeProgressMetadata:(FSItem *)item
{
    _volumeProgressMetadataRequestCount++;
    return _collectVolumeProgressMetadata;
}

@end


@interface FSItemScannerTests : XCTestCase
{
    NSString *_fixturePath;
}

@end


@implementation FSItemScannerTests

- (void)assertResourceKeys:(NSArray<NSURLResourceKey> *)resourceKeys
            containObject:(NSURLResourceKey)resourceKey
{
    XCTAssertTrue([resourceKeys containsObject:resourceKey], @"Expected resource key %@ in %@",
                  resourceKey, resourceKeys);
}

- (void)assertResourceKeys:(NSArray<NSURLResourceKey> *)resourceKeys
               omitObject:(NSURLResourceKey)resourceKey
{
    XCTAssertFalse([resourceKeys containsObject:resourceKey], @"Expected resource key %@ to be absent from %@",
                   resourceKey, resourceKeys);
}

- (void)setUp
{
    [super setUp];

    // Keep scanner fixtures beside the explicitly configured test products.
    // Verification builds place those products in build/Verification/Products,
    // so no test-created files escape the repository-local verification tree.
    NSString *productsPath = [[[NSBundle bundleForClass:[self class]] bundlePath]
                              stringByDeletingLastPathComponent];
    NSString *fixturesPath = [[productsPath stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent:@"TestFixtures"];
    NSString *fixtureName = [NSString stringWithFormat:@"DiskInventoryXScanner-%@",
                             [[NSUUID UUID] UUIDString]];
    _fixturePath = [[[fixturesPath stringByAppendingPathComponent:fixtureName]
                     stringByStandardizingPath] copy];

    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:_fixturePath
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error], @"%@", error);
}

- (void)tearDown
{
    if (_fixturePath != nil)
    {
        NSError *error = nil;
        XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:_fixturePath error:&error],
                      @"%@", error);
        [_fixturePath release];
        _fixturePath = nil;
    }

    [super tearDown];
}

- (void)createDirectory:(NSString *)relativePath
{
    NSString *path = [_fixturePath stringByAppendingPathComponent:relativePath];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:path
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error], @"%@", error);
}

- (void)createZeroByteFile:(NSString *)relativePath
{
    NSString *path = [_fixturePath stringByAppendingPathComponent:relativePath];
    XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:path
                                                          contents:[NSData data]
                                                        attributes:nil]);
}

- (void)createFile:(NSString *)relativePath length:(NSUInteger)length
{
    NSString *path = [_fixturePath stringByAppendingPathComponent:relativePath];
    NSMutableData *data = [NSMutableData dataWithLength:length];
    XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:path
                                                          contents:data
                                                        attributes:nil]);
}

- (FSItem *)scanWithDelegate:(FSItemScannerDelegate *)delegate
             usePhysicalSize:(BOOL)usePhysicalSize
{
    FSItem *root = [[[FSItem alloc] initWithPath:_fixturePath] autorelease];
    [root setDelegate:delegate];
    [root loadChildrenAndSetKindStrings:NO usePhysicalSize:usePhysicalSize];
    return root;
}

- (void)testZeroByteFileAndNestedDirectoriesAreScanned
{
    [self createDirectory:@"outer/inner"];
    [self createZeroByteFile:@"outer/inner/empty"];

    FSItemScannerDelegate *delegate = [[[FSItemScannerDelegate alloc] init] autorelease];
    FSItem *root = [self scanWithDelegate:delegate usePhysicalSize:YES];

    XCTAssertEqual([root childCount], (unsigned)1);
    FSItem *outer = [root childAtIndex:0];
    XCTAssertTrue([outer isFolder]);
    XCTAssertEqual([outer childCount], (unsigned)1);
    FSItem *inner = [outer childAtIndex:0];
    XCTAssertTrue([inner isFolder]);
    XCTAssertEqual([inner childCount], (unsigned)1);
    FSItem *empty = [inner childAtIndex:0];
    XCTAssertFalse([empty isFolder]);
    XCTAssertEqual([empty sizeValue], (unsigned long long)0);
}

- (void)testLogicalSpinnerResourceKeysOmitProgressOnlyMetadata
{
    NSArray<NSURLResourceKey> *resourceKeys = [FSItem
        resourceKeysForUsePhysicalSize:NO
        collectVolumeProgressMetadata:NO];

    [self assertResourceKeys:resourceKeys containObject:NSURLTotalFileSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLFileSizeKey];
    [self assertResourceKeys:resourceKeys omitObject:NSURLTotalFileAllocatedSizeKey];
    [self assertResourceKeys:resourceKeys omitObject:NSURLFileAllocatedSizeKey];
    [self assertResourceKeys:resourceKeys omitObject:NSURLLinkCountKey];
    [self assertResourceKeys:resourceKeys omitObject:NSURLFileResourceIdentifierKey];
}

- (void)testPhysicalSpinnerResourceKeysIncludeAllocatedSizeFallbacksOnly
{
    NSArray<NSURLResourceKey> *resourceKeys = [FSItem
        resourceKeysForUsePhysicalSize:YES
        collectVolumeProgressMetadata:NO];

    [self assertResourceKeys:resourceKeys containObject:NSURLTotalFileAllocatedSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLFileAllocatedSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLTotalFileSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLFileSizeKey];
    [self assertResourceKeys:resourceKeys omitObject:NSURLLinkCountKey];
    [self assertResourceKeys:resourceKeys omitObject:NSURLFileResourceIdentifierKey];
}

- (void)testVolumeProgressResourceKeysIncludeHardLinkCountButNotIdentifier
{
    NSArray<NSURLResourceKey> *resourceKeys = [FSItem
        resourceKeysForUsePhysicalSize:NO
        collectVolumeProgressMetadata:YES];

    [self assertResourceKeys:resourceKeys containObject:NSURLTotalFileAllocatedSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLFileAllocatedSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLTotalFileSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLFileSizeKey];
    [self assertResourceKeys:resourceKeys containObject:NSURLLinkCountKey];
    [self assertResourceKeys:resourceKeys omitObject:NSURLFileResourceIdentifierKey];
}

- (void)testScannerAsksDelegateWhetherVolumeProgressMetadataIsRequired
{
    [self createZeroByteFile:@"data"];
    FSItemScannerDelegate *delegate = [[[FSItemScannerDelegate alloc] init] autorelease];
    delegate.collectVolumeProgressMetadata = YES;

    [self scanWithDelegate:delegate usePhysicalSize:NO];

    XCTAssertEqual(delegate.volumeProgressMetadataRequestCount, (NSUInteger)1);
}

- (void)testFileIdentifierLookupIsLazyForPotentialHardLinks
{
    DIXResourceIdentifierProbe *probe = [[[DIXResourceIdentifierProbe alloc] init] autorelease];
    probe.identifier = @"hard-link-id";

    XCTAssertNil(DIXFileIdentifierForVolumeProgress((NSURL *)probe, 1));
    XCTAssertEqual(probe.requestCount, (NSUInteger)0);

    XCTAssertEqualObjects(DIXFileIdentifierForVolumeProgress((NSURL *)probe, 2),
                          @"hard-link-id");
    XCTAssertEqual(probe.requestCount, (NSUInteger)1);
}

- (void)testDirectoryIsReportedBeforeItsDescendantIsProcessed
{
    [self createDirectory:@"slow-directory"];
    [self createZeroByteFile:@"slow-directory/descendant"];

    FSItemScannerDelegate *delegate = [[[FSItemScannerDelegate alloc] init] autorelease];
    [self scanWithDelegate:delegate usePhysicalSize:NO];

    NSString *directoryPath = [_fixturePath stringByAppendingPathComponent:@"slow-directory"];
    NSString *descendantPath = [directoryPath stringByAppendingPathComponent:@"descendant"];
    NSUInteger directoryProcessed = [[delegate events]
        indexOfObject:[NSString stringWithFormat:@"process:%@", directoryPath]];
    NSUInteger directoryEntered = [[delegate events]
        indexOfObject:[NSString stringWithFormat:@"enter:%@", directoryPath]];
    NSUInteger descendantProcessed = [[delegate events]
        indexOfObject:[NSString stringWithFormat:@"process:%@", descendantPath]];

    XCTAssertNotEqual(directoryProcessed, NSNotFound);
    XCTAssertNotEqual(directoryEntered, NSNotFound);
    XCTAssertNotEqual(descendantProcessed, NSNotFound);
    XCTAssertLessThan(directoryProcessed, directoryEntered);
    XCTAssertLessThan(directoryEntered, descendantProcessed);
}

- (void)testDirectoryExitIsReportedBeforeFollowingSiblingIsProcessed
{
    [self createDirectory:@"aaa-child"];
    [self createZeroByteFile:@"aaa-child/descendant"];
    [self createZeroByteFile:@"zzz-sibling"];

    FSItemScannerDelegate *delegate = [[[FSItemScannerDelegate alloc] init] autorelease];
    [self scanWithDelegate:delegate usePhysicalSize:NO];

    NSString *childPath = [_fixturePath stringByAppendingPathComponent:@"aaa-child"];
    NSString *siblingPath = [_fixturePath stringByAppendingPathComponent:@"zzz-sibling"];
    NSUInteger childExit = [[delegate events]
        indexOfObject:[NSString stringWithFormat:@"exit:%@", childPath]];
    NSUInteger siblingProcessed = [[delegate events]
        indexOfObject:[NSString stringWithFormat:@"process:%@", siblingPath]];

    XCTAssertNotEqual(childExit, NSNotFound);
    XCTAssertNotEqual(siblingProcessed, NSNotFound);
    XCTAssertLessThan(childExit, siblingProcessed);
}

- (void)testCancellationStopsTraversalAtPerItemCallback
{
    [self createDirectory:@"directory"];
    [self createZeroByteFile:@"directory/never-required"];

    FSItemScannerDelegate *delegate = [[[FSItemScannerDelegate alloc] init] autorelease];
    delegate.cancelOnFirstDiscoveredItem = YES;

    XCTAssertThrowsSpecificNamed([self scanWithDelegate:delegate usePhysicalSize:YES],
                                 NSException,
                                 FSItemLoadingCanceledException);

    NSPredicate *processedPredicate = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'process:'"];
    XCTAssertEqual([[[delegate events] filteredArrayUsingPredicate:processedPredicate] count],
                   (NSUInteger)1);
}

- (void)testPhysicalProgressAccountingDoesNotDependOnDisplaySizePreference
{
    [self createDirectory:@"nested"];
    [self createFile:@"nested/data" length:16384];

    FSItemScannerDelegate *logicalDelegate = [[[FSItemScannerDelegate alloc] init] autorelease];
    FSItemScannerDelegate *physicalDelegate = [[[FSItemScannerDelegate alloc] init] autorelease];
    logicalDelegate.progress = [[[VolumeScanProgress alloc] initWithTotalCapacity:@1000000
                                                               availableCapacity:@0] autorelease];
    physicalDelegate.progress = [[[VolumeScanProgress alloc] initWithTotalCapacity:@1000000
                                                                availableCapacity:@0] autorelease];
    logicalDelegate.collectVolumeProgressMetadata = YES;
    physicalDelegate.collectVolumeProgressMetadata = YES;
    [self scanWithDelegate:logicalDelegate usePhysicalSize:NO];
    [self scanWithDelegate:physicalDelegate usePhysicalSize:YES];

    NSPredicate *processedPredicate = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'process:'"];
    NSArray *logicalPaths = [[logicalDelegate events] filteredArrayUsingPredicate:processedPredicate];
    NSArray *physicalPaths = [[physicalDelegate events] filteredArrayUsingPredicate:processedPredicate];
    XCTAssertEqualObjects(logicalPaths, physicalPaths);
    XCTAssertGreaterThan(logicalDelegate.progress.scannedAllocatedBytes, (uint64_t)0);
    XCTAssertEqual(logicalDelegate.progress.scannedAllocatedBytes,
                   physicalDelegate.progress.scannedAllocatedBytes);
    XCTAssertEqualWithAccuracy(logicalDelegate.progress.progressFraction,
                               physicalDelegate.progress.progressFraction,
                               0.000001);
}

@end
