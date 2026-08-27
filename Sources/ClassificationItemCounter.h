//
//  ClassificationItemCounter.h
//  Disk Inventory X
//

#import <Foundation/Foundation.h>


// Counts the FSItems that the file-kind classification traversal will visit.
// The scanner's global item count already supplies the total without requiring
// a callback for every discovered item.  This object records only descendants
// that classification will skip when package contents are hidden.
@interface ClassificationItemCounter : NSObject
{
    BOOL _showPackageContents;
    NSUInteger _directoryDepth;
    NSUInteger _hiddenPackageDepth;
    NSUInteger _hiddenPackageStartItemCount;
    NSUInteger _excludedDescendantCount;
}

- (id)initWithShowPackageContents:(BOOL)showPackageContents;

- (NSUInteger)itemCountForDiscoveredItemCount:(NSUInteger)discoveredItemCount;

// Calls must be balanced and follow scanner callback order. Root packages do
// not hide their descendants because FileSystemDoc always treats zoomedItem as
// a classification node.
- (void)enterDirectoryIsPackage:(BOOL)isPackage
                         isRoot:(BOOL)isRoot
             discoveredItemCount:(NSUInteger)discoveredItemCount;
- (void)exitDirectoryIsPackage:(BOOL)isPackage
                        isRoot:(BOOL)isRoot
            discoveredItemCount:(NSUInteger)discoveredItemCount;

@end
