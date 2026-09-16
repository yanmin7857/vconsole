#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 视图树 Tab：递归检视当前 App 的 UIView 层级（对标 H5 vConsole 的 Element 面板）。
@interface VConsoleElementViewController : UIViewController

- (void)refresh;

@end

NS_ASSUME_NONNULL_END
