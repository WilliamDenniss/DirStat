//
//  LoadingPanelUpdateStateTests.m
//  Disk Inventory XTests
//

#import <XCTest/XCTest.h>
#import <math.h>

#import "LoadingPanelUpdateState.h"


@interface LoadingPanelUpdateStateTests : XCTestCase
@end


@implementation LoadingPanelUpdateStateTests

- (LoadingPanelUpdateState*) updateState
{
	return [[[LoadingPanelUpdateState alloc]
		initWithMinimumUpdateInterval: 0.2] autorelease];
}

- (void) testDirectoryNotificationsKeepOnlyTheLatestValue
{
	LoadingPanelUpdateState *state = [self updateState];
	for ( unsigned itemCount = 1; itemCount <= 10000; itemCount++ )
	{
		NSString *path = [NSString stringWithFormat: @"/DIXProgressProof/%u", itemCount];
		[state queueDirectoryURL: [NSURL fileURLWithPath: path]
					 itemCount: itemCount];
	}

	XCTAssertTrue( [state hasPendingDirectoryUpdate] );
	XCTAssertEqualObjects( [[state pendingDirectoryURL] path],
					  @"/DIXProgressProof/10000" );
	XCTAssertEqual( [state pendingItemCount], (unsigned)10000 );

	[state noteFlushAtTime: 10.0];
	XCTAssertFalse( [state hasPendingDirectoryUpdate] );
	XCTAssertNil( [state pendingDirectoryURL] );
}

- (void) testFirstAndForcedFlushesAreImmediateWhileOrdinaryFlushesAreThrottled
{
	LoadingPanelUpdateState *state = [self updateState];

	XCTAssertTrue( [state shouldFlushAtTime: 10.0 force: NO] );
	[state noteFlushAtTime: 10.0];
	XCTAssertFalse( [state shouldFlushAtTime: 10.1 force: NO] );
	XCTAssertTrue( [state shouldFlushAtTime: 10.201 force: NO] );
	XCTAssertTrue( [state shouldFlushAtTime: 10.1 force: YES] );
}

- (void) testBackwardsTimestampDoesNotDisableThrottle
{
	LoadingPanelUpdateState *state = [self updateState];
	[state noteFlushAtTime: 20.0];

	XCTAssertFalse( [state shouldFlushAtTime: 19.0 force: NO] );
	XCTAssertTrue( [state shouldFlushAtTime: 19.0 force: YES] );
	[state noteFlushAtTime: 19.0];
	XCTAssertFalse( [state shouldFlushAtTime: 20.1 force: NO] );
	XCTAssertTrue( [state shouldFlushAtTime: 20.201 force: NO] );
}

- (void) testQueuedAndDisplayedProgressNeverDecrease
{
	LoadingPanelUpdateState *state = [self updateState];
	const double candidates[] = {
		0.2983, 0.1200, NAN, -1.0, 0.2982, 0.6100, 0.4200, 1.0, 0.9500
	};
	const NSUInteger candidateCount = sizeof( candidates ) / sizeof( candidates[0] );

	double previousPending = 0.0;
	double previousDisplayed = 0.0;
	for ( NSUInteger index = 0; index < candidateCount; index++ )
	{
		[state queueProgressFraction: candidates[index]];
		XCTAssertGreaterThanOrEqual( [state pendingProgressFraction], previousPending );
		[state noteFlushAtTime: (NSTimeInterval)index ];
		XCTAssertGreaterThanOrEqual( [state displayedProgressFraction], previousDisplayed );
		previousPending = [state pendingProgressFraction];
		previousDisplayed = [state displayedProgressFraction];
	}

	XCTAssertEqualWithAccuracy( [state pendingProgressFraction], 1.0, 0.000001 );
	XCTAssertEqualWithAccuracy( [state displayedProgressFraction], 1.0, 0.000001 );
}

- (void) testProgressRemainsPendingUntilAFlushIsRecorded
{
	LoadingPanelUpdateState *state = [self updateState];
	[state queueProgressFraction: 0.5];

	XCTAssertTrue( [state hasPendingProgressUpdate] );
	XCTAssertEqualWithAccuracy( [state displayedProgressFraction], 0.0, 0.000001 );
	[state noteFlushAtTime: 1.0];
	XCTAssertFalse( [state hasPendingProgressUpdate] );
	XCTAssertEqualWithAccuracy( [state displayedProgressFraction], 0.5, 0.000001 );
}

@end
