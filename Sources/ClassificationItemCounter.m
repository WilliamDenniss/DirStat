//
//  ClassificationItemCounter.m
//  Disk Inventory X
//

#import "ClassificationItemCounter.h"


@implementation ClassificationItemCounter

- (id)initWithShowPackageContents:(BOOL)showPackageContents
{
    self = [super init];
    if ( self != nil )
        _showPackageContents = showPackageContents;
    return self;
}

- (NSUInteger)itemCountForDiscoveredItemCount:(NSUInteger)discoveredItemCount
{
    return discoveredItemCount >= _excludedDescendantCount
        ? discoveredItemCount - _excludedDescendantCount : 0;
}

- (void)enterDirectoryIsPackage:(BOOL)isPackage
                         isRoot:(BOOL)isRoot
             discoveredItemCount:(NSUInteger)discoveredItemCount
{
    NSAssert( _directoryDepth < NSUIntegerMax, @"classification directory depth overflow" );
    ++_directoryDepth;

    if ( !_showPackageContents && isPackage && !isRoot )
    {
        NSAssert( _hiddenPackageDepth < NSUIntegerMax, @"classification package depth overflow" );
        if ( _hiddenPackageDepth == 0 )
            _hiddenPackageStartItemCount = discoveredItemCount;
        ++_hiddenPackageDepth;
    }
}

- (void)exitDirectoryIsPackage:(BOOL)isPackage
                        isRoot:(BOOL)isRoot
            discoveredItemCount:(NSUInteger)discoveredItemCount
{
    NSAssert( _directoryDepth != 0, @"classification directory exit without matching entry" );

    if ( !_showPackageContents && isPackage && !isRoot )
    {
        NSAssert( _hiddenPackageDepth != 0, @"classification package exit without matching entry" );
        --_hiddenPackageDepth;
        if ( _hiddenPackageDepth == 0 )
        {
            NSAssert( discoveredItemCount >= _hiddenPackageStartItemCount,
                      @"classification item count moved backwards" );
            NSUInteger descendantCount = discoveredItemCount >= _hiddenPackageStartItemCount
                ? discoveredItemCount - _hiddenPackageStartItemCount : 0;
            if ( NSUIntegerMax - _excludedDescendantCount < descendantCount )
                _excludedDescendantCount = NSUIntegerMax;
            else
                _excludedDescendantCount += descendantCount;
        }
    }

    --_directoryDepth;
    NSAssert( _hiddenPackageDepth <= _directoryDepth,
              @"classification package state exceeds directory state" );
}

@end
