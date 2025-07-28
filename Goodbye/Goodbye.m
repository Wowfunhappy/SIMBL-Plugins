#import "ZKSwizzle.h"
#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

static BOOL origAppImplementsApplicationShouldTerminateAfterLastWindowClosed = NO;



@interface Goodbye : NSObject
@end

@interface ME_Goodbye_NSApplicationDelegate : NSObject
@end

@implementation ME_Goodbye_NSApplicationDelegate

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	
	BOOL origReturn = origAppImplementsApplicationShouldTerminateAfterLastWindowClosed && ZKOrig(BOOL);
	
	if (origReturn) {
		return true;
	} else {
		// When the application next resigns active status, terminate if there are still no windows.
		[[NSNotificationCenter defaultCenter] addObserver:self
												selector:@selector(applicationDidResignActive:)
												name:NSApplicationDidResignActiveNotification
												object:NSApp];
		return false;
	}
}

- (void)applicationDidResignActive:(NSNotification *)notification {
	[[NSNotificationCenter defaultCenter] removeObserver:self
											name:NSApplicationDidResignActiveNotification
											object:NSApp];
	
	// App is no longer frontmost, check if we should terminate
	NSArray *windows = [NSApp windows];
	for (NSWindow *aWindow in windows) {
		if ([aWindow isVisible] || [aWindow isMiniaturized]) {
			return;
		}
	}
	[NSApp terminate:self];
}

@end



@implementation Goodbye
+ (void)load {
	NSArray *globalBlacklist = [NSArray arrayWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"globalBlacklist" ofType:@"plist"]];
	
	if (
		![globalBlacklist containsObject: [[NSBundle mainBundle] bundleIdentifier]] &&
		![NSUserDefaults.standardUserDefaults boolForKey:@"GoodbyeBlacklist"] &&
		![[NSBundle mainBundle] objectForInfoDictionaryKey:@"LSUIElement"]
	) {
		Class delegateClass = [[NSApplication sharedApplication].delegate class];
		origAppImplementsApplicationShouldTerminateAfterLastWindowClosed = [
			delegateClass instancesRespondToSelector:@selector(applicationShouldTerminateAfterLastWindowClosed:)
		];
		_ZKSwizzle([ME_Goodbye_NSApplicationDelegate class], delegateClass);
	}
}
@end
