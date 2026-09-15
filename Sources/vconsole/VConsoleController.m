#import "VConsoleCompat.h"
#import "VConsoleController.h"
#import "VConsoleViewController.h"
#import "VConsole.h"

@interface VConsoleController ()
@property (nonatomic, strong, nullable) UIWindow *consoleWindow;
@property (nonatomic, strong, nullable) VConsoleViewController *panelVC;
@property (nonatomic, weak, nullable) UIButton *floatingButton;
// 把头文件里 readonly 的 isVisible 在类扩展中重声明为 readwrite，使 show/hide 能直接赋值。
// 不要另起一个 visible 属性：那会合成出第二个 ivar（_visible），
// 导致公开的 isVisible（_isVisible）永远为 NO。
@property (nonatomic, assign, readwrite) BOOL isVisible;
/// 关闭动画的代际令牌：show 会使令牌失效，防止动画回调期间被重新打开的窗口又被隐藏
@property (nonatomic, assign) NSInteger hideToken;
@end

@implementation VConsoleController

+ (instancetype)shared {
    static VConsoleController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VConsoleController alloc] init];
    });
    return instance;
}

- (UIWindow *)consoleWindow {
    if (!_consoleWindow) {
        _consoleWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        _consoleWindow.windowLevel = UIWindowLevelStatusBar + 10;
        _consoleWindow.hidden = YES;
        _consoleWindow.backgroundColor = [UIColor clearColor];
        // iOS 13+ 启用 Scene 的 App 里，手动 alloc 的 UIWindow 必须绑定 windowScene
        // 才会被系统纳入场景、才能显示并接收触摸事件。否则 w.hidden = NO 无视觉效果，
        // 表现为「悬浮球能点、但面板弹框打不开」。iOS 9/11/12 无 Scene，跳过即可。
        if (@available(iOS 13.0, *)) {
            _consoleWindow.windowScene = [self vconsole_activeScene];
        }
        // 应用持久化的主题设置（面板独立 window，不影响宿主 App）
        NSInteger theme = [[NSUserDefaults standardUserDefaults] integerForKey:VConsoleDefaultsKeyThemeIndex];
        if (@available(iOS 13.0, *)) {
            if (theme == 1) _consoleWindow.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            else if (theme == 2) _consoleWindow.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
        _panelVC = [[VConsoleViewController alloc] init];
        _consoleWindow.rootViewController = _panelVC;
    }
    return _consoleWindow;
}

/// 取当前前台激活的 UIWindowScene（iOS 13+）。无 Scene 的旧架构返回 nil（由调用方跳过绑定）。
- (nullable UIWindowScene *)vconsole_activeScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                return (UIWindowScene *)scene;
            }
        }
        // 兜底：任意已连接的 window scene（如前台激活态尚未就绪时）
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (void)setFloatingButton:(UIButton *)button {
    _floatingButton = button;
}

- (void)show {
    // 使进行中的关闭动画失效：其 completion 不再隐藏窗口
    self.hideToken++;
    UIWindow *w = self.consoleWindow;
    w.frame = UIScreen.mainScreen.bounds;
    w.hidden = NO;
    self.floatingButton.hidden = YES;
    self.isVisible = YES;
    // 面板弹入动画（内部会确保 view 已加载）
    [self.panelVC animatePanelIn];
    [self.panelVC refreshVisible];
}

- (void)hide {
    if (!self.isVisible) return;
    self.isVisible = NO;
    self.hideToken++;
    NSInteger token = self.hideToken;
    [self.panelVC animatePanelOutWithCompletion:^{
        // 动画期间若面板又被打开（token 变化），则不隐藏窗口
        if (token != self.hideToken) return;
        self.consoleWindow.hidden = YES;
        self.floatingButton.hidden = NO;
    }];
}

- (void)toggle {
    if (self.isVisible) [self hide];
    else [self show];
}

- (void)selectPanelTab:(NSInteger)index {
    // 触发 consoleWindow 懒加载，确保 panelVC 已创建（面板 VC 在 consoleWindow getter 中实例化）
    (void)self.consoleWindow;
    [self.panelVC selectTabAtIndex:index];
}

@end
