#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// WKWebView 网络监控演示页：加载时自动发出 fetch + XHR 请求，
/// 用于验证 vconsole 对 WebView 内 JS 请求的捕获（网络面板青色 · H5 标记）。
@interface DemoWebViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
