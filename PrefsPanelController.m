//
//  PrefsPanelController.m
//  Disk Inventory X
//
//  Created by Tjark Derlien on 28.11.04.
//  Copyright 2004 Tjark Derlien. All rights reserved.
//
// Copyright 2026 The DirStat Authors.
// Modified 2026-09-04.

#import "PrefsPanelController.h"
#import "OmniCompatibility.h"

@implementation PrefsPanelController

+ (PrefsPanelController*) sharedPreferenceController
{
	static PrefsPanelController *sharedPreferenceController = nil;
	
	if (sharedPreferenceController == nil)
		sharedPreferenceController = [[self alloc] init];

	return sharedPreferenceController;
}

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
	[super registerItemName: itemName bundle: bundle description: description];
}
@end
