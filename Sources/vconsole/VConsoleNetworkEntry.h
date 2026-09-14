#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VConsoleNetworkEntry : NSObject

@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *requestHeaders;
@property (nonatomic, copy, nullable) NSString *requestBody;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *responseHeaders;
@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, strong, nullable) NSDate *endTime;
@property (nonatomic, assign) NSTimeInterval durationMs;
@property (nonatomic, assign) NSInteger responseSize;
@property (nonatomic, copy, nullable) NSString *responseBody;
@property (nonatomic, copy, nullable) NSString *error;
/// 是否由本地 Mock 返回（未发出真实网络请求）
@property (nonatomic, assign) BOOL mocked;
/// 请求来自 WKWebView 页面内的 JS（fetch/XHR），由 VConsoleWebViewMonitor 经 JS 钩子回传记录
@property (nonatomic, assign) BOOL fromWeb;

- (NSString *)durationText;
- (NSString *)statusText;

/// 把该请求还原为等效 curl 命令（含方法/头/`--data-raw` body，单引号已转义），
/// 可在终端直接复现
- (NSString *)curlCommand;

@end

NS_ASSUME_NONNULL_END
