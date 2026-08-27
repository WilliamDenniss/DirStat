//
//  ClassificationItemCounterTests.m
//  Disk Inventory XTests
//

#import <XCTest/XCTest.h>

#import "ClassificationItemCounter.h"


@interface ClassificationItemCounterTests : XCTestCase
@end


@implementation ClassificationItemCounterTests

- (void)testRootIsIncludedBeforeAnyDiscovery
{
    ClassificationItemCounter *counter = [[ClassificationItemCounter alloc]
                                           initWithShowPackageContents:NO];

    XCTAssertEqual([counter itemCountForDiscoveredItemCount:1], (NSUInteger)1);

    [counter release];
}

- (void)testVisibleTreeCountsEveryDiscoveredItem
{
    ClassificationItemCounter *counter = [[ClassificationItemCounter alloc]
                                           initWithShowPackageContents:YES];

    [counter enterDirectoryIsPackage:NO isRoot:YES discoveredItemCount:1];
    [counter enterDirectoryIsPackage:YES isRoot:NO discoveredItemCount:4];
    [counter exitDirectoryIsPackage:YES isRoot:NO discoveredItemCount:6];
    [counter exitDirectoryIsPackage:NO isRoot:YES discoveredItemCount:6];

    XCTAssertEqual([counter itemCountForDiscoveredItemCount:6], (NSUInteger)6);

    [counter release];
}

- (void)testHiddenPackageCountsPackageButNotItsDescendants
{
    ClassificationItemCounter *counter = [[ClassificationItemCounter alloc]
                                           initWithShowPackageContents:NO];

    [counter enterDirectoryIsPackage:NO isRoot:YES discoveredItemCount:1];
    // The package itself has already raised the total to two before entry.
    [counter enterDirectoryIsPackage:YES isRoot:NO discoveredItemCount:2];
    [counter enterDirectoryIsPackage:NO isRoot:NO discoveredItemCount:5];
    [counter exitDirectoryIsPackage:NO isRoot:NO discoveredItemCount:6];
    [counter exitDirectoryIsPackage:YES isRoot:NO discoveredItemCount:6];
    [counter exitDirectoryIsPackage:NO isRoot:YES discoveredItemCount:7];

    XCTAssertEqual([counter itemCountForDiscoveredItemCount:7], (NSUInteger)3);

    [counter release];
}

- (void)testNestedHiddenPackagesKeepSuppressionUntilOuterPackageExit
{
    ClassificationItemCounter *counter = [[ClassificationItemCounter alloc]
                                           initWithShowPackageContents:NO];

    [counter enterDirectoryIsPackage:NO isRoot:YES discoveredItemCount:1];
    [counter enterDirectoryIsPackage:YES isRoot:NO discoveredItemCount:2];
    [counter enterDirectoryIsPackage:YES isRoot:NO discoveredItemCount:3];
    [counter exitDirectoryIsPackage:YES isRoot:NO discoveredItemCount:3];
    [counter exitDirectoryIsPackage:YES isRoot:NO discoveredItemCount:4];
    [counter exitDirectoryIsPackage:NO isRoot:YES discoveredItemCount:5];

    XCTAssertEqual([counter itemCountForDiscoveredItemCount:5], (NSUInteger)3);

    [counter release];
}

- (void)testRootPackageNeverSuppressesItsDescendants
{
    ClassificationItemCounter *counter = [[ClassificationItemCounter alloc]
                                           initWithShowPackageContents:NO];

    [counter enterDirectoryIsPackage:YES isRoot:YES discoveredItemCount:1];
    [counter exitDirectoryIsPackage:YES isRoot:YES discoveredItemCount:3];

    XCTAssertEqual([counter itemCountForDiscoveredItemCount:3], (NSUInteger)3);

    [counter release];
}

- (void)testSeparateHiddenPackagesAccumulateExcludedDescendants
{
    ClassificationItemCounter *counter = [[ClassificationItemCounter alloc]
                                           initWithShowPackageContents:NO];

    [counter enterDirectoryIsPackage:NO isRoot:YES discoveredItemCount:1];
    [counter enterDirectoryIsPackage:YES isRoot:NO discoveredItemCount:2];
    [counter exitDirectoryIsPackage:YES isRoot:NO discoveredItemCount:5];
    [counter enterDirectoryIsPackage:YES isRoot:NO discoveredItemCount:6];
    [counter exitDirectoryIsPackage:YES isRoot:NO discoveredItemCount:8];
    [counter exitDirectoryIsPackage:NO isRoot:YES discoveredItemCount:9];

    XCTAssertEqual([counter itemCountForDiscoveredItemCount:9], (NSUInteger)4);

    [counter release];
}

- (void)testMaximumDiscoveredCountDoesNotOverflowExclusionAccounting
{
    ClassificationItemCounter *counter = [[ClassificationItemCounter alloc]
                                           initWithShowPackageContents:NO];

    [counter enterDirectoryIsPackage:NO isRoot:YES discoveredItemCount:1];
    [counter enterDirectoryIsPackage:YES isRoot:NO discoveredItemCount:2];
    [counter exitDirectoryIsPackage:YES isRoot:NO discoveredItemCount:NSUIntegerMax];
    [counter exitDirectoryIsPackage:NO isRoot:YES discoveredItemCount:NSUIntegerMax];

    XCTAssertEqual([counter itemCountForDiscoveredItemCount:NSUIntegerMax], (NSUInteger)2);

    [counter release];
}

@end
