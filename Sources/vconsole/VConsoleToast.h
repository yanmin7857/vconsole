#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 轻量 toast：顶部滑入的胶囊提示，自动消失，不拦截任何交互。
/// 替代 UIAlertController 式的“已复制/已保存”提示。
@interface VConsoleToast : NSObject

/// 在指定 window 顶部显示（1.6s 后自动消失）。
+ (void)showInWindow:(nullable UIWindow *)window message:(NSString *)message;

/// 便捷方法：在指定视图所在 window 显示；window 取不到时回退到当前 key window。
+ (void)showInView:(nullable UIView *)view message:(NSString *)message;

/// 便捷方法：直接取当前 key window 显示。
+ (void)showMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
