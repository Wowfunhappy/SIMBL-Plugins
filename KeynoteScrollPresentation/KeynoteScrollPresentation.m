#import <AppKit/AppKit.h>
#import "ZKSwizzle.h"

static void LogMethod(NSString *className, NSString *method) {
	NSLog(@"KeynoteScrollPresentation: %@.%@ called", className, method);
}

@interface NSObject (KeynotePrivateMethods)
- (id)movieRendererAtPoint:(NSPoint)point;
- (BOOL)p_mouseEventIsInHyperlink:(NSEvent *)event hitObject:(id *)hitObject hitRep:(id *)hitRep hitInfo:(id *)hitInfo;
@end

@interface KeynoteScrollPresentation_KNMacAnimatedPlaybackContainerView : NSView @end
@implementation KeynoteScrollPresentation_KNMacAnimatedPlaybackContainerView

static BOOL wasOverHyperlink = NO;
static BOOL preventNavigation = YES;
static NSTimeInterval lastScrollTime = 0;
static const NSTimeInterval scrollDebounceInterval = 0.01; // debounce

-(void)mouseMoved:(NSEvent *)event {
	// Prevent cursor changes that interfere with the WacomOverlay app I use for teaching.
	
	// Check if mouse is over a hyperlink
	SEL hyperlinkSel = NSSelectorFromString(@"p_mouseEventIsInHyperlink:hitObject:hitRep:hitInfo:");
	BOOL overHyperlink = [self p_mouseEventIsInHyperlink:event hitObject:nil hitRep:nil hitInfo:nil];
	if (overHyperlink) {
		// Over a hyperlink
		wasOverHyperlink = YES;
		ZKOrig(void, event);
		return;
	} else if (wasOverHyperlink) {
		// Just left a hyperlink - call original once to reset cursor
		wasOverHyperlink = NO;
		ZKOrig(void, event);
		return;
	}
	
	// Check if mouse is over a movie
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"KNShowMovieHUDWhenMouseOver"]) {
		id playbackController = object_getIvar(self, class_getInstanceVariable([self class], "mPlaybackController"));
		NSPoint mouseLocation = [self convertPoint:[event locationInWindow] fromView:nil];
		if ([playbackController movieRendererAtPoint:mouseLocation]) {
			ZKOrig(void, event);
			return;
		}
	}
		
	// Do nothing
}

// Prevent clicking to go to the next slide (unless it's from us)
- (void)mouseDown:(NSEvent *)theEvent {
	if (! preventNavigation) {
		preventNavigation = YES;
		ZKOrig(void, theEvent);
	}
	return;
}

- (void)rightMouseDown:(NSEvent *)theEvent {
	if (! preventNavigation) {
		preventNavigation = YES;
		ZKOrig(void, theEvent);
	}
	return;
}

// Add scroll wheel support for slide navigation. (Only discrete/notched scroll wheels)
- (void)scrollWheel:(NSEvent *)event {
	BOOL isDiscrete = ![event hasPreciseScrollingDeltas];
	if (!isDiscrete) {
		return;
	}
	
	CGFloat deltaY = [event scrollingDeltaY];
	if (fabs(deltaY) < 0.1) {
		return;
	}
	
	// Ignore scroll during slide transitions
	id playbackController = object_getIvar(self, class_getInstanceVariable([self class], "mPlaybackController"));
	if ([playbackController isNonMovieAnimationActive]) {
		return;
	}
	
	NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
	if (currentTime - lastScrollTime < scrollDebounceInterval) {
		return;
	}
	
	// Update last scroll time
	lastScrollTime = currentTime;
	
	if (deltaY > 0) {
		preventNavigation = NO;
		[self rightMouseDown:nil];
		
	} else if (deltaY < 0) {
		preventNavigation = NO;
		[self mouseDown:nil];
	}
}

@end


@implementation NSObject (main)

+ (void)load {
	ZKSwizzle(KeynoteScrollPresentation_KNMacAnimatedPlaybackContainerView, KNMacAnimatedPlaybackContainerView);
}

@end