// Disposable Sparkle E2E host. This is never included in Peek's app target.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

static void record(NSString *event, NSString *detail) {
    NSString *path = NSBundle.mainBundle.infoDictionary[@"PeekVerificationReport"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"event":event, @"detail":detail ?: @""} options:0 error:NULL];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    [file seekToEndOfFile]; [file writeData:data]; [file writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]]; [file closeFile];
}

@interface VerificationDriver : NSObject <SPUUserDriver, NSApplicationDelegate>
@property SPUUpdater *updater;
@end

@implementation VerificationDriver
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if ([NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] isEqual:@"2"]) {
        record(@"relaunched", [NSUserDefaults.standardUserDefaults stringForKey:@"fixturePreference"]);
        [NSApp terminate:nil]; return;
    }
    [NSUserDefaults.standardUserDefaults setObject:@"preserved" forKey:@"fixturePreference"];
    self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:self delegate:nil];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) { record(@"error", error.description); [NSApp terminate:nil]; return; }
    [self.updater checkForUpdates];
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation { record(@"checking", nil); }
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    record(@"found", item.versionString);
    if ([NSBundle.mainBundle.infoDictionary[@"PeekVerificationCase"] isEqual:@"skip"]) { reply(SPUUserUpdateChoiceSkip); record(@"skipped", nil); [NSApp terminate:nil]; }
    else reply(SPUUserUpdateChoiceInstall);
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement { record(@"no-update", error.description); acknowledgement(); [NSApp terminate:nil]; }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement { record(@"error", error.description); acknowledgement(); [NSApp terminate:nil]; }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation { record(@"downloading", nil); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { record(@"extracting", nil); }
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { record(@"installing", nil); reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { record(@"installed", nil); acknowledgement(); [NSApp terminate:nil]; }
- (void)dismissUpdateInstallation {}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        VerificationDriver *driver = [VerificationDriver new];
        application.delegate = driver;
        [application run];
    }
    return 0;
}
