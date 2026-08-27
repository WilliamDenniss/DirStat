//
//  VolumeScanProgressTests.m
//  Disk Inventory XTests
//

#import <XCTest/XCTest.h>
#import <math.h>

#import "VolumeScanProgress.h"

static VolumeScanProgress *Progress(NSNumber *total, NSNumber *available)
{
    VolumeScanProgress *progress =
        [[VolumeScanProgress alloc] initWithTotalCapacity:total
                                       availableCapacity:available];
#if __has_feature(objc_arc)
    return progress;
#else
    return [progress autorelease];
#endif
}

@interface VolumeScanProgressTests : XCTestCase
@end

@implementation VolumeScanProgressTests

- (void)testCapacityValidation
{
    NSArray *invalidProgressValues = [NSArray arrayWithObjects:
        Progress(nil, @100),
        Progress(@100, nil),
        Progress(@100, @100),
        Progress(@99, @100),
        Progress(@-1, @-2),
        Progress(@100, @-1),
        nil];

    for (VolumeScanProgress *progress in invalidProgressValues)
    {
        XCTAssertFalse(progress.isDeterminate);
        XCTAssertEqual(progress.phase, VolumeScanProgressPhaseDisabled);
        XCTAssertEqual(progress.expectedUsedBytes, (uint64_t)0);
        XCTAssertEqual(progress.scannedAllocatedBytes, (uint64_t)0);
        XCTAssertEqualWithAccuracy(progress.progressFraction, 0.0, 0.000001);

        [progress recordAllocatedBytes:100 fileIdentifier:nil linkCount:1];
        [progress finishScanning];
        [progress beginClassificationWithItemCount:1];
        [progress recordClassifiedItem];
        [progress finish];

        XCTAssertEqualWithAccuracy(progress.progressFraction, 0.0, 0.000001);
    }

    VolumeScanProgress *valid = Progress(@1000, @200);
    XCTAssertTrue(valid.isDeterminate);
    XCTAssertEqual(valid.phase, VolumeScanProgressPhaseScanning);
    XCTAssertEqual(valid.expectedUsedBytes, (uint64_t)800);
}

- (void)testScanningMapsUsedBytesIntoFirstNinetyFivePercentMonotonically
{
    VolumeScanProgress *progress = Progress(@1200, @200);

    [progress recordAllocatedBytes:250 fileIdentifier:nil linkCount:1];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.2375, 0.000001);

    double previousFraction = progress.progressFraction;
    [progress recordAllocatedBytes:0 fileIdentifier:nil linkCount:1];
    XCTAssertGreaterThanOrEqual(progress.progressFraction, previousFraction);

    [progress recordAllocatedBytes:250 fileIdentifier:nil linkCount:1];
    XCTAssertGreaterThan(progress.progressFraction, previousFraction);
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.475, 0.000001);
}

- (void)testAllocatedByteAdditionSaturatesWithoutOverflow
{
    VolumeScanProgress *progress =
        Progress([NSNumber numberWithUnsignedLongLong:UINT64_MAX], @0);

    [progress recordAllocatedBytes:UINT64_MAX - 5 fileIdentifier:nil linkCount:1];
    [progress recordAllocatedBytes:10 fileIdentifier:nil linkCount:1];

    XCTAssertEqual(progress.scannedAllocatedBytes, (uint64_t)UINT64_MAX);
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.95, 0.000001);
}

- (void)testHardLinksWithIdentifiersAreCountedOnlyOnce
{
    VolumeScanProgress *progress = Progress(@1000, @0);

    [progress recordAllocatedBytes:100 fileIdentifier:@"same inode" linkCount:2];
    [progress recordAllocatedBytes:100 fileIdentifier:@"same inode" linkCount:2];
    XCTAssertEqual(progress.scannedAllocatedBytes, (uint64_t)100);

    [progress recordAllocatedBytes:100 fileIdentifier:nil linkCount:2];
    [progress recordAllocatedBytes:100 fileIdentifier:nil linkCount:2];
    [progress recordAllocatedBytes:100 fileIdentifier:@"same inode" linkCount:1];
    XCTAssertEqual(progress.scannedAllocatedBytes, (uint64_t)400);
}

- (void)testScanningOverrunIsClampedAtNinetyFivePercent
{
    VolumeScanProgress *progress = Progress(@100, @0);

    [progress recordAllocatedBytes:150 fileIdentifier:nil linkCount:1];

    XCTAssertEqual(progress.scannedAllocatedBytes, (uint64_t)150);
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.95, 0.000001);
}

- (void)testPhaseTransitionsAndSuccessfulCompletion
{
    VolumeScanProgress *progress = Progress(@1000, @0);
    [progress recordAllocatedBytes:100 fileIdentifier:nil linkCount:1];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.095, 0.000001);

    [progress finishScanning];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.95, 0.000001);

    [progress beginClassificationWithItemCount:4];
    XCTAssertEqual(progress.phase, VolumeScanProgressPhaseClassification);

    uint64_t scanningBytes = progress.scannedAllocatedBytes;
    [progress recordAllocatedBytes:100 fileIdentifier:nil linkCount:1];
    XCTAssertEqual(progress.scannedAllocatedBytes, scanningBytes);
    [progress recordClassifiedItem];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.9625, 0.000001);
    [progress recordClassifiedItem];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.975, 0.000001);
    [progress recordClassifiedItem];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.9875, 0.000001);
    [progress recordClassifiedItem];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.999, 0.000001);
    XCTAssertLessThan(progress.progressFraction, 1.0);

    [progress recordClassifiedItem];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.999, 0.000001);

    [progress finish];
    XCTAssertEqual(progress.phase, VolumeScanProgressPhaseFinished);
    XCTAssertEqualWithAccuracy(progress.progressFraction, 1.0, 0.000001);

    [progress recordClassifiedItem];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 1.0, 0.000001);
}

- (void)testEmptyClassificationWaitsForExplicitCompletion
{
    VolumeScanProgress *progress = Progress(@1000, @0);

    [progress beginClassificationWithItemCount:0];
    [progress recordClassifiedItem];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 0.95, 0.000001);

    [progress finish];
    XCTAssertEqualWithAccuracy(progress.progressFraction, 1.0, 0.000001);
}

- (void)testObservedProgressNeverDecreasesAcrossTheEntireLifecycle
{
    VolumeScanProgress *progress = Progress(@1000, @0);
    NSMutableArray *observedFractions = [NSMutableArray array];
    [observedFractions addObject:@(progress.progressFraction)];

    [progress recordAllocatedBytes:100 fileIdentifier:@"hard link" linkCount:2];
    [observedFractions addObject:@(progress.progressFraction)];
    [progress recordAllocatedBytes:0 fileIdentifier:nil linkCount:1];
    [observedFractions addObject:@(progress.progressFraction)];
    [progress recordAllocatedBytes:100 fileIdentifier:@"hard link" linkCount:2];
    [observedFractions addObject:@(progress.progressFraction)];
    [progress recordAllocatedBytes:400 fileIdentifier:nil linkCount:1];
    [observedFractions addObject:@(progress.progressFraction)];

    [progress finishScanning];
    [observedFractions addObject:@(progress.progressFraction)];
    [progress beginClassificationWithItemCount:3];
    [observedFractions addObject:@(progress.progressFraction)];
    for (NSUInteger item = 0; item < 3; item++)
    {
        [progress recordClassifiedItem];
        [observedFractions addObject:@(progress.progressFraction)];
    }
    [progress finish];
    [observedFractions addObject:@(progress.progressFraction)];

    for (NSUInteger index = 1; index < [observedFractions count]; index++)
    {
        double previous = [[observedFractions objectAtIndex:index - 1] doubleValue];
        double current = [[observedFractions objectAtIndex:index] doubleValue];
        XCTAssertGreaterThanOrEqual(current, previous,
                                    @"progress decreased at sample %lu: %.6f -> %.6f",
                                    (unsigned long)index, previous, current);
    }
}

- (void)testStalePartialSnapshotsCannotLowerQueuedOrObservedProgress
{
    // 0.2983 is representative of a point-in-time accessibility snapshot.
    // Later repaint candidates may be stale, but the shared UI/tracker reducer
    // must retain the greatest fraction observed for this load operation.
    const double candidates[] = {
        0.2983, 0.1200, NAN, -1.0, 0.2982, 0.6100, 0.4200, 1.0, 0.9500
    };
    const NSUInteger candidateCount =
        sizeof(candidates) / sizeof(candidates[0]);

    double observedFraction = 0.0;
    for (NSUInteger index = 0; index < candidateCount; index++)
    {
        double previousFraction = observedFraction;
        observedFraction = DIXMonotonicProgressFraction(observedFraction,
                                                         candidates[index]);
        XCTAssertGreaterThanOrEqual(observedFraction, previousFraction,
                                    @"snapshot %lu decreased progress: %.4f -> %.4f",
                                    (unsigned long)index,
                                    previousFraction, observedFraction);
    }

    XCTAssertEqualWithAccuracy(observedFraction, 1.0, 0.000001);
}

@end
