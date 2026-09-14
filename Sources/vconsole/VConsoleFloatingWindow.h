#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 悬浮球承载窗口。
///
/// 作用：在 iOS 13+ Scene 架构下，把调试浮球放进一个独立的高层级 UIWindow，
/// 让它常驻于宿主的 modal / SDK 自建 window 之上（不会像直接 addSubview 到宿主
/// window 那样被盖住而消失）。这与 DoraemonKit 的 DoraemonEntryWindow 思路一致。
///
/// 关键点：重写 hitTest:，让 window 自身及其空白 content view 不拦截触摸——
/// 屏幕上的非按钮区域会把事件透传给下层的宿主窗口，因此**不挡宿主 App 的其它按钮**。
/// 只有真正落在悬浮球上的触摸才会被本 window 接收。
@interface VConsoleFloatingWindow : UIWindow
@end

NS_ASSUME_NONNULL_END
