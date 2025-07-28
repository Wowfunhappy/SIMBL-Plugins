#import <AppKit/AppKit.h>
#import "ZKSwizzle.h"

@interface AppFolderFix_TBaseBrowserViewController : NSObject
@end

@implementation AppFolderFix_TBaseBrowserViewController

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	
	NSDragOperation originalMask = ZKOrig(NSDragOperation, session, context);
	
	NSArray *items = session.draggingPasteboard.pasteboardItems;
	BOOL hasApplicationsFile = NO;
	NSString *appPath = nil;
	
	for (NSPasteboardItem *item in items) {
		NSString *urlString = [item stringForType:@"public.file-url"];
		if (urlString) {
			NSURL *url = [NSURL URLWithString:urlString];
			NSString *path = [url path];
			if (path && [path hasPrefix:@"/Applications/"]) {
				hasApplicationsFile = YES;
				appPath = path;
				break;
			}
		}
	}
	
	if (!hasApplicationsFile) {
		return originalMask;
	}
	
	NSUInteger modifiers = [[NSApp currentEvent] modifierFlags];
	if ((modifiers & NSCommandKeyMask) && (modifiers & NSAlternateKeyMask)) {
		return originalMask;
	}
	
	return originalMask & ~NSDragOperationLink;
}

@end


@implementation NSObject (main)

+ (void)load {
	ZKSwizzle(AppFolderFix_TBaseBrowserViewController, TBaseBrowserViewController);
}

@end

int main() {}