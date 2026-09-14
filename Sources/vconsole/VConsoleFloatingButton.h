#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 仿 H5 vConsole 的绿色悬浮球：可拖动，点击切换调试面板。
@interface VConsoleFloatingButton : UIButton

@property (nonatomic, copy, nullable) void (^tapHandler)(void);

- (void)showInWindow:(UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
