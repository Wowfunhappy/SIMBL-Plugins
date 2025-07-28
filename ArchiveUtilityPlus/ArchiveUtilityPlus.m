#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreServices/CoreServices.h>
#import "ZKSwizzle.h"

static NSMutableDictionary *activeTasks = nil;

static Class createDecompressorClass(const char *className, IMP decompressImp) {
	Class BAHDecompressor = NSClassFromString(@"BAHDecompressor");
	Class newClass = objc_allocateClassPair(BAHDecompressor, className, 0);
	if (!newClass) {
		return NSClassFromString([NSString stringWithUTF8String:className]);
	}
	
	Method method = class_getInstanceMethod(BAHDecompressor, @selector(_decompressPerformCopy));
	class_addMethod(newClass, @selector(_decompressPerformCopy), decompressImp, method_getTypeEncoding(method));
	
	objc_registerClassPair(newClass);
	return newClass;
}

static NSString *get7zPath() {
	NSString *bundlePath = [[NSBundle bundleWithIdentifier:@"com.archiveutility.plus"] bundlePath];
	return [bundlePath stringByAppendingPathComponent:@"Contents/Resources/7zz"];
}

static BOOL extractArchive(id self, SEL _cmd) {
	if (!((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(_decompressSetupTarget))) {
		return NO;
	}
	
	NSString *sourcePath = [self performSelector:@selector(copySource)];
	NSString *targetPath = [self performSelector:@selector(copyTarget)];
	NSString *finalDest = [self performSelector:@selector(finalDestDirectory)];
	
	// Set indeterminate progress bar mode for non-native formats
	Ivar determinateIvar = class_getInstanceVariable([self class], "_allowDeterminateProgressBar");
	if (determinateIvar) {
		*(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(determinateIvar)) = NO;
	}
	
	[self performSelector:@selector(_enableProgressBar:) withObject:(id)YES];
	[self performSelector:@selector(_enableProgressCancel:) withObject:(id)YES];
	
	NSString *sevenZPath = get7zPath();
	NSString *password = nil;
	BOOL firstAttempt = YES;
	
	while (YES) {
		if (!firstAttempt) {
			NSMutableString *passwordString = [NSMutableString string];
			NSDictionary *passwordDict = @{@"PWSheetFileNamePrompt": sourcePath,
										   @"PWSheetReturnedPW": passwordString};
			
			[self performSelector:@selector(askForArchivePassword:) withObject:passwordDict];
			
			Ivar progressViewIvar = class_getInstanceVariable([self class], "_progressView");
			if (progressViewIvar) {
				id progressView = object_getIvar(self, progressViewIvar);
				if ([progressView respondsToSelector:@selector(userDidCancelPasswordSheet)] &&
					((BOOL (*)(id, SEL))objc_msgSend)(progressView, @selector(userDidCancelPasswordSheet))) {
					[self performSelector:@selector(_enableProgressBar:) withObject:(id)NO];
					return NO;
				}
			}
			
			password = [NSString stringWithString:passwordString];
		}
		
		NSTask *task = [[NSTask alloc] init];
		[task setLaunchPath:sevenZPath];
		
		NSString *outputArg = [NSString stringWithFormat:@"-o%@", targetPath];
		NSMutableArray *args = [NSMutableArray arrayWithObjects:@"x", @"-y", outputArg, nil];
		
		[args addObject:(password && password.length) ? [NSString stringWithFormat:@"-p%@", password] : @"-p"];
		[args addObject:sourcePath];
		[task setArguments:args];
		
		[task setStandardOutput:[NSPipe pipe]];
		[task setStandardError:[NSPipe pipe]];
		
		if (!activeTasks) activeTasks = [[NSMutableDictionary alloc] init];
		NSValue *selfPointer = [NSValue valueWithPointer:(__bridge void *)self];
		[activeTasks setObject:task forKey:selfPointer];
		
		NSPipe *outputPipe = [task standardOutput];
		NSPipe *errorPipe = [task standardError];
		
		[task launch];
		
		while ([task isRunning]) {
			Ivar canceledIvar = class_getInstanceVariable([self class], "_progressCanceled");
			if (canceledIvar && *(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(canceledIvar))) {
				[task terminate];
				[activeTasks removeObjectForKey:selfPointer];
				[self performSelector:@selector(_enableProgressBar:) withObject:(id)NO];
				return NO;
			}
			[NSThread sleepForTimeInterval:0.1];
		}
		
		[task waitUntilExit];
		[activeTasks removeObjectForKey:selfPointer];
		
		NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
		NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
		NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
		NSString *errorString = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
		
		BOOL noFilesExtracted = [outputString rangeOfString:@"No files to process"].location != NSNotFound;
		BOOL isPasswordError = noFilesExtracted ||
							   (errorString && ([errorString rangeOfString:@"Wrong password"].location != NSNotFound ||
												[errorString rangeOfString:@"Data Error in encrypted file"].location != NSNotFound ||
												[errorString rangeOfString:@"Can not open encrypted archive"].location != NSNotFound));
		
		if ([task terminationStatus] != 0 || noFilesExtracted) {
			if (isPasswordError) {
				firstAttempt = NO;
				continue;
			}
			[self performSelector:@selector(_enableProgressBar:) withObject:(id)NO];
			return NO;
		}
		
		break;
	}
	
	[self performSelector:@selector(_enableProgressBar:) withObject:(id)NO];
	
	NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:targetPath error:nil];
	NSString *finalTargetPath = ([contents count] == 1) ?
		[finalDest stringByAppendingPathComponent:[contents objectAtIndex:0]] :
		[finalDest stringByAppendingPathComponent:[[sourcePath lastPathComponent] stringByDeletingPathExtension]];
	
	[self performSelector:@selector(setFinalTargetPath:) withObject:finalTargetPath];
	return YES;
}

static NSDictionary *readArchiveUtilityPreferences() {
	NSMutableDictionary *options = [NSMutableDictionary dictionary];
	CFStringRef appID = CFSTR("com.apple.archiveutility");
	
	for (NSString *key in @[@"dewarchive-move-after", @"dearchive-into", @"dearchive-reveal-after", 
							@"openIfSingleItem", @"dearchive-move-intermediate-after", @"dearchive-recursively"]) {
		CFPropertyListRef value = CFPreferencesCopyAppValue((CFStringRef)key, appID);
		if (value) {
			[options setObject:(__bridge id)value forKey:key];
			CFRelease(value);
		}
	}
	
	return options;
}

@interface AUP_BAHController : NSObject @end

@implementation AUP_BAHController

- (BOOL)isDearchivable:(NSString *)path whichController:(id *)controller isPrimaryArchive:(BOOL)isPrimary {
	NSString *extension = [[path pathExtension] lowercaseString];
	
	NSArray *supportedFormats = @[@"7z", @"rar", @"xz", @"lzh", @"lha", @"lzma", @"zst", @"tzst", @"cab", @"arj", @"ar"];
	
	if ([supportedFormats containsObject:extension] && controller) {
		NSString *className = nil;
		if ([extension isEqualToString:@"7z"]) {
			className = @"BAHDecompressor7z";
		} else if ([extension isEqualToString:@"rar"]) {
			className = @"BAHDecompressorRAR";
		} else if ([extension isEqualToString:@"xz"]) {
			className = @"BAHDecompressorXZ";
		} else if ([extension isEqualToString:@"lzh"]) {
			className = @"BAHDecompressorLZH";
		} else if ([extension isEqualToString:@"lha"]) {
			className = @"BAHDecompressorLHA";
		} else if ([extension isEqualToString:@"lzma"]) {
			className = @"BAHDecompressorLZMA";
		} else if ([extension isEqualToString:@"zst"]) {
			className = @"BAHDecompressorZST";
		} else if ([extension isEqualToString:@"tzst"]) {
			className = @"BAHDecompressorTZST";
		} else if ([extension isEqualToString:@"cab"]) {
			className = @"BAHDecompressorCAB";
		} else if ([extension isEqualToString:@"arj"]) {
			className = @"BAHDecompressorARJ";
		} else if ([extension isEqualToString:@"ar"]) {
			className = @"BAHDecompressorAR";
		}
		
		Class decompressorClass = NSClassFromString(className);
		
		if (decompressorClass) {
			id options = readArchiveUtilityPreferences();
			*controller = [[decompressorClass alloc] performSelector:@selector(initWithFile:andOptions:) 
														 withObject:path 
														 withObject:options];
			return YES;
		}
	}
	
	return ZKOrig(BOOL, path, controller, isPrimary);
}

@end


static void registerUTIHandlers() {
	NSString *archiveUtilityBundleID = @"com.apple.archiveutility";
	
	NSDictionary *utiMappings = @{
		@"7z": @"org.7-zip.7-zip-archive",
		@"rar": @"com.rarlab.rar-archive",
		@"xz": @"org.tukaani.xz-archive",
		@"lzh": @"public.archive.lzh",
		@"lha": @"public.archive.lha",
		@"lzma": @"org.tukaani.lzma-archive",
		@"zst": @"org.facebook.zstandard-archive",
		@"tzst": @"org.facebook.zstandard-tar-archive",
		@"cab": @"com.microsoft.cab-archive",
		@"arj": @"public.archive.arj",
		@"ar": @"public.archive.ar"
	};
	
	// First, declare the UTIs dynamically if they're not already known
	for (NSString *extension in utiMappings) {
		NSString *uti = utiMappings[extension];
		
		// Set Archive Utility as the default handler for the UTI
		LSSetDefaultRoleHandlerForContentType((__bridge CFStringRef)uti,
											  kLSRolesViewer | kLSRolesEditor,
											  (__bridge CFStringRef)archiveUtilityBundleID);
		
		// Also register by extension using dynamic UTI creation
		CFStringRef dynamicUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, 
																	   (__bridge CFStringRef)extension, 
																	   kUTTypeData);
		if (dynamicUTI) {
			LSSetDefaultRoleHandlerForContentType(dynamicUTI,
												  kLSRolesViewer | kLSRolesEditor,
												  (__bridge CFStringRef)archiveUtilityBundleID);
			CFRelease(dynamicUTI);
		}
	}
}

@implementation NSObject (main)

+ (void)load {
	ZKSwizzle(AUP_BAHController, BAHController);
	createDecompressorClass("BAHDecompressor7z", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorRAR", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorXZ", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorLZH", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorLHA", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorLZMA", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorZST", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorTZST", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorCAB", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorARJ", (IMP)extractArchive);
	createDecompressorClass("BAHDecompressorAR", (IMP)extractArchive);
	
	registerUTIHandlers();
}

@end