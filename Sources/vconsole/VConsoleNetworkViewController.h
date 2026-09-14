#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 网络 Tab：展示被拦截的请求，支持详情与清空。
@interface VConsoleNetworkViewController : UIViewController

- (void)refresh;

/// 键盘快捷键（Cmd+F）入口：聚焦顶部搜索框
- (void)focusSearch;

@end

NS_ASSUME_NONNULL_END
