#import "VConsoleCompat.h"
#import "VConsole.h"

// 持久化键在 Release 分支中也会被 VConsoleLogger / VConsoleController 引用，故放在条件编译之外
NSString * const VConsoleDefaultsKeyThemeIndex = @"vcs.themeIndex";
NSString * const VConsoleDefaultsKeyLevelFilter = @"vcs.levelFilter";
NSString * const VConsoleDefaultsKeyNetworkEnabled = @"vcs.networkEnabled";
NSString * const VConsoleDefaultsKeyFabX = @"vcs.fabX";
NSString * const VConsoleDefaultsKeyFabY = @"vcs.fabY";
NSString * const VConsoleDefaultsKeyPanelHeight = @"vcs.panelHeight";
NSString * const VConsoleDefaultsKeyMockEnabled = @"vcs.mockEnabled";
NSString * const VConsoleDefaultsKeyRedactionEnabled = @"vcs.redactionEnabled";
NSString * const VConsoleDefaultsKeyShakeEnabled = @"vcs.shakeEnabled";
NSString * const VConsoleDefaultsKeyCrashEnabled = @"vcs.crashEnabled";

#ifdef DEBUG

#import "VConsoleLogger.h"
#import "VConsoleNetworkLogger.h"
#import "VConsoleWebViewMonitor.h"
#import "VConsoleController.h"
#import "VConsoleFloatingButton.h"
#import "VConsoleCrashReporter.h"
#import "VConsoleRedactor.h"
#import <objc/runtime.h>

// 防重入：多次调用 attachToWindow: 只创建一个悬浮球
// （stderr 捕获与网络开关本身幂等，无需额外保护）
static BOOL gVConsoleFabAttached = NO;
// 多 window / Scene 增强：记录悬浮球实例，场景切换时重绑到激活场景
static BOOL gVConsoleSceneObserved = NO;
static __strong VConsoleFloatingButton *gVConsoleFab = nil;

@implementation VConsole

+ (void)start {
    UIWindow *window = [self vconsole_currentKeyWindow];
    if (window) {
        [self attachToWindow:window];
    } else {
        // 窗口尚未就绪（Scene 应用过早调用）：等首个 keyWindow 出现再挂载一次。
        // 用 dispatch_once 语义的静态标记防止重复注册。
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(vconsole_windowDidBecomeKey:)
                                                     name:UIWindowDidBecomeKeyNotification
                                                   object:nil];
    }
}

/// 首个 keyWindow 出现时挂载（仅 start 时序兜底路径触发）
+ (void)vconsole_windowDidBecomeKey:(NSNotification *)note {
    UIWindow *window = note.object;
    if ([window isKindOfClass:[UIWindow class]] && !gVConsoleFabAttached) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIWindowDidBecomeKeyNotification
                                                      object:nil];
        [self attachToWindow:window];
    }
}

/// 自动取当前可用于挂载的窗口：
/// iOS 13+：前台激活的 UIWindowScene 中优先 keyWindow，否则取第一个 window（启动早期可能还没 keyWindow）；
/// iOS 9~12：回退到 [UIApplication sharedApplication].keyWindow（该 API 在 13 已弃用）。
+ (nullable UIWindow *)vconsole_currentKeyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
            return ws.windows.firstObject; // 启动早期回退
        }
        return nil;
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
    #pragma clang diagnostic pop
}

+ (void)attachToWindow:(nullable UIWindow *)window {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{VConsoleDefaultsKeyNetworkEnabled: @YES}];

    // 网络抓包遵循上次设置（默认开启）
    if ([defaults boolForKey:VConsoleDefaultsKeyNetworkEnabled]) {
        [[VConsoleNetworkLogger shared] enable];
    }
    // WKWebView 网络监控（JS 钩子）跟随抓包开关启停，之后新建的 WebView 自动生效
    [VConsoleWebViewMonitor attach];
    // 仅在开关开启时捕获 stderr（默认开启）；关闭后 Xcode 控制台恢复
    if ([[VConsoleLogger shared] captureStderrEnabled]) {
        [[VConsoleLogger shared] startCapturingStderr];
    }

    // 进阶能力：读取持久化开关并生效
    [VConsoleRedactor setEnabled:[defaults boolForKey:VConsoleDefaultsKeyRedactionEnabled]];
    [VConsoleCrashReporter setEnabled:[defaults boolForKey:VConsoleDefaultsKeyCrashEnabled]];
    if ([defaults boolForKey:VConsoleDefaultsKeyCrashEnabled]) {
        [VConsoleCrashReporter install];
        [VConsoleCrashReporter replayLastCrashIfAny];
    }
    if ([defaults boolForKey:VConsoleDefaultsKeyShakeEnabled]) {
        [self vconsole_installShake];
    }

    if (window && !gVConsoleFabAttached) {
        gVConsoleFabAttached = YES;
        VConsoleFloatingButton *fab = [[VConsoleFloatingButton alloc] initWithFrame:CGRectZero];
        [fab showInWindow:window];
        fab.tapHandler = ^{
            [[VConsoleController shared] toggle];
        };
        [[VConsoleController shared] setFloatingButton:fab];
        gVConsoleFab = fab;
    }

    // 多 window / Scene 增强：场景激活切换时，把悬浮球重绑到当前激活场景之上
    // （iPad 多窗口 / Stage Manager 下，原场景进入后台后悬浮球会随之消失）。
    if (!gVConsoleSceneObserved) {
        gVConsoleSceneObserved = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(vconsole_sceneDidActivate:)
                                                     name:UISceneDidActivateNotification
                                                   object:nil];
    }
}

+ (void)show { [[VConsoleController shared] show]; }
+ (void)hide { [[VConsoleController shared] hide]; }
+ (void)toggle { [[VConsoleController shared] toggle]; }
+ (void)selectPanelTab:(VConsolePanelTab)tab {
    [[VConsoleController shared] selectPanelTab:(NSInteger)tab];
}

#pragma mark - 进阶能力开关

+ (void)setRedactionEnabled:(BOOL)enabled {
    [VConsoleRedactor setEnabled:enabled];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:VConsoleDefaultsKeyRedactionEnabled];
}

+ (void)setCrashReportingEnabled:(BOOL)enabled {
    [VConsoleCrashReporter setEnabled:enabled];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:VConsoleDefaultsKeyCrashEnabled];
    if (enabled) {
        [VConsoleCrashReporter install];
        [VConsoleCrashReporter replayLastCrashIfAny];
    }
}

+ (void)setShakeToToggleEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:VConsoleDefaultsKeyShakeEnabled];
    if (enabled) [self vconsole_installShake];
}

+ (void)setCaptureStderrEnabled:(BOOL)enabled {
    [[VConsoleLogger shared] setCaptureStderrEnabled:enabled];
}

#pragma mark - 摇一摇唤起（swizzle UIWindow 的 motionEnded:）

static BOOL gVConsoleShakeSwizzled = NO;

+ (void)vconsole_installShake {
    if (gVConsoleShakeSwizzled) return;
    gVConsoleShakeSwizzled = YES;
    Class cls = [UIWindow class];
    SEL original = @selector(motionEnded:withEvent:);
    SEL swizzled = @selector(vconsole_motionEnded:withEvent:);
    Method m1 = class_getInstanceMethod(cls, original);
    Method m2 = class_getInstanceMethod(cls, swizzled);
    if (m1 && m2) method_exchangeImplementations(m1, m2);
}

- (void)vconsole_motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    [self vconsole_motionEnded:motion withEvent:event]; // 调回原实现
    if (motion == UIEventSubtypeMotionShake &&
        [[NSUserDefaults standardUserDefaults] boolForKey:VConsoleDefaultsKeyShakeEnabled]) {
        [VConsole toggle];
    }
}

#pragma mark - 多 window / Scene 增强

/// 场景激活切换时，把悬浮球承载窗口重绑到新激活的 UIWindowScene。
+ (void)vconsole_sceneDidActivate:(NSNotification *)note {
    UIScene *scene = note.object;
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    if (@available(iOS 13.0, *)) {
        if (gVConsoleFab) [gVConsoleFab rebindToScene:(UIWindowScene *)scene];
    }
}

@end

#else

// Release 构建：全部空实现，调试能力完全移除
@implementation VConsole

+ (void)start {}
+ (void)attachToWindow:(nullable UIWindow *)window {}
+ (void)show {}
+ (void)hide {}
+ (void)toggle {}
+ (void)selectPanelTab:(VConsolePanelTab)tab {}

@end

#endif
