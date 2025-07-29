#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreServices/CoreServices.h>
#import "ZKSwizzle/ZKSwizzle.h"

@interface PQE_PVDocumentController : NSObject
- (NSString *)typeIdentifierOfFileURL:(NSURL *)url;
- (id)documentForURL:(NSURL *)url;
- (id)frontmostWindowController;
@end

@interface PQE_PVWindowController : NSObject
@end

@interface NSObject (PreviewPlusForwardDeclarations)
- (BOOL)isCanceled;
- (id)existingWindowControllers;
- (NSString *)spotlightSearchString;
- (NSInteger)openingMode;
- (id)windowController;
- (void)setWindowController:(id)controller;
- (id)containersOpened;
- (BOOL)displayWindow;
- (id)addURLErrors;
- (id)parentWindowController;
- (BOOL)isWindowLoaded;
- (id)window;
- (void)setCurrentMediaContainer:(id)container;
- (void)showWindow:(id)sender;
- (void)searchEvent:(NSString *)searchString;
- (void)willBeginAddingFiles;
- (void)didEndAddingFiles;
- (id)metaUndoManager;
- (id)addFileURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error;
- (id)mediaContainers;
- (void)showWindowOnMainThread;
- (NSInteger)addedFileCount;
- (void)disableUndoRegistration;
- (void)enableUndoRegistration;
+ (void)addFilePresenter:(id)presenter;
@end

@implementation PQE_PVDocumentController

+ (NSArray *)supportedTypes {
	return @[
		@"org.webmproject.webp", @"com.google.webp", @"public.webp",
		@"public.avif", @"public.heic", @"public.heif",
		@"net.daringfireball.markdown", @"public.markdown"
	];
}

- (id)readableQuickLookTypes {
	id originalResult = ZKOrig(id);
	if (![originalResult isKindOfClass:[NSSet class]]) {
		return originalResult;
	}
	
	NSMutableSet *extendedTypes = [NSMutableSet setWithArray:[(NSSet *)originalResult allObjects]];
	[extendedTypes addObjectsFromArray:[[self class] supportedTypes]];
	return [extendedTypes copy];
}

- (id)allReadableTypes {
	NSSet *originalTypes = ZKOrig(NSSet *);
	NSSet *customTypes = [NSSet setWithArray:[[self class] supportedTypes]];
	return [originalTypes setByAddingObjectsFromSet:customTypes];
}

- (BOOL)canOpenDocumentAtURL:(id)url typeID:(id *)typeID {
	NSString *typeIdentifier = [self typeIdentifierOfFileURL:url];
	if (typeID && typeIdentifier) {
		*typeID = typeIdentifier;
	}
	
	if (typeIdentifier && [[[self class] supportedTypes] containsObject:typeIdentifier]) {
		return YES;
	}
	
	return ZKOrig(BOOL, url, typeID);
}

- (void)addDocumentAtURL:(NSURL *)url ofType:(NSString *)type toLoadGroup:(id)loadGroup {
	/* Unfortunately, we have to replace this entire method.
	The original implementation reads the _allReadableTypes instance variable to check if a type is supported.
	Attempting to hook and modify this ivar led to memory corruption and crashes. */
	
	if ([loadGroup isCanceled]) {
		return;
	}
	
	// Handle existing document
	id existingDocument = [self documentForURL:url];
	if (existingDocument) {
		id windowController = [existingDocument parentWindowController];
		if (windowController && ![[loadGroup existingWindowControllers] containsObject:windowController]) {
			[[loadGroup existingWindowControllers] addObject:windowController];
			if ([windowController isWindowLoaded] && [[windowController window] isVisible]) {
				[windowController setCurrentMediaContainer:existingDocument];
				[windowController showWindow:existingDocument];
				if ([loadGroup spotlightSearchString]) {
					[windowController searchEvent:[loadGroup spotlightSearchString]];
				}
			}
		}
		return;
	}
	
	// Check if type is supported
	if (![[[self class] supportedTypes] containsObject:type]) {
		NSSet *allTypes = [self allReadableTypes];
		if (![allTypes containsObject:type]) {
			return;
		}
	}
	
	// Get or create window controller
	id windowController = [loadGroup windowController];
	BOOL shouldShowWindow = NO;
	
	if ([loadGroup openingMode] == 2 && !windowController) {
		Class pvWindowControllerClass = NSClassFromString(@"PVWindowController");
		if (pvWindowControllerClass) {
			windowController = [[pvWindowControllerClass alloc] initWithWindowNibName:@"PVDocument"];
			shouldShowWindow = YES;
		} else {
			windowController = [self frontmostWindowController];
			[loadGroup setWindowController:windowController];
		}
		[windowController willBeginAddingFiles];
	}
	
	// Add the file
	[[windowController metaUndoManager] disableUndoRegistration];
	NSError *error = nil;
	id container = [windowController addFileURL:url ofType:type error:&error];
	[[windowController metaUndoManager] enableUndoRegistration];
	
	if (container) {
		[[loadGroup containersOpened] addObject:container];
		[NSFileCoordinator addFilePresenter:container];
		
		if (shouldShowWindow) {
			[windowController didEndAddingFiles];
			if ([[windowController mediaContainers] count] > 0 && [loadGroup displayWindow]) {
				[windowController showWindowOnMainThread];
			}
		} else if ([windowController addedFileCount] >= 11 && 
				   [loadGroup displayWindow] && 
				   ![[windowController window] isVisible]) {
			[windowController showWindowOnMainThread];
		}
		
		if ([loadGroup spotlightSearchString]) {
			[windowController searchEvent:[loadGroup spotlightSearchString]];
		}
	} else if (error) {
		[[loadGroup addURLErrors] addObject:error];
	}
}

@end

@implementation PQE_PVWindowController

- (id)addFileURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
	if ([[PQE_PVDocumentController supportedTypes] containsObject:type]) {
		Class pvQuickLookContainerClass = NSClassFromString(@"PVQuickLookContainer");
		if (pvQuickLookContainerClass) {
			id container = objc_msgSend(pvQuickLookContainerClass, @selector(alloc));
			if ([container respondsToSelector:@selector(initWithURL:)]) {
				return objc_msgSend(container, @selector(initWithURL:), url);
			}
		}
	}
	
	return ZKOrig(id, url, type, error);
}

@end

static void registerUTIHandlers() {
	NSString *previewBundleID = @"com.apple.Preview";
	NSDictionary *utiMappings = @{
		@"webp": @"org.webmproject.webp",
		@"avif": @"public.avif",
		@"heic": @"public.heic",
		@"heif": @"public.heif",
		@"md": @"net.daringfireball.markdown",
		@"markdown": @"net.daringfireball.markdown"
	};
	
	for (NSString *extension in utiMappings) {
		NSString *uti = utiMappings[extension];
		LSSetDefaultRoleHandlerForContentType((__bridge CFStringRef)uti,
											  kLSRolesViewer | kLSRolesEditor,
											  (__bridge CFStringRef)previewBundleID);
		
		CFStringRef dynamicUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, 
																	   (__bridge CFStringRef)extension, 
																	   kUTTypeData);
		if (dynamicUTI) {
			LSSetDefaultRoleHandlerForContentType(dynamicUTI,
												  kLSRolesViewer | kLSRolesEditor,
												  (__bridge CFStringRef)previewBundleID);
			CFRelease(dynamicUTI);
		}
	}
}

@implementation NSObject (PreviewPlus)

+ (void)load {
	ZKSwizzle(PQE_PVDocumentController, PVDocumentController);
	ZKSwizzle(PQE_PVWindowController, PVWindowController);
	registerUTIHandlers();
}

@end