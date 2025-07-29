#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
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
	NSSet *originalTypes = ZKOrig(id);
	NSMutableSet *extendedTypes = [originalTypes mutableCopy];
	[self addExtendedTypes:extendedTypes];
	return [extendedTypes copy];
}

- (id)allReadableTypes {
	NSSet *originalTypes = ZKOrig(id);
	NSMutableSet *extendedTypes = [originalTypes mutableCopy];
	[self addExtendedTypes:extendedTypes];
	
	// Update the instance variable directly
	ZKHookIvar(self, NSSet *, "_allReadableTypes") = [extendedTypes copy];
	
	return [extendedTypes copy];
}

- (BOOL)canOpenDocumentAtURL:(id)url typeID:(id *)typeID {
	NSString *typeIdentifier = [self typeIdentifierOfFileURL:url];
	
	if (typeID) {
		*typeID = typeIdentifier;
	}
	
	if ([[[self class] supportedTypes] containsObject:typeIdentifier]) {
		return YES;
	}
	
	return ZKOrig(BOOL, url, typeID);
}

- (void)addDocumentAtURL:(NSURL *)url ofType:(NSString *)type toLoadGroup:(id)loadGroup {
	// Ensure allReadableTypes is updated by calling the getter
	NSSet *allTypes = [self allReadableTypes];
	[allTypes containsObject:type]; // Keep the reference alive
	
	ZKOrig(void, url, type, loadGroup);
}


- (void)addExtendedTypes:(NSMutableSet *)types {
	[types addObjectsFromArray:[[self class] supportedTypes]];
}

@end

@implementation PQE_PVWindowController

- (id)addFileURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
	if ([[PQE_PVDocumentController supportedTypes] containsObject:type]) {
		Class pvQuickLookContainerClass = NSClassFromString(@"PVQuickLookContainer");
		if (pvQuickLookContainerClass) {
			id container = objc_msgSend(pvQuickLookContainerClass, @selector(alloc));
			SEL initSel = @selector(initWithURL:);
			if ([container respondsToSelector:initSel]) {
				container = objc_msgSend(container, initSel, url);
				return container;
			}
		}
	}
	
	return ZKOrig(id, url, type, error);
}

@end

@implementation NSObject (PreviewPlus)

+ (void)load {
	ZKSwizzle(PQE_PVDocumentController, PVDocumentController);
	ZKSwizzle(PQE_PVWindowController, PVWindowController);
}

@end