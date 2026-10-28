#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// WebView 面板：列出存活的 WKWebView，在其页面内执行 JS（操作 DOM）并清理缓存。
/// 目标 WebView 由 VConsoleWebViewMonitor 的初始化 swizzle 自动登记，业务零改动。
@interface VConsoleWebViewController : UIViewController

/// 面板每次展示时调用：重新扫描存活的 WebView 并刷新目标选择。
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
