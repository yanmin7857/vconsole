#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 网络 Tab：展示被拦截的请求，支持详情与清空。
@interface VConsoleNetworkViewController : UIViewController

- (void)refresh;

/// 键盘快捷键（Cmd+F）入口：聚焦顶部搜索框
- (void)focusSearch;

/// 搜索结果导航：⌘G 下一个 / ⇧⌘G 上一个匹配（由面板容器快捷键转发）
- (void)nextMatch;
- (void)prevMatch;

@end

NS_ASSUME_NONNULL_END
