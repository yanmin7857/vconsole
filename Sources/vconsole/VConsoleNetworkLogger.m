#import "VConsoleCompat.h"
#import "VConsoleNetworkLogger.h"
#import "VConsoleLogger.h"
#import "VConsoleMockCenter.h"
#import <objc/runtime.h>

NSString *const VConsoleNetworkLoggerDidAddEntryNotification = @"VConsoleNetworkLoggerDidAddEntryNotification";
NSString *const VConsoleNetworkLoggerDidClearNotification = @"VConsoleNetworkLoggerDidClearNotification";
NSString *const VConsoleNetworkLoggerDidToggleNotification = @"VConsoleNetworkLoggerDidToggleNotification";
static NSString *const kVConsoleInternalHeader = @"X-VConsole-Internal-Marker";

/// 记录的请求/响应体最大字符数，超出截断显示，避免大响应撑爆内存
static const NSUInteger kVConsoleMaxBodyChars = 50000;
/// 缓存的响应数据上限（约 2MB）：超过后只统计大小、不再缓存内容（数据仍完整转发给原请求方）
static const NSUInteger kVConsoleMaxCaptureBytes = 2 * 1024 * 1024;
/// 通知合并窗口（秒）：并发完成的一批请求合并为一次通知
static const NSTimeInterval kVConsoleNotifyCoalesceInterval = 0.1;

static NSString *vconsoleTruncatedBody(NSString *body) {
    if (body.length <= kVConsoleMaxBodyChars) return body;
    return [NSString stringWithFormat:@"%@\n\n…(已截断，完整内容共 %lu 字符)",
            [body substringToIndex:kVConsoleMaxBodyChars], (unsigned long)body.length];
}

/// 把请求体流完整读入内存。流只能被消费一次，读完后必须以 HTTPBody 数据转发，
/// 否则转发给内部 session 的请求会发出空 body。
static NSData *vconsoleReadBodyStream(NSInputStream *stream) {
    if (!stream) return nil;
    NSMutableData *data = [NSMutableData data];
    [stream open];
    uint8_t buf[64 * 1024];
    while (stream.hasBytesAvailable) {
        NSInteger n = [stream read:buf maxLength:sizeof(buf)];
        if (n <= 0) break;
        [data appendBytes:buf length:(NSUInteger)n];
    }
    [stream close];
    return data;
}

@interface VConsoleNetworkLogger ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableArray<VConsoleNetworkEntry *> *mutableEntries;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL didSwizzle;
// 通知合并：窗口内攒批，一次派发
@property (nonatomic, strong) NSMutableArray<VConsoleNetworkEntry *> *pendingEntries;
@property (nonatomic, assign) BOOL flushScheduled;
- (void)swizzleConfigurations;
- (void)unswizzleConfigurations;
@end

// 提前声明 swizzle 用分类方法，消除 @selector 引用处的 -Wundeclared-selector 警告
@interface NSURLSessionConfiguration (VConsoleInject)
+ (NSURLSessionConfiguration *)vconsole_defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)vconsole_ephemeralSessionConfiguration;
@end

#pragma mark - 协议实现

@interface VConsoleNetworkProtocol : NSURLProtocol <NSURLSessionDataDelegate>
/// 持有内部 session，防止 task 执行期间被 ARC 提前释放
@property (nonatomic, strong, nullable) NSURLSession *internalSession;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *receivedData;
@property (nonatomic, strong, nullable) NSURLResponse *response;
@property (nonatomic, strong) VConsoleNetworkEntry *entry;
@property (nonatomic, strong) NSDate *startTime;
/// 完整接收字节数（含超出缓存上限、未缓存的部分）
@property (nonatomic, assign) NSUInteger totalReceivedBytes;
/// entry 是否已记录，防止取消路径与完成路径重复记录
@property (nonatomic, assign) BOOL entryRecorded;
@end

@implementation VConsoleNetworkProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 关闭抓包后，即使协议仍残留在已创建 session 的 protocolClasses 中也直接放行
    if (![[VConsoleNetworkLogger shared] isEnabled]) return NO;
    if ([request valueForHTTPHeaderField:kVConsoleInternalHeader]) return NO;
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    self.startTime = [NSDate date];
    self.receivedData = [NSMutableData data];
    self.entry = [[VConsoleNetworkEntry alloc] init];
    self.entry.startTime = self.startTime;
    self.entry.method = self.request.HTTPMethod ?: @"GET";
    self.entry.url = self.request.URL.absoluteString;
    self.entry.requestHeaders = self.request.allHTTPHeaderFields;

    NSMutableURLRequest *req = [self.request mutableCopy];
    [req setValue:@"1" forHTTPHeaderField:kVConsoleInternalHeader];

    NSData *body = self.request.HTTPBody;
    if (!body && self.request.HTTPBodyStream) {
        // 流式请求体（multipart / 大 POST）：读入内存并以数据形式转发
        body = vconsoleReadBodyStream(self.request.HTTPBodyStream);
        if (body) req.HTTPBody = body;
    }
    if (body.length) {
        NSString *bodyStr = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        if (bodyStr) self.entry.requestBody = vconsoleTruncatedBody(bodyStr);
    }

    // ---- Mock 拦截：命中后不发出真实请求，直接把本地数据回给原请求方 ----
    if ([VConsoleMockCenter isEnabled]) {
        VConsoleMockResult *mock = [VConsoleMockCenter lookupForURL:self.request.URL];
        if (mock) {
            self.entry.mocked = YES;
            self.entry.statusCode = 200;
            self.entry.endTime = [NSDate date];
            self.entry.durationMs = 0;
            self.entry.responseSize = (NSInteger)mock.data.length;
            self.entry.responseHeaders = @{@"Content-Type": @"application/json"};
            NSString *mockBody = [[NSString alloc] initWithData:mock.data encoding:NSUTF8StringEncoding];
            if (mockBody) self.entry.responseBody = vconsoleTruncatedBody(mockBody);
            self.entryRecorded = YES;
            [[VConsoleNetworkLogger shared] recordEntry:self.entry];
            VConsoleLogI(@"[Mock] 命中 %@ ← %@", self.entry.url, mock.sourceDescription);

            NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                                   statusCode:200
                                                              HTTPVersion:@"HTTP/1.1"
                                                             headerFields:@{@"Content-Type": @"application/json"}];
            [self.client URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:mock.data];
            [self.client URLProtocolDidFinishLoading:self];
            return;
        }
    }

    // 内部 session 必须排除本协议，避免递归拦截。
    // 注意：defaultSessionConfiguration 已被 swizzle，返回的 protocolClasses 首位就是
    // VConsoleNetworkProtocol，这里把它过滤掉、只保留系统协议，保证内部请求真实发出且不会再次命中本协议。
    // 与 canInitWithRequest: 中的 kVConsoleInternalHeader 标记构成双重递归防护。
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSMutableArray *innerClasses = [(cfg.protocolClasses ?: @[]) mutableCopy];
    [innerClasses removeObject:[VConsoleNetworkProtocol class]];
    cfg.protocolClasses = innerClasses;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    cfg.timeoutIntervalForRequest = self.request.timeoutInterval > 0 ? self.request.timeoutInterval : 60;

    // delegateQueue 传 nil：由系统创建串行队列，避免把所有网络回调压到主线程
    self.internalSession = [NSURLSession sessionWithConfiguration:cfg
                                                         delegate:self
                                                    delegateQueue:nil];
    self.task = [self.internalSession dataTaskWithRequest:req];
    [self.task resume];
}

- (void)stopLoading {
    if (self.task) {
        [self.task cancel];
        self.task = nil;
    }
    if (self.internalSession) {
        // session 强持有 delegate，必须 invalidate 才能解除引用环
        [self.internalSession invalidateAndCancel];
        self.internalSession = nil;
    }
    // 外部取消时 didCompleteWithError 不一定回调，这里兜底记录一条「已取消」
    if (self.entry && !self.entryRecorded) {
        self.entryRecorded = YES;
        self.entry.endTime = [NSDate date];
        self.entry.durationMs = [self.entry.endTime timeIntervalSinceDate:self.startTime] * 1000.0;
        self.entry.responseSize = (NSInteger)self.totalReceivedBytes;
        self.entry.error = @"已取消";
        [[VConsoleNetworkLogger shared] recordEntry:self.entry];
    }
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.response = response;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        self.entry.statusCode = http.statusCode;
        self.entry.responseHeaders = http.allHeaderFields;
    }
    // 首字节耗时 TTFB：请求发出（startTime）到收到首个响应头
    self.entry.ttfbMs = [[NSDate date] timeIntervalSinceDate:self.startTime] * 1000.0;
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    // 超过缓存上限后只统计不缓存；数据始终完整转发给原请求方
    if (self.receivedData.length < kVConsoleMaxCaptureBytes) {
        [self.receivedData appendData:data];
    }
    self.totalReceivedBytes += data.length;
    [self.client URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    self.entry.endTime = [NSDate date];
    self.entry.durationMs = [self.entry.endTime timeIntervalSinceDate:self.startTime] * 1000.0;
    self.entry.responseSize = (NSInteger)self.totalReceivedBytes;
    if (self.receivedData.length) {
        NSString *body = [[NSString alloc] initWithData:self.receivedData encoding:NSUTF8StringEncoding];
        if (!body) body = [[NSString alloc] initWithData:self.receivedData encoding:NSISOLatin1StringEncoding];
        if (body) self.entry.responseBody = vconsoleTruncatedBody(body);
    }
    if (error) {
        self.entry.error = error.localizedDescription;
    }
    self.entryRecorded = YES;
    [[VConsoleNetworkLogger shared] recordEntry:self.entry];
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        [self.client URLProtocolDidFinishLoading:self];
    }
    // 释放内部 session，解除 delegate 引用环
    [self.internalSession finishTasksAndInvalidate];
    self.internalSession = nil;
}

@end

#pragma mark - Logger 主体

@implementation VConsoleNetworkLogger

+ (instancetype)shared {
    static VConsoleNetworkLogger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VConsoleNetworkLogger alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.vconsole.netlogger", DISPATCH_QUEUE_SERIAL);
        _mutableEntries = [NSMutableArray array];
        _pendingEntries = [NSMutableArray array];
    }
    return self;
}

- (void)enable {
    if (_enabled) return;
    _enabled = YES;
    [NSURLProtocol registerClass:[VConsoleNetworkProtocol class]];
    [self swizzleConfigurations];
    VConsoleLogI(@"[vConsole] 网络抓包已开启");
    [self postToggle:YES];
}

- (void)disable {
    if (!_enabled) return;
    _enabled = NO;
    [NSURLProtocol unregisterClass:[VConsoleNetworkProtocol class]];
    // 恢复 hook：之后新建的 session 不再注入协议；
    // 已存在 session 的请求由 canInitWithRequest 中的开关检查放行。
    [self unswizzleConfigurations];
    VConsoleLogI(@"[vConsole] 网络抓包已关闭");
    [self postToggle:NO];
}

- (void)postToggle:(BOOL)on {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleNetworkLoggerDidToggleNotification
                                                            object:@(on)];
    });
}

- (BOOL)isEnabled { return _enabled; }

- (NSArray<VConsoleNetworkEntry *> *)entries {
    __block NSArray *r = nil;
    dispatch_sync(_queue, ^{ r = [self.mutableEntries copy]; });
    return r;
}

- (void)clear {
    dispatch_async(_queue, ^{
        [self.mutableEntries removeAllObjects];
        // 清空积压的待派发条目，避免 clear 之后又收到过期的 add 通知
        [self->_pendingEntries removeAllObjects];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleNetworkLoggerDidClearNotification object:nil];
        });
    });
}

- (void)recordEntry:(VConsoleNetworkEntry *)entry {
    if (!entry) return;
    // 过滤纯噪声条目，避免网络面板被无意义记录刷屏：
    //  1) 空接口：URL 为空 / 全空白。JS 钩子回传的非网络消息（如旧版 console 误入
    //     网络通道）没有 url 字段，会解析成 URL 空的记录，一律不收录；
    //  2) 空响应：响应体为空且响应字节数为 0，即没拿到任何接口数据（含跨域拦截等
    //     无数据的失败请求）。
    NSString *trimmedURL = [entry.url stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedURL.length == 0) return;
    BOOL hasResponse = (entry.responseSize > 0) || (entry.responseBody.length > 0);
    if (!hasResponse) return;
    dispatch_async(_queue, ^{
        entry.index = self.mutableEntries.count + 1;
        [self.mutableEntries addObject:entry];
        if (self.mutableEntries.count > 2000) {
            [self.mutableEntries removeObjectsInRange:NSMakeRange(0, self.mutableEntries.count - 2000)];
        }
        // 攒批派发：窗口内的多条记录合并为一次主队列通知（object 为 NSArray<VConsoleNetworkEntry *>）
        [self->_pendingEntries addObject:entry];
        if (!self->_flushScheduled) {
            self->_flushScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVConsoleNotifyCoalesceInterval * NSEC_PER_SEC)),
                           self->_queue, ^{
                self->_flushScheduled = NO;
                if (self->_pendingEntries.count == 0) return;
                NSArray<VConsoleNetworkEntry *> *batch = [self->_pendingEntries copy];
                [self->_pendingEntries removeAllObjects];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:VConsoleNetworkLoggerDidAddEntryNotification
                                                                        object:batch];
                });
            });
        }
    });
}

- (void)swizzleConfigurations {
    if (_didSwizzle) return;
    _didSwizzle = YES;
    Class cls = [NSURLSessionConfiguration class];
    Method m1 = class_getClassMethod(cls, @selector(defaultSessionConfiguration));
    Method m2 = class_getClassMethod(cls, @selector(vconsole_defaultSessionConfiguration));
    if (m1 && m2) method_exchangeImplementations(m1, m2);
    Method m3 = class_getClassMethod(cls, @selector(ephemeralSessionConfiguration));
    Method m4 = class_getClassMethod(cls, @selector(vconsole_ephemeralSessionConfiguration));
    if (m3 && m4) method_exchangeImplementations(m3, m4);
}

- (void)unswizzleConfigurations {
    if (!_didSwizzle) return;
    _didSwizzle = NO;
    Class cls = [NSURLSessionConfiguration class];
    // method_exchangeImplementations 是对合操作：再交换一次即恢复原实现
    Method m1 = class_getClassMethod(cls, @selector(defaultSessionConfiguration));
    Method m2 = class_getClassMethod(cls, @selector(vconsole_defaultSessionConfiguration));
    if (m1 && m2) method_exchangeImplementations(m1, m2);
    Method m3 = class_getClassMethod(cls, @selector(ephemeralSessionConfiguration));
    Method m4 = class_getClassMethod(cls, @selector(vconsole_ephemeralSessionConfiguration));
    if (m3 && m4) method_exchangeImplementations(m3, m4);
}

+ (void)injectProtocol:(NSURLSessionConfiguration *)cfg {
    if (![VConsoleNetworkLogger shared]->_enabled) return;
    NSMutableArray *arr = [cfg.protocolClasses mutableCopy];
    if (!arr) arr = [NSMutableArray array];
    // protocolClasses 是**有序**的：NSURLSession 取数组中第一个 canInitWithRequest: 返回 YES
    // 的协议来处理请求。追加到末尾会被系统的 _NSURLHTTPProtocol 抢先命中，导致本协议永不执行，
    // 因此必须**前置插入**到首位。
    // 去重：若已存在先移除，保证始终只有一个且位于首位。
    if ([arr containsObject:[VConsoleNetworkProtocol class]]) {
        [arr removeObject:[VConsoleNetworkProtocol class]];
    }
    [arr insertObject:[VConsoleNetworkProtocol class] atIndex:0];
    cfg.protocolClasses = arr;
}

@end

#pragma mark - 注入到所有 NSURLSessionConfiguration

@implementation NSURLSessionConfiguration (VConsoleInject)

+ (NSURLSessionConfiguration *)vconsole_defaultSessionConfiguration {
    NSURLSessionConfiguration *cfg = [self vconsole_defaultSessionConfiguration]; // 已交换，调用原方法
    [VConsoleNetworkLogger injectProtocol:cfg];
    return cfg;
}

+ (NSURLSessionConfiguration *)vconsole_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *cfg = [self vconsole_ephemeralSessionConfiguration];
    [VConsoleNetworkLogger injectProtocol:cfg];
    return cfg;
}

@end
