//
//  mySIMBLFixes.m
//  mySIMBLFixes
//
//  Created by Wolfgang Baird on 3/30/17.
//  Updated with additional fixes in 2022/2025 by Wowfunhappy with assistance from krackers.
//

#import "ZKSwizzle.h"
#import <AppKit/AppKit.h>



@interface mySIMBLFixes : NSObject
@end


@implementation mySIMBLFixes

+ (instancetype)sharedInstance
{
	static mySIMBLFixes *plugin = nil;
	@synchronized(self)
	{
		if (!plugin)
			plugin = [[self alloc] init];
	}
	return plugin;
}

+ (void)load
{
	//Work around side effects of injecting SIMBL into certain applications.
	
	//Make Terminal open a new window when launched.
	if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.Terminal"])
	{
		[[mySIMBLFixes sharedInstance] performSelector:@selector(addTerminalWindowIfNeeded) withObject:nil afterDelay:0.01];
	}
	
	//Make Archive Utility close when finished
	if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.archiveutility"])
		ZKSwizzle(mySIMBLFixes_BAHController, BAHController);
	
	//Make proxy icons in sandboxed apps show path to unsandboxed file.
	ZKSwizzle(mySIMBLFixes_NSApplication, NSApplication);
}

- (void)addTerminalWindowIfNeeded {
	for (NSObject *o in [NSApp windows])
		if ([[o className] isEqualToString:@"TTWindow"])
			return;
	
	//No existing Terminal windows found!
	
	CGEventFlags flags = kCGEventFlagMaskCommand;
	CGEventRef ev;
	CGEventSourceRef source = CGEventSourceCreate (kCGEventSourceStateCombinedSessionState);
	
	//press down
	ev = CGEventCreateKeyboardEvent (source, (CGKeyCode)0x2D, true);
	CGEventSetFlags(ev,flags | CGEventGetFlags(ev)); //combine flags
	CGEventPost(kCGHIDEventTap,ev);
	CFRelease(ev);
	
	//press up
	ev = CGEventCreateKeyboardEvent (source, (CGKeyCode)0x2D, false);
	CGEventSetFlags(ev,flags | CGEventGetFlags(ev)); //combine flags
	CGEventPost(kCGHIDEventTap,ev);
	CFRelease(ev);
	
	CFRelease(source);
}

@end




@interface mySIMBLFixes_BAHController : NSObject
@end

@implementation mySIMBLFixes_BAHController

// Why is this broken by mySIMBL loading?
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

@end




@interface mySIMBLFixes_NSApplication : NSApplication
@end

@implementation mySIMBLFixes_NSApplication

// This is an Apple bug, triggered when any Apple Event is sent to a sandboxed document-based app.
- (short)_handleAEOpenDocumentsForURLs:(id)URLs {
	for (int i = 0; i < [URLs count]; i++) {
		URLs[i] = [URLs[i] URLByResolvingSymlinksInPath];
	}
	return ZKOrig(short, URLs);
}

@end
