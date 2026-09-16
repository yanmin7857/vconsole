#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 仿 H5 vConsole 的绿色悬浮球：可拖动，点击切换调试面板。
@interface VConsoleFloatingButton : UIButton

@property (nonatomic, copy, nullable) void (^tapHandler)(void);

- (void)showInWindow:(UIWindow *)window;

/// 多 window / Scene 增强：把悬浮球承载窗口重新绑定到指定 UIWindowScene。
/// 用于 iPad 多窗口 / Stage Manager 下场景切换时，悬浮球始终停留在当前激活场景之上。
- (void)rebindToScene:(nullable UIWindowScene *)scene NS_AVAILABLE_IOS(13.0);

@end

NS_ASSUME_NONNULL_END
