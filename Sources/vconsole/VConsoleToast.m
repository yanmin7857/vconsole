#import "VConsoleCompat.h"
#import "VConsoleToast.h"

static const NSInteger kVConsoleToastTag = 0x56435354; // "VConsoleT"
static const NSTimeInterval kVConsoleToastDuration = 1.6;

@implementation VConsoleToast

+ (UIWindow *)vconsole_keyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
        // 兜底：非激活状态取第一个 window scene 的 keyWindow
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    }
    // iOS 9 回退：遍历 windows 找 keyWindow（用 isKeyWindow 规避 keyWindow 属性的高版本要求）
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) return w;
    }
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
    return windows.firstObject;
}

+ (void)showInView:(UIView *)view message:(NSString *)message {
    [self showInWindow:view.window message:message];
}

+ (void)showMessage:(NSString *)message {
    [self showInWindow:[self vconsole_keyWindow] message:message];
}

+ (void)showInWindow:(UIWindow *)window message:(NSString *)message {
    if (!window || message.length == 0) return;
    // 同一时间只保留一个 toast
    [[window viewWithTag:kVConsoleToastTag] removeFromSuperview];

    UILabel *label = [[UILabel alloc] init];
    label.tag = kVConsoleToastTag;
    label.text = message;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.layer.cornerRadius = 16;
    label.layer.masksToBounds = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    // userInteractionEnabled = NO：toast 永不拦截点击
    label.userInteractionEnabled = NO;
    [window addSubview:label];

    if (@available(iOS 11.0, *)) {
        [label.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:10].active = YES;
    } else {
        // iOS 9 无 safeAreaLayoutGuide：直接贴在窗口顶部（含状态栏高度）
        [label.topAnchor constraintEqualToAnchor:window.topAnchor constant:30].active = YES;
    }
    [label.centerXAnchor constraintEqualToAnchor:window.centerXAnchor].active = YES;
    [label.widthAnchor constraintLessThanOrEqualToConstant:window.bounds.size.width - 32].active = YES;
    [label.heightAnchor constraintGreaterThanOrEqualToConstant:32].active = YES;

    // 滑入动画
    label.alpha = 0;
    label.transform = CGAffineTransformMakeTranslation(0, -14);
    [UIView animateWithDuration:0.25
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.3
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        label.alpha = 1;
        label.transform = CGAffineTransformIdentity;
    } completion:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVConsoleToastDuration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // tag 不匹配说明已被新 toast 顶替，跳过移除
        if (label.tag != kVConsoleToastTag || label.superview != window) return;
        [UIView animateWithDuration:0.25 animations:^{
            label.alpha = 0;
            label.transform = CGAffineTransformMakeTranslation(0, -10);
        } completion:^(BOOL finished) {
            [label removeFromSuperview];
        }];
    });
}

@end
