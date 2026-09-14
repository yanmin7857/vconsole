#import <Foundation/Foundation.h>
#import <WebKit/WKScriptMessageHandler.h>
#import "VConsoleNetworkEntry.h"

NS_ASSUME_NONNULL_BEGIN

/// WKWebView 网络监控。
///
/// NSURLProtocol 拦截不到 WKWebView 的网络（WebKit 独立进程发出，不经过
/// App 进程的 URL Loading System），这里改用 JS 钩子方案：
/// swizzle WKWebView 的指定初始化器，向其 userContentController 注入
/// document-start 脚本（hook XMLHttpRequest / fetch），页面内的请求经
/// webkit.messageHandlers 回传后构造 VConsoleNetworkEntry 汇入网络面板。
///
/// 生效范围与限制：
///  - attach 之后新建的 WKWebView 自动生效（业务代码零改动）；
///  - 只能捕获页面 JS 发起的 fetch/XHR（含请求/响应头与 body）；
///    <img>/<script> 等静态资源加载不经 JS，无法捕获；
///  - 通过 Storyboard（initWithCoder:）创建的 WebView 不一定走被
///    hook 的初始化路径，此类实例可能不生效。
/// 公开声明 WKScriptMessageHandler 一致性：内部 swizzle 时要把
/// [VConsoleWebViewMonitor shared] 传给 addScriptMessageHandler:，
/// 若只在 .m 的类扩展里声明，公开的 VConsoleWebViewMonitor * 类型不匹配协议会告警。
@interface VConsoleWebViewMonitor : NSObject <WKScriptMessageHandler>

/// 由 VConsole attach 时调用：抓包开启则挂上 swizzle，
/// 并跟随「网络抓包」开关动态启停。重复调用安全。
+ (void)attach;

/// 挂上 WKWebView 初始化 swizzle（幂等）。已创建的 WebView 不受影响。
+ (void)start;
/// 还原 swizzle（幂等）。已注入脚本的页面仍会回传消息，
/// 由消息入口的运行时开关检查放行。
+ (void)stop;

/// JS 消息回传的接收者（单例，被各 userContentController 持有）。
+ (instancetype)shared;

/// 把 JS 钩子回传的 JSON 解析为网络记录（纯逻辑，供单元测试）。
+ (nullable VConsoleNetworkEntry *)entryFromWebJSON:(NSString *)json;

@end

NS_ASSUME_NONNULL_END
