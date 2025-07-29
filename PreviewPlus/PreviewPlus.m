#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreServices/CoreServices.h>
#import "ZKSwizzle/ZKSwizzle.h"

@interface PQE_PVDocumentController : NSObject
- (NSString *)typeIdentifierOfFileURL:(NSURL *)url;
@end

@interface PQE_PVWindowController : NSObject
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
	
	NSMutableSet *extendedTypes = [NSMutableSet set];
	NSSet *originalSet = (NSSet *)originalResult;
	[extendedTypes addObjectsFromArray:[originalSet allObjects]];
	[extendedTypes addObjectsFromArray:[[self class] supportedTypes]];
	
	return [extendedTypes copy];
}

- (id)allReadableTypes {
	NSSet *originalTypes = ZKOrig(NSSet *);
	NSSet *customTypes = [NSSet setWithArray:[[self class] supportedTypes]];
	return [originalTypes setByAddingObjectsFromSet:customTypes];
}

- (BOOL)canOpenDocumentAtURL:(id)url typeID:(id *)typeID {
	// Get the type identifier for this URL
	NSString *typeIdentifier = [self typeIdentifierOfFileURL:url];
	
	// Set the type ID if requested
	if (typeID && typeIdentifier) {
		*typeID = typeIdentifier;
	}
	
	// Check if it's one of our supported types
	if (typeIdentifier && [[[self class] supportedTypes] containsObject:typeIdentifier]) {
		return YES;
	}
	
	// Otherwise let the original implementation handle it
	return ZKOrig(BOOL, url, typeID);
}

- (void)addDocumentAtURL:(NSURL *)url ofType:(NSString *)type toLoadGroup:(id)loadGroup {
	if ([[[self class] supportedTypes] containsObject:type]) {
		// The original implementation will use the _allReadableTypes ivar to determine if a type is supported.

		NSSet *originalIvar = ZKHookIvar(self, NSSet *, "_allReadableTypes");
		ZKHookIvar(self, NSSet *, "_allReadableTypes") = [NSSet setWithObject:type];
		ZKOrig(void, url, type, loadGroup);
		ZKHookIvar(self, NSSet *, "_allReadableTypes") = originalIvar;
		
	} else {
		// For native types, just pass through normally
		ZKOrig(void, url, type, loadGroup);
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
	
	// Map of file extensions to their UTIs
	NSDictionary *utiMappings = @{
		@"webp": @"org.webmproject.webp",
		@"avif": @"public.avif",
		@"heic": @"public.heic",
		@"heif": @"public.heif",
		@"md": @"net.daringfireball.markdown",
		@"markdown": @"net.daringfireball.markdown"
	};
	
	// Register Preview as the default handler for each UTI
	for (NSString *extension in utiMappings) {
		NSString *uti = utiMappings[extension];
		
		// Set Preview as the default handler for the UTI
		LSSetDefaultRoleHandlerForContentType((__bridge CFStringRef)uti,
											  kLSRolesViewer | kLSRolesEditor,
											  (__bridge CFStringRef)previewBundleID);
		
		// Also register by extension using dynamic UTI creation
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
	
	// Register UTI handlers to make Preview the default app for these file types
	registerUTIHandlers();
}

@end