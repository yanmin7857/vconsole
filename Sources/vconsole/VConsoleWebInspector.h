#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 「WebView」面板的底层能力：跟踪存活的 WKWebView、在其页面内执行 JS（操作 DOM）、清理缓存。
///
/// 实例跟踪由 VConsoleWebViewMonitor 的初始化 swizzle 驱动（业务零改动）：
/// 每个经 initWithFrame:configuration: 创建的 WKWebView 都会被登记一次（弱引用，
/// 释放后自动从列表移除），面板据此列出可选目标。
@interface VConsoleWebInspector : NSObject

#pragma mark - 实例跟踪

/// 登记一个存活的 WKWebView（弱引用、幂等）。由 swizzle 在其初始化时调用。
+ (void)registerWebView:(WKWebView *)webView;

/// 当前存活的 WKWebView，按创建先后排序（已释放的自动剔除）。
+ (NSArray<WKWebView *> *)liveWebViews;

#pragma mark - JS / DOM

/// 在页面内执行 JS。completion 在主线程回调，返回结果文本；
/// 执行出错时以 "❌ " 前缀返回错误描述（不抛异常）。webView 为 nil 时直接返回错误文本。
+ (void)evaluateScript:(NSString *)js
             inWebView:(nullable WKWebView *)webView
            completion:(void (^)(NSString *result))completion;

/// 读取页面基本信息（标题 / URL / 文档状态 / 元素数量），completion 在主线程回调。
+ (void)fetchPageInfoForWebView:(nullable WKWebView *)webView
                     completion:(void (^)(NSString *info))completion;

#pragma mark - 缓存

/// 清理指定类型的网站数据（WKWebsiteDataType* 集合）。整站共享一个 dataStore，
/// 因此影响所有 WebView。completion 在主线程回调（在清理完成后）。
+ (void)clearDataTypes:(NSSet<NSString *> *)dataTypes
            completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
