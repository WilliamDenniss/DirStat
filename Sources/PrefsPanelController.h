//
//  PrefsPanelController.h
//  Disk Inventory X
//
//  Created by Tjark Derlien on 28.11.04.
//  Copyright 2004 Tjark Derlien. All rights reserved.
//
// Copyright 2026 The DirStat Authors.
// Modified 2026-09-04.

#import <Cocoa/Cocoa.h>
#import "OmniCompatibility.h"


@interface PrefsPanelController : OAPreferenceController {

}

+ (PrefsPanelController*) sharedPreferenceController;

@end
