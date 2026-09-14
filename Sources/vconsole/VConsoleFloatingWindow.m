#import "VConsoleFloatingWindow.h"

@implementation VConsoleFloatingWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    // 命中 window 自身或其空白 content view（即没有落在任何真实子视图上）→ 视为空白区域，
    // 返回 nil 让触摸事件透传给下层窗口，避免遮挡宿主 App 的其它按钮 / 控件。
    // 只有真正命中悬浮球（子视图）时 hitView 才不是 self，正常返回。
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}

@end
