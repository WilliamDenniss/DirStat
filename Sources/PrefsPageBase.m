//
//  PrefsPageBase.m
//  Disk Inventory X
//
//  Created by Tjark Derlien on 29.11.04.
//  Copyright 2004 Tjark Derlien. All rights reserved.
//
// Copyright 2026 The DirStat Authors.
// Modified 2026-09-04.

#import "PrefsPageBase.h"
#import "OmniCompatibility.h"

@implementation PrefsPageBase

- (void)restoreDefaultsNoPrompt;
{
    [super restoreDefaultsNoPrompt];
}

- (BOOL)haveAnyDefaultsChanged;
{
    return [super haveAnyDefaultsChanged];
}

@end
