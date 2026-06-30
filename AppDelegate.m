#import "AppDelegate.h"
#import "BreakOverlayController.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMediaIO/CMIOHardware.h>
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>
#import <time.h>

// Tunables.
static const NSInteger kWorkInterval       = 20 * 60; // 20 minutes of work
static const NSInteger kBreakDuration      = 20;      // 20 second break
static const NSInteger kIdleResetThreshold = 3 * 60;  // reset if idle >= 3 minutes
static const NSInteger kPostCallGrace      = 2 * 60;  // wait this long after a call before breaking
static NSString *const kBreakSoundName      = @"Blow"; // gentle chime when a break starts
static NSString *const kBreakEndSoundName   = @"Submarine";  // gentle chime when a break completes
static NSString *const kSilentDefaultsKey   = @"Silent"; // NSUserDefaults: suppress all sounds
static NSString *const kPostponeDefaultsKey = @"PostponeForWebcam"; // NSUserDefaults: defer breaks during calls

// YES if any camera is currently capturing in any process. We only read the
// system-wide "is running somewhere" flag CoreMediaIO already maintains, so this
// needs no camera permission, shows no green indicator, and is app-agnostic
// (Zoom, Teams, browser Meet, FaceTime all light up the same flag).
static BOOL EBCameraInUse(void) {
    CMIOObjectPropertyAddress devicesAddr = {
        kCMIOHardwarePropertyDevices,
        kCMIOObjectPropertyScopeGlobal,
        kCMIOObjectPropertyElementMain
    };
    UInt32 dataSize = 0;
    if (CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject, &devicesAddr, 0, NULL, &dataSize)
            != kCMIOHardwareNoError || dataSize == 0) {
        return NO;
    }

    UInt32 count = dataSize / sizeof(CMIOObjectID);
    CMIOObjectID *devices = malloc(dataSize);
    if (!devices) return NO;

    BOOL inUse = NO;
    if (CMIOObjectGetPropertyData(kCMIOObjectSystemObject, &devicesAddr, 0, NULL,
                                  dataSize, &dataSize, devices) == kCMIOHardwareNoError) {
        CMIOObjectPropertyAddress runningAddr = {
            kCMIODevicePropertyDeviceIsRunningSomewhere,
            kCMIOObjectPropertyScopeWildcard,
            kCMIOObjectPropertyElementWildcard
        };
        for (UInt32 i = 0; i < count; i++) {
            UInt32 running = 0, sz = sizeof(running);
            if (CMIOObjectGetPropertyData(devices[i], &runningAddr, 0, NULL,
                                          sz, &sz, &running) == kCMIOHardwareNoError && running) {
                inUse = YES;
                break;
            }
        }
    }
    free(devices);
    return inUse;
}

// Monotonic clock that does NOT advance while the machine is asleep — the work
// interval should only count real on-screen time, not time with the lid shut.
// The 1s timer is just a UI refresh; accuracy comes from comparing against this.
static uint64_t EBNowNanos(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

typedef NS_ENUM(NSInteger, EBState) {
    EBStateWorking,
    EBStateOnBreak,
};

@interface AppDelegate () <NSMenuDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) BreakOverlayController *overlay;
@property (nonatomic, assign) NSInteger secondsRemaining; // break countdown only
@property (nonatomic, assign) uint64_t workDeadline;      // EBNowNanos() of next break
@property (nonatomic, assign) uint64_t pauseStartedAt;    // EBNowNanos() when paused
@property (nonatomic, assign) uint64_t cameraFreeSince;   // EBNowNanos() a call last ended (0 = none/on call)
@property (nonatomic, assign) EBState state;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL silent;
@property (nonatomic, assign) BOOL postponeForWebcam;
@property (nonatomic, assign) BOOL cameraWasInUse;        // previous tick's camera state
@property (nonatomic, strong) NSMenuItem *countdownItem;
@property (nonatomic, strong) NSMenuItem *pauseItem;
@property (nonatomic, strong) NSMenuItem *silentItem;
@property (nonatomic, strong) NSMenuItem *postponeItem;
@property (nonatomic, strong) NSMenuItem *launchAtLoginItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.overlay = BreakOverlayController.new;

    __weak typeof(self) weakSelf = self;
    self.overlay.onSkip = ^{
        [weakSelf endBreak];
    };

    [self setupStatusItem];

    self.state = EBStateWorking;
    [self beginWorkInterval];

    // one tick per second drives the whole app
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(tick)
                                                userInfo:nil
                                                 repeats:YES];

    // keep ticking smoothly even while menus are open
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)setupStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.title = @"\U0001F441";

    NSMenu *menu = NSMenu.new;
    menu.delegate = self;

    // Non-clickable header showing time until the next break. Refreshed by
    // menuNeedsUpdate: before opening and by tick while it stays open.
    self.countdownItem = [menu addItemWithTitle:@"" action:NULL keyEquivalent:@""];
    self.countdownItem.enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];

    [menu addItemWithTitle:@"Look away now"
                    action:@selector(takeBreakNow:)
             keyEquivalent:@""].target = self;

    [menu addItemWithTitle:@"Reset timer"
                    action:@selector(resetTimer:)
             keyEquivalent:@""].target = self;

    self.pauseItem = [menu addItemWithTitle:@"Pause"
                                     action:@selector(togglePause:)
                              keyEquivalent:@""];
    self.pauseItem.target = self;

    [menu addItem:NSMenuItem.separatorItem];

    self.silentItem = [menu addItemWithTitle:@"Silent"
                                      action:@selector(toggleSilent:)
                               keyEquivalent:@""];
    self.silentItem.target = self;
    self.silent = [NSUserDefaults.standardUserDefaults boolForKey:kSilentDefaultsKey];
    self.silentItem.state = self.silent ? NSControlStateValueOn : NSControlStateValueOff;

    self.postponeItem = [menu addItemWithTitle:@"Postpone for webcam"
                                        action:@selector(togglePostpone:)
                                 keyEquivalent:@""];
    self.postponeItem.target = self;
    self.postponeForWebcam = [NSUserDefaults.standardUserDefaults boolForKey:kPostponeDefaultsKey];
    self.postponeItem.state = self.postponeForWebcam ? NSControlStateValueOn : NSControlStateValueOff;

    self.launchAtLoginItem = [menu addItemWithTitle:@"Launch at login"
                                             action:@selector(toggleLaunchAtLogin:)
                                      keyEquivalent:@""];
    self.launchAtLoginItem.target = self;
    [self updateLaunchAtLoginState];

    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItemWithTitle:@"Quit EyeBreak"
                    action:@selector(quit:)
             keyEquivalent:@"q"].target = self;

    self.statusItem.menu = menu;
}

#pragma mark - Work interval

// Anchor the next break to a wall-position on the monotonic uptime clock, so the
// countdown stays accurate even if ticks are late, dropped, or coalesced.
- (void)beginWorkInterval {
    self.workDeadline = EBNowNanos() + (uint64_t)kWorkInterval * NSEC_PER_SEC;
}

// Signed: goes negative once the deadline has passed but a break has been held
// off (e.g. while you're on a call), so the menu can show how overdue you are.
- (NSInteger)workSecondsRemaining {
    uint64_t now = EBNowNanos();
    if (now >= self.workDeadline) {
        return -(NSInteger)((now - self.workDeadline) / NSEC_PER_SEC);
    }
    return (NSInteger)ceil((double)(self.workDeadline - now) / (double)NSEC_PER_SEC);
}

#pragma mark - Menu countdown

- (NSString *)countdownText {
    if (self.paused) return @"Paused";
    if (self.state == EBStateOnBreak) return @"Looking away";
    NSInteger total = [self workSecondsRemaining];
    NSString *sign = total < 0 ? @"-" : @"";
    NSInteger mag = labs(total);
    return [NSString stringWithFormat:@"Look away in %@%ld:%02ld",
            sign, (long)(mag / 60), (long)(mag % 60)];
}

- (void)refreshCountdownItem {
    self.countdownItem.title = [self countdownText];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [self refreshCountdownItem];
}

#pragma mark - Timer loop

- (void)tick {
    [self refreshCountdownItem]; // keep the header live while the menu is open
    if (self.paused) return;

    if (self.state == EBStateWorking) {
        // Track the camera so we can hold breaks during (and just after) calls.
        BOOL cameraOn = NO;
        if (self.postponeForWebcam) {
            cameraOn = EBCameraInUse();
            if (cameraOn) {
                self.cameraFreeSince = 0;             // on a call right now
            } else if (self.cameraWasInUse) {
                self.cameraFreeSince = EBNowNanos();  // a call just ended
            }
            self.cameraWasInUse = cameraOn;
        }

        // Optional frill: if the user has been idle for a while, keep the
        // timer pinned at full so they get a fresh 20 minutes when they return.
        // Skipped while on a call — you're present even if you aren't typing,
        // and the deadline should keep counting down (and go overdue).
        if (!cameraOn) {
            CFTimeInterval idle = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,
                                                                         kCGAnyInputEventType);
            if (idle >= kIdleResetThreshold) {
                [self beginWorkInterval];
                self.cameraFreeSince = 0;
                return;
            }
        }

        if ([self workSecondsRemaining] <= 0) {
            // A break is due — but don't interrupt a call, nor pounce the
            // instant it ends. Wait out a short grace period after hang-up.
            if (cameraOn) return;
            if (self.cameraFreeSince != 0 &&
                EBNowNanos() - self.cameraFreeSince < (uint64_t)kPostCallGrace * NSEC_PER_SEC) {
                return;
            }
            [self startBreak];
            return;
        }

    } else { // EBStateOnBreak
        // The break only "counts" while you're actually away from the keyboard
        // and mouse (i.e. genuinely looking into the distance). Any input
        // activity restarts the 20s countdown.
        CFTimeInterval idle = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,
                                                                     kCGAnyInputEventType);
        if (idle < 1.0) {
            self.secondsRemaining = kBreakDuration;
            [self.overlay updateSecondsRemaining:self.secondsRemaining];
            return;
        }

        self.secondsRemaining -= 1;
        [self.overlay updateSecondsRemaining:self.secondsRemaining];
        if (self.secondsRemaining <= 0) {
            // Chime only on a genuinely completed break — skip/reset stay silent.
            [self playSound:kBreakEndSoundName];
            [self endBreak];
        }
    }
}

#pragma mark - Break lifecycle

- (void)playSound:(NSString *)name {
    if (self.silent) return;
    [[NSSound soundNamed:name] play];
}

- (void)startBreak {
    self.state = EBStateOnBreak;
    self.secondsRemaining = kBreakDuration;
    self.cameraFreeSince = 0;

    [self playSound:kBreakSoundName];

    // Deliberately do NOT activate/steal focus — the small overlay just floats
    // on top so it won't interrupt a call or whatever you're doing.
    [self.overlay show];
    [self.overlay updateSecondsRemaining:self.secondsRemaining];
}

- (void)endBreak {
    [self.overlay hide];
    self.state = EBStateWorking;
    [self beginWorkInterval];
}

#pragma mark - Menu actions

- (void)takeBreakNow:(id)sender {
    if (self.state == EBStateWorking) {
        [self startBreak];
    }
}

- (void)resetTimer:(id)sender {
    if (self.state == EBStateOnBreak) {
        [self endBreak];
    } else {
        [self beginWorkInterval];
    }
}

- (void)togglePause:(id)sender {
    self.paused = !self.paused;
    if (self.paused) {
        // Freeze: remember when we paused so we can push the deadline forward by
        // the paused duration on resume (real time keeps passing while paused).
        self.pauseStartedAt = EBNowNanos();
    } else {
        self.workDeadline += EBNowNanos() - self.pauseStartedAt;
    }
    self.pauseItem.title = self.paused ? @"Resume" : @"Pause";
}

- (void)toggleSilent:(id)sender {
    self.silent = !self.silent;
    [NSUserDefaults.standardUserDefaults setBool:self.silent forKey:kSilentDefaultsKey];
    self.silentItem.state = self.silent ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)togglePostpone:(id)sender {
    self.postponeForWebcam = !self.postponeForWebcam;
    [NSUserDefaults.standardUserDefaults setBool:self.postponeForWebcam forKey:kPostponeDefaultsKey];
    self.postponeItem.state = self.postponeForWebcam ? NSControlStateValueOn : NSControlStateValueOff;
    if (!self.postponeForWebcam) {
        self.cameraWasInUse = NO;
        self.cameraFreeSince = 0;
    }
}

- (void)toggleLaunchAtLogin:(id)sender {
    SMAppService *service = [SMAppService mainAppService];
    NSError *error = nil;
    BOOL ok;
    if (service.status == SMAppServiceStatusEnabled) ok = [service unregisterAndReturnError:&error];
    else ok = [service registerAndReturnError:&error];

    if (!ok) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Couldn't change launch at login status";
        alert.informativeText = error.localizedDescription ?: @"Unknown error.";
        [alert runModal];
    }
    [self updateLaunchAtLoginState];
}

- (void)updateLaunchAtLoginState {
    BOOL enabled = ([SMAppService mainAppService].status == SMAppServiceStatusEnabled);
    self.launchAtLoginItem.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end
