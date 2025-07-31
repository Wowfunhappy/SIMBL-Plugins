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

@interface PQE_PVPDFAnnotationImageStamp : NSObject
- (BOOL)isRotated90;
- (CGRect)bounds;
@end

@interface PQE_PVAnnotation : NSObject
@end


// Consolidated UTI configuration loaded from plist
static NSDictionary *getUTIConfiguration() {
	static NSDictionary *config = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSBundle *bundle = [NSBundle bundleForClass:[PQE_PVDocumentController class]];
		NSString *plistPath = [bundle pathForResource:@"UTIConfiguration" ofType:@"plist"];
		config = [NSDictionary dictionaryWithContentsOfFile:plistPath];
	});
	return config;
}

@implementation PQE_PVDocumentController

+ (NSArray *)supportedTypes {
	static NSArray *types = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSMutableSet *uniqueTypes = [NSMutableSet set];
		NSDictionary *config = getUTIConfiguration();
		for (NSArray *utis in [config allValues]) {
			[uniqueTypes addObjectsFromArray:utis];
		}
		types = [uniqueTypes allObjects];
	});
	return types;
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

// Helper function to create transform for EXIF orientation
// This corresponds to sub_10005ee44 in the assembly
static CGAffineTransform createTransformForEXIFOrientation(NSInteger orientation, CGFloat width, CGFloat height) {
	CGAffineTransform transform = CGAffineTransformIdentity;
	
	switch (orientation) {
		case 1: // Normal
			break;
			
		case 2: // Flip horizontal
			transform = CGAffineTransformMake(-1, 0, 0, 1, width, 0);
			break;
			
		case 3: // Rotate 180
			transform = CGAffineTransformMake(-1, 0, 0, -1, width, height);
			break;
			
		case 4: // Flip vertical
			transform = CGAffineTransformMake(1, 0, 0, -1, 0, height);
			break;
			
		case 5: // Rotate 90 CCW and flip vertical
			transform = CGAffineTransformMake(0, -1, -1, 0, height, width);
			break;
			
		case 6: // Rotate 90 CCW
			transform = CGAffineTransformMake(0, -1, 1, 0, 0, width);
			break;
			
		case 7: // Rotate 90 CW and flip vertical
			transform = CGAffineTransformMake(0, 1, 1, 0, 0, 0);
			break;
			
		case 8: // Rotate 90 CW
			transform = CGAffineTransformMake(0, 1, -1, 0, height, 0);
			break;
	}
	
	return transform;
}

@implementation PQE_PVPDFAnnotationImageStamp

- (double)scale {
	// Get the CGImage from the _image instance variable
	CGImageRef image = ZKHookIvar(self, CGImageRef, "_image");
	
	// If there's no image, return a default scale
	if (!image) {
		return 1.0;
	}
	
	// Get the actual pixel width of the image
	size_t imageWidth = CGImageGetWidth(image);
	
	// To prevent a division-by-zero error
	if (imageWidth == 0) {
		return 1.0;
	}
	
	// Get the bounds rect using the bounds method
	// We need to use objc_msgSend_stret for struct returns
	CGRect bounds;
	SEL boundsSelector = @selector(bounds);
	
	// Check if the image is displayed rotated by 90 degrees
	if ([self isRotated90]) {
		// If rotated, we need to get bounds and use the height
		((void(*)(CGRect*, id, SEL))objc_msgSend_stret)(&bounds, self, boundsSelector);
		return bounds.size.height / (double)imageWidth;
	} else {
		// If not rotated, we need to get bounds and use the width
		((void(*)(CGRect*, id, SEL))objc_msgSend_stret)(&bounds, self, boundsSelector);
		return bounds.size.width / (double)imageWidth;
	}
}

- (void)drawWithContext:(CGContextRef)context zoomFactor:(double)zoomFactor {
	// 1. Setup graphics state
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:context flipped:NO]];
	
	// 2. Get properties
	CGImageRef image = ZKHookIvar(self, CGImageRef, "_image");
	NSInteger exifOrientation = (NSInteger)ZKHookIvar(self, NSInteger, "_environmentEXIF");
	CGFloat scale = [self scale];
	CGFloat rawWidth = CGImageGetWidth(image);
	CGFloat rawHeight = CGImageGetHeight(image);
	
	// Check if shift key is held for non-proportional scaling
	BOOL shiftHeld = ([NSEvent modifierFlags] & NSShiftKeyMask) != 0;
	
	// 3. Calculate scaled dimensions (first time) to pass to helper
	CGFloat scaledWidthForTransform, scaledHeightForTransform;
	
	if (shiftHeld) {
		// Non-proportional scaling: fill the entire bounds
		CGRect bounds;
		SEL boundsSelector = @selector(bounds);
		((void(*)(CGRect*, id, SEL))objc_msgSend_stret)(&bounds, self, boundsSelector);
		
		// For transform, we need the final dimensions
		if ([self isRotated90]) {
			scaledWidthForTransform = bounds.size.height;
			scaledHeightForTransform = bounds.size.width;
		} else {
			scaledWidthForTransform = bounds.size.width;
			scaledHeightForTransform = bounds.size.height;
		}
	} else {
		// Proportional scaling (original behavior)
		scaledWidthForTransform = rawWidth * scale;
		scaledHeightForTransform = rawHeight * scale;
	}
	
	// 4. Create the orientation transform using the scaled dimensions
	CGAffineTransform transform = createTransformForEXIFOrientation(
		exifOrientation, scaledWidthForTransform, scaledHeightForTransform
	);
	
	// 5. Apply the transform
	CGContextConcatCTM(context, transform);
	
	// 6. Set quality
	CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
	
	// 7. Calculate the final destination rectangle
	CGFloat finalWidth, finalHeight;
	
	if (shiftHeld) {
		// Non-proportional: use the full bounds dimensions
		CGRect bounds;
		SEL boundsSelector = @selector(bounds);
		((void(*)(CGRect*, id, SEL))objc_msgSend_stret)(&bounds, self, boundsSelector);
		
		// The destination rect dimensions should match the bounds
		if ([self isRotated90]) {
			finalWidth = ceil(bounds.size.height);
			finalHeight = ceil(bounds.size.width);
		} else {
			finalWidth = ceil(bounds.size.width);
			finalHeight = ceil(bounds.size.height);
		}
	} else {
		// Proportional: use scaled dimensions (original behavior)
		finalWidth = ceil([self scale] * CGImageGetWidth(image));
		finalHeight = ceil([self scale] * CGImageGetHeight(image));
	}
	
	CGRect destinationRect = CGRectMake(0, 0, finalWidth, finalHeight);
	
	// 8. Draw the image
	CGContextDrawImage(context, destinationRect, image);
	
	// 9. Cleanup
	[NSGraphicsContext restoreGraphicsState];
}

@end

@implementation PQE_PVAnnotation

- (BOOL)requiresFixedAspectRatio {
	// Check if shift key is held
	BOOL shiftHeld = ([NSEvent modifierFlags] & NSShiftKeyMask) != 0;
	
	if (shiftHeld) {
		// Allow non-proportional scaling when shift is held
		return NO;
	} else {
		// Otherwise, use the original behavior
		return ZKOrig(BOOL);
	}
}

- (unsigned long long)resizeByMovingHandle:(unsigned long long)handle withModifiers:(unsigned long long)modifiers toPoint:(struct CGPoint)point inView:(id)view {
	if (modifiers & NSShiftKeyMask) {
		// Get the original implementation of requiresFixedAspectRatio
		// ZKSwizzle stores it with the swizzle class name prefix
		SEL originalSelector = @selector(_ZK_old_PQE_PVAnnotation_requiresFixedAspectRatio);
		BOOL (*originalImpl)(id, SEL) = (BOOL (*)(id, SEL))[self methodForSelector:originalSelector];
		BOOL originalRequiresFixedAspectRatio = originalImpl(self, originalSelector);
		
		// Only remove shift modifier if the original requires fixed aspect ratio
		// (i.e., for images that normally constrain, we want shift to unconstrain)
		if (originalRequiresFixedAspectRatio) {
			// Remove the shift modifier to allow non-proportional scaling
			modifiers &= ~NSShiftKeyMask;
		}
		// Otherwise, leave shift modifier alone so shapes can still be constrained
	}
	
	return ZKOrig(unsigned long long, handle, modifiers, point, view);
}

@end

static void registerUTIHandlers() {
	NSString *previewBundleID = @"com.apple.Preview";
	NSDictionary *config = getUTIConfiguration();
	
	// Register Preview as the default handler for each UTI
	for (NSString *extension in config) {
		NSArray *utis = config[extension];
		
		// Register each UTI for this extension
		for (NSString *uti in utis) {
			LSSetDefaultRoleHandlerForContentType(
				(__bridge CFStringRef)uti,
				kLSRolesViewer | kLSRolesEditor,
				(__bridge CFStringRef)previewBundleID
			);
		}
		
		// Also register by extension using dynamic UTI creation
		CFStringRef dynamicUTI = UTTypeCreatePreferredIdentifierForTag(
			kUTTagClassFilenameExtension, 
			(__bridge CFStringRef)extension, 
			kUTTypeData
		);
		if (dynamicUTI) {
			LSSetDefaultRoleHandlerForContentType(
				dynamicUTI,
				kLSRolesViewer | kLSRolesEditor,
				(__bridge CFStringRef)previewBundleID
			);
			CFRelease(dynamicUTI);
		}
	}
}

@implementation NSObject (PreviewPlus)

+ (void)load {
	//For supporting more file types
	ZKSwizzle(PQE_PVDocumentController, PVDocumentController);
	ZKSwizzle(PQE_PVWindowController, PVWindowController);
	
	//For allowing free resize when shift is held
	ZKSwizzle(PQE_PVPDFAnnotationImageStamp, PVPDFAnnotationImageStamp);
	ZKSwizzle(PQE_PVAnnotation, PVAnnotation);
	
	registerUTIHandlers();
}

@end