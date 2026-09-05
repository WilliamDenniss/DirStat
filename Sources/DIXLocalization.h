// Copyright 2026 The DirStat Authors.

#import <Foundation/Foundation.h>

// Replaces CocoaTechStrings lookups with the app's FileOperations table.
#define DIXLocalizedString(key) NSLocalizedStringFromTable((key), @"FileOperations", @"")
