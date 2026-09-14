#import <Foundation/Foundation.h>
#import "VConsoleNetworkEntry.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const VConsoleNetworkLoggerDidAddEntryNotification;
extern NSString *const VConsoleNetworkLoggerDidClearNotification;
/// 抓包开关切换（enable/disable 时派发，object 为 @(BOOL enabled)）
extern NSString *const VConsoleNetworkLoggerDidToggleNotification;

/// 与 H5 vConsole Network 面板一致：通过 NSURLProtocol 拦截 App 内所有
/// NSURLSession / NSURLConnection 请求，记录方法、URL、状态、耗时、响应大小。
@interface VConsoleNetworkLogger : NSObject

+ (instancetype)shared;

/// 开启抓包：注册全局协议 + hook NSURLSessionConfiguration，使之后新建的 session 也会被拦截。
- (void)enable;
/// 关闭抓包：注销协议 + 恢复 hook。已存在的 session 也会因内部开关检查而放行。
- (void)disable;
- (BOOL)isEnabled;

- (NSArray<VConsoleNetworkEntry *> *)entries;
- (void)clear;

/// 外部采集器注入一条记录（如 WKWebView 监控的 JS 钩子回传）。
/// 线程安全，与协议拦截走同一套容量上限与合并通知。
- (void)recordEntry:(VConsoleNetworkEntry *)entry;

@end

NS_ASSUME_NONNULL_END
