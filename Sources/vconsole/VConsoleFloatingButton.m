#import "VConsoleCompat.h"
#import "VConsoleFloatingButton.h"
#import "VConsole.h"
#import "VConsoleController.h"
#import "VConsoleFloatingWindow.h"

static const CGFloat kVConsoleFabSize = 54.0;
static const CGFloat kVConsoleFabEdgeMargin = 10.0;
static const NSTimeInterval kVConsoleFabIdleInterval = 3.0;
static const CGFloat kVConsoleFabIdleAlpha = 0.45;

@interface VConsoleFloatingButton ()
@property (nonatomic, assign) BOOL moved;
@property (nonatomic, strong, nullable) NSTimer *idleTimer;
// 键盘避让状态
@property (nonatomic, assign) BOOL keyboardLifted;
@property (nonatomic, assign) CGPoint preKeyboardCenter;
// 长按菜单的兜底承载 window（仅在找不到宿主 VC 时创建，present 完成后释放）
@property (nonatomic, strong, nullable) UIWindow *menuHostWindow;
// 悬浮球自身的承载 window（Scene 架构下用，独立高层级，浮在 modal/SDK 页之上）
// 用 VConsoleFloatingWindow 子类以让空白区域触摸透传，避免遮挡宿主其它按钮
@property (nonatomic, strong, nullable) VConsoleFloatingWindow *fabWindow;
@end

@implementation VConsoleFloatingButton

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.10 green:0.72 blue:0.45 alpha:1.0];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.30;
        self.layer.shadowRadius = 6;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        [self setTitle:@"vC" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:16];

        // 无障碍：悬浮球是打开调试面板的唯一入口，必须可被 VoiceOver 聚焦并说明用途。
        // label 不在这里写死，而是重写 accessibilityLabel getter 实时反映面板开合状态。
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        // 长按菜单是"隐藏功能"，不写进 hint 的话 VoiceOver 用户永远发现不了
        self.accessibilityHint = @"轻点打开或关闭调试面板，长按显示更多选项";

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(panMoved:)];
        [self addGestureRecognizer:pan];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                                action:@selector(longPressed:)];
        longPress.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPress];

        [self addTarget:self action:@selector(didTap) forControlEvents:UIControlEventTouchUpInside];

        // 键盘避让：宿主 App 弹出键盘时若悬浮球被遮挡，临时上移
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(kbWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [nc addObserver:self selector:@selector(kbWillHide:) name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [_idleTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 无障碍

/// 实时反映面板开合状态（面板打开时悬浮球会被隐藏，此处仍保持语义正确）。
/// 用 getter 而不是在 tap 后手动更新，可避免"状态变了但 label 没刷新"。
- (NSString *)accessibilityLabel {
    BOOL visible = [VConsoleController shared].isVisible;
    return visible ? @"vConsole 调试面板，当前已打开" : @"vConsole 调试面板，当前已关闭";
}

// cornerRadius / 旋转后贴边都在布局时机处理（init 时 frame 可能为 CGRectZero）
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetWidth(self.bounds) / 2.0;
    // 旋转 / 分屏导致容器尺寸变化后，保持贴边且不出屏
    if (self.superview && self.superview.bounds.size.width > 0) {
        [self snapToNearestEdgeAnimated:NO persist:NO];
    }
}

#pragma mark - Show

- (void)showInWindow:(UIWindow *)window {
    if (@available(iOS 13.0, *)) {
        // Scene 架构：直接 add 到宿主 window 会在 modal present / SDK 自建 window 时被盖住而消失。
        // 改为放到独立的高层级 UIWindow（windowScene 与宿主一致），浮在所有宿主页面之上，
        // 与 DoraemonKit 做法一致。windowLevel 取 StatusBar 级，低于面板 window（StatusBar+10）。
        if (window.windowScene) {
            // 用 VConsoleFloatingWindow 子类承载：独立高层级 window 让浮球常驻于 modal/SDK 页之上，
            // 但其 hitTest 重写为空白区域透传，因此不挡宿主 App 的其它按钮（对标 DoraemonEntryWindow）。
            VConsoleFloatingWindow *fabWindow = [[VConsoleFloatingWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            fabWindow.backgroundColor = UIColor.clearColor;
            fabWindow.windowLevel = UIWindowLevelStatusBar;
            fabWindow.windowScene = window.windowScene;
            fabWindow.hidden = NO;
            _fabWindow = fabWindow;

            self.frame = CGRectMake(0, 0, kVConsoleFabSize, kVConsoleFabSize);
            self.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                                  | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSNumber *savedX = [defaults objectForKey:VConsoleDefaultsKeyFabX];
            NSNumber *savedY = [defaults objectForKey:VConsoleDefaultsKeyFabY];
            if (savedX && savedY) {
                self.center = CGPointMake(savedX.doubleValue, savedY.doubleValue);
                [self clampToBounds:fabWindow.bounds];
            } else {
                self.center = CGPointMake(fabWindow.bounds.size.width - kVConsoleFabSize / 2.0 - 16,
                                          fabWindow.bounds.size.height - kVConsoleFabSize / 2.0 - 60);
            }
            [fabWindow addSubview:self];
            [self snapToNearestEdgeAnimated:NO persist:NO];
            [self resetIdleState];
            return;
        }
    }
    // 旧架构（无 Scene / iOS 9）：沿用直接挂到宿主 window 的行为
    self.frame = CGRectMake(0, 0, kVConsoleFabSize, kVConsoleFabSize);
    self.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                          | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSNumber *savedX = [defaults objectForKey:VConsoleDefaultsKeyFabX];
    NSNumber *savedY = [defaults objectForKey:VConsoleDefaultsKeyFabY];
    if (savedX && savedY) {
        // 恢复上次位置（clamp 兜底，防止换设备 / 旋转后落屏外）
        self.center = CGPointMake(savedX.doubleValue, savedY.doubleValue);
        [self clampToBounds:window.bounds];
    } else {
        self.center = CGPointMake(window.bounds.size.width - kVConsoleFabSize / 2.0 - 16,
                                  window.bounds.size.height - kVConsoleFabSize / 2.0 - 60);
    }
    [window addSubview:self];
    [self snapToNearestEdgeAnimated:NO persist:NO];
    [self resetIdleState];
}

#pragma mark - Drag

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _moved = NO;
    [self resetIdleState];
    [super touchesBegan:touches withEvent:event];
}

- (void)panMoved:(UIPanGestureRecognizer *)gesture {
    UIView *superview = self.superview;
    if (!superview) return;
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint delta = [gesture translationInView:superview];
        self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
        [gesture setTranslation:CGPointZero inView:superview];
        _moved = YES;
        [self clampToBounds:superview.bounds];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        // 松手触觉反馈 + 弹簧吸附到最近边缘
        UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [haptic impactOccurred];
        [self snapToNearestEdgeAnimated:YES persist:YES];
    }
}

- (void)clampToBounds:(CGRect)bounds {
    CGFloat r = CGRectGetWidth(self.bounds) / 2.0;
    CGFloat x = MIN(MAX(self.center.x, r), bounds.size.width - r);
    CGFloat y = MIN(MAX(self.center.y, r), bounds.size.height - r);
    self.center = CGPointMake(x, y);
}

/// 吸附到最近的左右边缘（弹簧动画），可选持久化目标位置。
/// 无障碍：拖动与吸附期间不主动播报任何内容 —— 位置变化本身不需要朗读，
/// 主动播报反而会在 VoiceOver 下打断用户；label 只在被聚焦时才读取。
- (void)snapToNearestEdgeAnimated:(BOOL)animated persist:(BOOL)persist {
    UIView *superview = self.superview;
    if (!superview) return;
    CGFloat W = CGRectGetWidth(superview.bounds);
    CGFloat H = CGRectGetHeight(superview.bounds);
    if (W <= 0 || H <= 0) return;

    CGFloat r = kVConsoleFabSize / 2.0;
    BOOL toLeft = (self.center.x < W / 2.0);
    CGFloat targetX = toLeft ? (kVConsoleFabEdgeMargin + r) : (W - kVConsoleFabEdgeMargin - r);
    CGFloat targetY = MIN(MAX(self.center.y, kVConsoleFabEdgeMargin + r), H - kVConsoleFabEdgeMargin - r);

    if (persist) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setDouble:targetX forKey:VConsoleDefaultsKeyFabX];
        [defaults setDouble:targetY forKey:VConsoleDefaultsKeyFabY];
    }
    if (animated) {
        [UIView animateWithDuration:0.35
                              delay:0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.center = CGPointMake(targetX, targetY);
        } completion:nil];
    } else {
        self.center = CGPointMake(targetX, targetY);
    }
}

#pragma mark - Long Press Menu

/// 找到可用于 present 的最顶层视图控制器。
/// 悬浮球是 addSubview 到宿主 UIWindow 上的，nextResponder 链为
/// FAB → UIWindow → UIWindowScene → UIApplication → AppDelegate，
/// 链上不存在 UIViewController，靠响应链查找会让 host 恒为 nil、菜单永不弹出。
/// 依次尝试：①所在 window 的 rootVC → ②active scene 的 key window → ③透明临时 window 兜底。
- (UIViewController *)topmostHostViewController {
    UIViewController *top = self.window.rootViewController;
    if (!top) {
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow && w.rootViewController) { top = w.rootViewController; break; }
                }
                if (top) break;
            }
        }
    }
    if (!top) {
        // 释放上一次可能残留的兜底 window，避免多次长按累积
        [self releaseMenuHostWindowIfNeeded];
        UIWindow *tmp = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        tmp.backgroundColor = UIColor.clearColor;
        tmp.windowLevel = UIWindowLevelNormal + 1;
        // iOS 13+ Scene 架构：手动 window 必须绑定 windowScene 才会显示
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive &&
                    [scene isKindOfClass:[UIWindowScene class]]) {
                    tmp.windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        tmp.rootViewController = [[UIViewController alloc] init];
        [tmp makeKeyAndVisible];
        self.menuHostWindow = tmp;
        return tmp.rootViewController;
    }
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top;
}

/// 释放兜底承载 window（若存在）。
/// 注意：不能在 present 的 completion 里调用——alert 就在这个 window 的视图层级里，
/// 提前隐藏会让它随 window 一起消失；必须在菜单关闭时（各 action handler）释放。
- (void)releaseMenuHostWindowIfNeeded {
    if (!self.menuHostWindow) return;
    self.menuHostWindow.hidden = YES;
    self.menuHostWindow = nil;
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self resetIdleState];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    UIViewController *host = [self topmostHostViewController];
    if (!host) {
        NSLog(@"[vconsole] 悬浮球长按：未能找到可 present 的宿主 VC，菜单无法显示");
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    // 用 weakSelf：兜底 window 会 retain alert，alert retain action block，
    // block 若强捕获 self 就形成 self→window→alert→block→self 的引用环
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"隐藏悬浮球（重启 App 后恢复）"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__kindof UIAlertAction *action) {
        weakSelf.hidden = YES;
        [weakSelf releaseMenuHostWindowIfNeeded];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"位置复位"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__kindof UIAlertAction *action) {
        [weakSelf resetToDefaultPosition];
        [weakSelf releaseMenuHostWindowIfNeeded];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__kindof UIAlertAction *action) {
        [weakSelf releaseMenuHostWindowIfNeeded];
    }]];
    // 兜底路径（③）下禁止「点击外部 / 下滑」关闭：保证三个 action 之一必定被调用，
    // 否则 releaseMenuHostWindowIfNeeded 不会被触发，临时 window 会残留。
    // 主路径不创建 menuHostWindow，故此设置不影响已验证的主路径交互。
    if (@available(iOS 13.0, *)) {
        if (self.menuHostWindow) alert.modalInPresentation = YES;
    }
    alert.popoverPresentationController.sourceView = self;
    alert.popoverPresentationController.sourceRect = self.bounds;
    [host presentViewController:alert animated:YES completion:^{
        // 长按菜单：UIKit 默认会把 VoiceOver 焦点移到 presented 的 alert 上。
        // 这里补一次 ScreenChanged，确保焦点确实落进菜单（三个 action 标题本身即可读）。
        if (UIAccessibilityIsVoiceOverRunning()) {
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, alert.view);
        }
    }];
}

- (void)resetToDefaultPosition {
    UIView *superview = self.superview;
    if (!superview || superview.bounds.size.height <= 0) return;
    self.center = CGPointMake(superview.bounds.size.width - kVConsoleFabSize / 2.0 - 16,
                              superview.bounds.size.height * 0.7);
    [self snapToNearestEdgeAnimated:YES persist:YES];
}

#pragma mark - Idle Dim

/// 触摸后恢复不透明并重新计时闲置
- (void)resetIdleState {
    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = 1.0;
    }];
    [self.idleTimer invalidate];
    // block 版 NSTimer + weak 捕获，避免 target 强引用造成循环
    __weak typeof(self) weakSelf = self;
    self.idleTimer = [NSTimer timerWithTimeInterval:kVConsoleFabIdleInterval
                                             repeats:NO
                                               block:^(NSTimer *timer) {
        [weakSelf idleDim];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.idleTimer forMode:NSRunLoopCommonModes];
}

- (void)idleDim {
    [UIView animateWithDuration:0.4 animations:^{
        self.alpha = kVConsoleFabIdleAlpha;
    }];
}

#pragma mark - Keyboard Avoidance

- (void)kbWillShow:(NSNotification *)n {
    UIWindow *win = self.window ?: (UIWindow *)self.superview;
    if (!win) return;
    // 键盘 frame 是屏幕坐标系，转换到悬浮球所在 window
    CGRect kbFrame = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect kbInWindow = [win convertRect:kbFrame fromWindow:nil];
    CGFloat r = CGRectGetWidth(self.bounds) / 2.0;
    if (CGRectGetMaxY(self.frame) <= kbInWindow.origin.y) return; // 未被遮挡

    if (!self.keyboardLifted) {
        self.keyboardLifted = YES;
        self.preKeyboardCenter = self.center;
    }
    CGFloat targetY = MAX(r + kVConsoleFabEdgeMargin, kbInWindow.origin.y - r - 8);
    [self animateCenterY:targetY withKeyboardNotification:n];
}

- (void)kbWillHide:(NSNotification *)n {
    if (!self.keyboardLifted) return;
    self.keyboardLifted = NO;
    CGPoint target = self.preKeyboardCenter;
    // 期间可能发生旋转等变化，clamp 兜底防止落屏外
    if (self.superview && self.superview.bounds.size.height > 0) {
        CGFloat r = CGRectGetWidth(self.bounds) / 2.0;
        CGFloat H = self.superview.bounds.size.height;
        target.y = MIN(MAX(target.y, r + kVConsoleFabEdgeMargin), H - r - kVConsoleFabEdgeMargin);
    }
    [UIView animateWithDuration:0.25 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.center = target;
    } completion:nil];
    // 保持闲置计时节奏
    [self resetIdleState];
}

/// 以键盘动画的时长/曲线移动到指定 Y（X 不变）
- (void)animateCenterY:(CGFloat)y withKeyboardNotification:(NSNotification *)n {
    CGFloat dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [n.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions opts = ((UIViewAnimationOptions)curve << 16) | UIViewAnimationOptionBeginFromCurrentState;
    [UIView animateWithDuration:(dur > 0 ? dur : 0.25) delay:0 options:opts
                     animations:^{
        self.center = CGPointMake(self.center.x, y);
    } completion:nil];
}

#pragma mark - Tap

- (void)didTap {
    if (_moved) return;
    if (self.tapHandler) self.tapHandler();
}

@end
