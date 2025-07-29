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

- (id)readableQuickLookTypes {
    // Call the original implementation using ZKOrig
    NSSet *originalTypes = ZKOrig(id);
    
    NSLog(@"PreviewQuickLookExtender: Original readableQuickLookTypes count: %lu", (unsigned long)originalTypes.count);
    
    // Create a mutable copy and add our types
    NSMutableSet *extendedTypes = [originalTypes mutableCopy];
    [self addExtendedTypes:extendedTypes];
    
    NSLog(@"PreviewQuickLookExtender: Extended readableQuickLookTypes count: %lu", (unsigned long)extendedTypes.count);
    
    // Return immutable set
    return [extendedTypes copy];
}

- (id)allReadableTypes {
    // Call the original implementation using ZKOrig
    NSSet *originalTypes = ZKOrig(id);
    
    NSLog(@"PreviewQuickLookExtender: Original allReadableTypes count: %lu", (unsigned long)originalTypes.count);
    
    // Create a mutable copy and add our types
    NSMutableSet *extendedTypes = [originalTypes mutableCopy];
    [self addExtendedTypes:extendedTypes];
    
    NSLog(@"PreviewQuickLookExtender: Extended allReadableTypes count: %lu", (unsigned long)extendedTypes.count);
    
    // Also update the instance variable directly
    ZKHookIvar(self, NSSet *, "_allReadableTypes") = [extendedTypes copy];
    
    // Return the extended set
    return [extendedTypes copy];
}

- (BOOL)canOpenDocumentAtURL:(id)url typeID:(id *)typeID {
    NSString *typeIdentifier = [self typeIdentifierOfFileURL:url];
    NSLog(@"PreviewQuickLookExtender: canOpenDocument called for URL: %@, type: %@", url, typeIdentifier);
    
    // Set typeID if provided
    if (typeID) {
        *typeID = typeIdentifier;
    }
    
    // Check if it's one of our extended types
    NSArray *ourTypes = @[@"org.webmproject.webp", @"com.google.webp", @"public.webp",
                         @"public.avif", @"public.heic", @"public.heif",
                         @"net.daringfireball.markdown", @"public.markdown",
                         @"public.source-code", @"public.swift-source", 
                         @"public.python-script", @"public.ruby-script", 
                         @"public.shell-script"];
    
    if ([ourTypes containsObject:typeIdentifier]) {
        NSLog(@"PreviewQuickLookExtender: Overriding canOpen to YES for our type: %@", typeIdentifier);
        return YES;
    }
    
    // Call original implementation
    return ZKOrig(BOOL, url, typeID);
}

- (void)addDocumentAtURL:(NSURL *)url ofType:(NSString *)type toLoadGroup:(id)loadGroup {
    NSLog(@"PreviewQuickLookExtender: addDocumentAtURL called for URL: %@, type: %@", url, type);
    
    // Check if type is in allReadableTypes
    NSSet *allTypes = [self allReadableTypes];
    BOOL inSet = [allTypes containsObject:type];
    NSLog(@"PreviewQuickLookExtender: Type %@ in allReadableTypes: %@", type, inSet ? @"YES" : @"NO");
    
    // Call original implementation
    ZKOrig(void, url, type, loadGroup);
    
    NSLog(@"PreviewQuickLookExtender: addDocumentAtURL completed");
}

- (id)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    NSLog(@"PreviewQuickLookExtender: makeDocumentWithContentsOfURL called for URL: %@, type: %@", url, type);
    
    id result = ZKOrig(id, url, type, error);
    
    NSLog(@"PreviewQuickLookExtender: makeDocumentWithContentsOfURL returned: %@, error: %@", result, error ? *error : nil);
    
    return result;
}

- (void)addExtendedTypes:(NSMutableSet *)types {
    // Add WebP support
    [types addObject:@"org.webmproject.webp"];
    [types addObject:@"com.google.webp"];
    [types addObject:@"public.webp"];
    
    // Add other common formats
    [types addObject:@"public.avif"];
    [types addObject:@"public.heic"];
    [types addObject:@"public.heif"];
    
    // Add markdown
    [types addObject:@"net.daringfireball.markdown"];
    [types addObject:@"public.markdown"];
    
    // Add source code formats
    [types addObject:@"public.source-code"];
    [types addObject:@"public.swift-source"];
    [types addObject:@"public.python-script"];
    [types addObject:@"public.ruby-script"];
    [types addObject:@"public.shell-script"];
}

@end

@implementation PQE_PVWindowController

- (id)addFileURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    NSLog(@"PreviewQuickLookExtender: PVWindowController addFileURL called for: %@, type: %@", url, type);
    
    // Check if it's one of our extended types
    NSArray *ourTypes = @[@"org.webmproject.webp", @"com.google.webp", @"public.webp",
                         @"public.avif", @"public.heic", @"public.heif",
                         @"net.daringfireball.markdown", @"public.markdown",
                         @"public.source-code", @"public.swift-source", 
                         @"public.python-script", @"public.ruby-script", 
                         @"public.shell-script"];
    
    if ([ourTypes containsObject:type]) {
        NSLog(@"PreviewQuickLookExtender: Attempting to create QuickLook container for type: %@", type);
        
        // Try to create a QuickLook container directly
        Class pvQuickLookContainerClass = NSClassFromString(@"PVQuickLookContainer");
        if (pvQuickLookContainerClass) {
            // Use objc_msgSend to avoid ARC issues with init methods
            id container = objc_msgSend(pvQuickLookContainerClass, @selector(alloc));
            SEL initSel = @selector(initWithURL:);
            if ([container respondsToSelector:initSel]) {
                container = objc_msgSend(container, initSel, url);
                NSLog(@"PreviewQuickLookExtender: Created QuickLook container: %@", container);
                return container;
            }
        }
    }
    
    // Call original implementation
    id result = ZKOrig(id, url, type, error);
    NSLog(@"PreviewQuickLookExtender: Original addFileURL returned: %@, error: %@", result, error ? *error : nil);
    return result;
}

@end

@implementation NSObject (PreviewQuickLookExtender)

+ (void)load {
    NSLog(@"PreviewQuickLookExtender: Loading...");
    ZKSwizzle(PQE_PVDocumentController, PVDocumentController);
    ZKSwizzle(PQE_PVWindowController, PVWindowController);
}

@end