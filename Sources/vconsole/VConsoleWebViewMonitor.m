#import "VConsoleCompat.h"
#import "VConsoleWebViewMonitor.h"

#ifdef DEBUG

#import "VConsoleNetworkLogger.h"
#import "VConsoleLogger.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

#pragma mark - 注入页面的 JS 钩子源码

// document-start 注入（forMainFrameOnly:NO，iframe 一并覆盖），先于页面自身脚本执行：
//  - hook XMLHttpRequest.prototype 的 open/setRequestHeader/send，完成/失败时回传
//  - hook window.fetch（含 Request 对象入参），响应 clone 后异步读取 body 回传
//  - hook window.console 的 log/info/debug/warn/error，序列化参数回传（进日志面板）
//  - 回传通道：window.webkit.messageHandlers.vconsoleNet（网络）/ vconsoleLog（H5 控制台日志），负载为 JSON 字符串
//  - body 超过 50k 字符在 JS 侧先截断（与原生 kVConsoleMaxBodyChars 上限一致）
// 注意：JS 源码里的反斜杠转义（如 \n）在 ObjC 字面量中必须写成 \\n；
// 字符串一律用单引号，避免与 ObjC 字面量的双引号转义纠缠。
static NSString *const sVConsoleHookJS =
    @"(function () {"
    @"  if (window.__vcsHooked) return;"
    @"  window.__vcsHooked = true;"
    @"  var MAX = 50000;"
    @"  function post(o) {"
    @"    try { window.webkit.messageHandlers.vconsoleNet.postMessage(JSON.stringify(o)); } catch (e) {}"
    @"  }"
    @"  function trunc(v) {"
    @"    var s = (v == null) ? '' : String(v);"
    @"    if (s.length <= MAX) return s;"
    @"    return s.slice(0, MAX) + '…(H5 已截断，完整内容共 ' + s.length + ' 字符)';"
    @"  }"
    @"  var xo = XMLHttpRequest.prototype;"
    @"  var oOpen = xo.open, oSend = xo.send, oHdr = xo.setRequestHeader;"
    @"  xo.open = function (m, u) {"
    @"    this.__vcs = { m: String(m || 'GET'), u: String(u || ''), h: {}, b: '', t0: performance.now() };"
    @"    return oOpen.apply(this, arguments);"
    @"  };"
    @"  xo.setRequestHeader = function (k, v) {"
    @"    if (this.__vcs) this.__vcs.h[k] = v;"
    @"    return oHdr.apply(this, arguments);"
    @"  };"
    @"  xo.send = function (body) {"
    @"    var x = this, i = x.__vcs;"
    @"    if (i && body != null) i.b = (typeof body === 'string') ? body : String(body);"
    @"    if (i) {"
    @"      x.addEventListener('load', function () {"
    @"        var rh = ''; try { rh = x.getAllResponseHeaders() || ''; } catch (e) {}"
    @"        var rb = '';"
    @"        try {"
    @"          if (x.responseType === '' || x.responseType === 'text') rb = x.responseText;"
    @"          else rb = String(x.response);"
    @"        } catch (e) {}"
    @"        post({ kind: 'xhr', method: i.m, url: (x.responseURL || i.u), reqHeaders: i.h,"
    @"               reqBody: trunc(i.b), status: x.status, respHeaders: rh,"
    @"               respBody: trunc(rb), duration: performance.now() - i.t0 });"
    @"      });"
    @"      x.addEventListener('error', function () {"
    @"        post({ kind: 'xhr', method: i.m, url: i.u, reqHeaders: i.h, reqBody: trunc(i.b),"
    @"               status: 0, error: '网络错误或跨域拦截', duration: performance.now() - i.t0 });"
    @"      });"
    @"    }"
    @"    return oSend.apply(this, arguments);"
    @"  };"
    @"  var oFetch = window.fetch;"
    @"  if (typeof oFetch === 'function') {"
    @"    window.fetch = function (input, init) {"
    @"      var m = 'GET', u = '', rh = {}, bp = null;"
    @"      try {"
    @"        if (input && typeof input === 'object' && input.url) {"
    @"          m = input.method || 'GET';"
    @"          u = input.url;"
    @"          try { input.headers.forEach(function (v, k) { rh[k] = v; }); } catch (e) {}"
    @"          try { bp = input.clone().text(); } catch (e) {}"
    @"        } else {"
    @"          u = String(input);"
    @"          m = (init && init.method) || 'GET';"
    @"          var hs = init && init.headers;"
    @"          if (hs) {"
    @"            if (typeof hs.forEach === 'function') hs.forEach(function (v, k) { rh[k] = v; });"
    @"            else if (typeof hs === 'object') rh = hs;"
    @"          }"
    @"          if (init && init.body != null) {"
    @"            bp = Promise.resolve(typeof init.body === 'string' ? init.body : String(init.body));"
    @"          }"
    @"        }"
    @"      } catch (e) {}"
    @"      var t0 = performance.now();"
    @"      var p = oFetch.apply(window, arguments);"
    @"      p.then(function (resp) {"
    @"        try {"
    @"          var tp;"
    @"          try { tp = resp.clone().text(); } catch (e) { tp = Promise.resolve(''); }"
    @"          var hdr = '';"
    @"          try { resp.headers.forEach(function (v, k) { hdr += k + ': ' + v + '\\n'; }); } catch (e) {}"
    @"          Promise.all([bp || Promise.resolve(''), tp]).then(function (r) {"
    @"            post({ kind: 'fetch', method: m, url: u, reqHeaders: rh,"
    @"                   reqBody: trunc(r[0]), status: resp.status, respHeaders: hdr,"
    @"                   respBody: trunc(r[1]), duration: performance.now() - t0 });"
    @"          }).catch(function () {});"
    @"        } catch (e) {}"
    @"        return resp;"
    @"      }, function (err) {"
    @"        post({ kind: 'fetch', method: m, url: u, reqHeaders: rh, reqBody: '',"
    @"               status: 0, error: String(err), duration: performance.now() - t0 });"
    @"        throw err;"
    @"      });"
    @"      return p;"
    @"    };"
    @"  }"
    @"  var cv = window.console;"
    @"  ['log','info','debug','warn','error'].forEach(function (lv) {"
    @"    var cOrig = cv[lv];"
    @"    cv[lv] = function () {"
    @"      try {"
    @"        var parts = [];"
    @"        for (var i = 0; i < arguments.length; i++) {"
    @"          var a = arguments[i];"
    @"          if (typeof a === 'string') parts.push(a);"
    @"          else if (a == null) parts.push('' + a);"
    @"          else { try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); } }"
    @"        }"
    @"        try { window.webkit.messageHandlers.vconsoleLog.postMessage(JSON.stringify({ kind: 'log', level: lv, text: parts.join(' ') })); } catch (e) {}"
    @"      } catch (e) {}"
    @"      if (cOrig) { try { cOrig.apply(cv, arguments); } catch (e) {} }"
    @"    };"
    @"  });"
    @"})();";

static char sVConsoleDidHookUCCKey; // 关联对象 key：标记某个 UCC 已注入过
static BOOL sVConsoleSwizzled = NO; // swizzle 状态（交换是对合操作，可还原）

#pragma mark - WKWebView 初始化 hook

@interface WKWebView (VConsoleAutoHook)
- (instancetype)vconsole_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration;
@end

@implementation WKWebView (VConsoleAutoHook)

// 交换后的 initWithFrame:configuration: 入口：向 configuration 的
// userContentController 注入钩子脚本与消息通道（同一 UCC 被多个 WebView
// 共享时只注入一次），随后调用原实现。initWithFrame: 便捷初始化器
// 内部也会走到指定初始化器，同样被覆盖。
- (instancetype)vconsole_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    @try {
        WKUserContentController *ucc = configuration.userContentController;
        if (ucc && !objc_getAssociatedObject(ucc, &sVConsoleDidHookUCCKey)) {
            objc_setAssociatedObject(ucc, &sVConsoleDidHookUCCKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            WKUserScript *script = [[WKUserScript alloc] initWithSource:sVConsoleHookJS
                                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                        forMainFrameOnly:NO];
            [ucc addUserScript:script];
            [ucc addScriptMessageHandler:[VConsoleWebViewMonitor shared] name:@"vconsoleNet"];
            [ucc addScriptMessageHandler:[VConsoleWebViewMonitor shared] name:@"vconsoleLog"];
        }
    } @catch (NSException *e) {
        // 注入失败不影响 WebView 正常创建
    }
    return [self vconsole_initWithFrame:frame configuration:configuration];
}

@end

#pragma mark - Monitor 主体

@interface VConsoleWebViewMonitor () <WKScriptMessageHandler>
@end

@implementation VConsoleWebViewMonitor

+ (instancetype)shared {
    static VConsoleWebViewMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VConsoleWebViewMonitor alloc] init];
    });
    return instance;
}

+ (void)attach {
    static BOOL didAttach = NO;
    if (didAttach) return;
    didAttach = YES;
    if ([[VConsoleNetworkLogger shared] isEnabled]) [self start];
    // 跟随「网络抓包」开关动态启停（通知派发在主线程）
    [[NSNotificationCenter defaultCenter] addObserver:[self shared]
                                             selector:@selector(onToggle:)
                                                 name:VConsoleNetworkLoggerDidToggleNotification
                                               object:nil];
}

- (void)onToggle:(NSNotification *)n {
    if ([n.object boolValue]) {
        [VConsoleWebViewMonitor start];
    } else {
        [VConsoleWebViewMonitor stop];
    }
}

+ (void)start {
    if (sVConsoleSwizzled) return;
    Class cls = NSClassFromString(@"WKWebView");
    if (!cls) return; // 无 WebKit 的宿主环境直接跳过
    Method orig = class_getInstanceMethod(cls, @selector(initWithFrame:configuration:));
    Method mine = class_getInstanceMethod(cls, @selector(vconsole_initWithFrame:configuration:));
    if (!orig || !mine) return;
    method_exchangeImplementations(orig, mine);
    sVConsoleSwizzled = YES;
    VConsoleLogI(@"[vConsole] WKWebView 网络监控已开启（attach 之后新建的 WebView 自动生效）");
}

+ (void)stop {
    if (!sVConsoleSwizzled) return;
    Class cls = NSClassFromString(@"WKWebView");
    Method orig = class_getInstanceMethod(cls, @selector(initWithFrame:configuration:));
    Method mine = class_getInstanceMethod(cls, @selector(vconsole_initWithFrame:configuration:));
    if (orig && mine) method_exchangeImplementations(orig, mine);
    sVConsoleSwizzled = NO;
    VConsoleLogI(@"[vConsole] WKWebView 网络监控已关闭");
}

#pragma mark WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSString class]]) return;
    // H5 控制台日志走独立通道，与网络抓包开关同生命周期（WebView 监控开启即生效）
    if ([message.name isEqualToString:@"vconsoleLog"]) {
        [self handleConsoleMessage:message];
        return;
    }
    // 抓包关闭后已注入脚本的页面仍会回传消息，这里运行时放行检查
    if (![[VConsoleNetworkLogger shared] isEnabled]) return;
    VConsoleNetworkEntry *entry = [VConsoleWebViewMonitor entryFromWebJSON:message.body];
    if (entry) [[VConsoleNetworkLogger shared] recordEntry:entry];
}

- (void)handleConsoleMessage:(WKScriptMessage *)message {
    NSData *data = [message.body dataUsingEncoding:NSUTF8StringEncoding];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *o = obj;
    NSString *lv = [o[@"level"] isKindOfClass:[NSString class]] ? o[@"level"] : @"log";
    NSString *text = [o[@"text"] isKindOfClass:[NSString class]] ? o[@"text"] : @"";
    if (text.length == 0) return;
    VConsoleLogLevel level = VConsoleLogLevelInfo;
    if ([lv isEqualToString:@"debug"]) level = VConsoleLogLevelDebug;
    else if ([lv isEqualToString:@"warn"]) level = VConsoleLogLevelWarn;
    else if ([lv isEqualToString:@"error"]) level = VConsoleLogLevelError;
    // log / info 均归为 Info；前缀「· H5」与网络面板的 H5 标记保持一致
    NSString *msg = [@"· H5 " stringByAppendingString:text];
    [[VConsoleLogger shared] log:level message:msg file:NULL function:NULL line:0];
}

#pragma mark JSON → entry 解析（纯逻辑）

+ (nullable VConsoleNetworkEntry *)entryFromWebJSON:(NSString *)json {
    if (json.length == 0) return nil;
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *o = obj;

    VConsoleNetworkEntry *e = [[VConsoleNetworkEntry alloc] init];
    e.fromWeb = YES;
    e.method = [NSString stringWithFormat:@"%@", o[@"method"] ?: @"GET"];
    e.url = [NSString stringWithFormat:@"%@", o[@"url"] ?: @""];

    NSDictionary *reqHeaders = o[@"reqHeaders"];
    if ([reqHeaders isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary<NSString *, NSString *> *h = [NSMutableDictionary dictionary];
        [reqHeaders enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            if (!k || !v) return;
            h[[NSString stringWithFormat:@"%@", k]] = [NSString stringWithFormat:@"%@", v];
        }];
        e.requestHeaders = h;
    }
    if ([o[@"reqBody"] isKindOfClass:[NSString class]]) e.requestBody = o[@"reqBody"];

    e.statusCode = [o[@"status"] integerValue];
    if ([o[@"respHeaders"] isKindOfClass:[NSString class]]) {
        e.responseHeaders = [self parseHeaderLines:o[@"respHeaders"]];
    }
    if ([o[@"respBody"] isKindOfClass:[NSString class]]) {
        e.responseBody = o[@"respBody"];
        e.responseSize = (NSInteger)[o[@"respBody"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    }
    e.durationMs = [o[@"duration"] doubleValue];
    NSDate *end = [NSDate date];
    e.endTime = end;
    // JS 侧只有「完成时刻 + 耗时」，据此倒推开始时间
    e.startTime = [end dateByAddingTimeInterval:-e.durationMs / 1000.0];
    if ([o[@"error"] isKindOfClass:[NSString class]]) e.error = o[@"error"];
    return e;
}

/// 把 XHR getAllResponseHeaders / fetch headers 序列化出的 "k: v" 按行文本解析为头字典
+ (NSDictionary<NSString *, NSString *> *)parseHeaderLines:(NSString *)s {
    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    for (NSString *line in [s componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound || colon.length == line.length) continue;
        NSString *k = [[line substringToIndex:colon.location]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *v = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (k.length == 0) continue;
        out[k] = v;
    }
    return out;
}

@end

#else

// Release 构建：全部空实现，调试能力完全移除
@implementation VConsoleWebViewMonitor

+ (void)attach {}
+ (void)start {}
+ (void)stop {}
+ (instancetype)shared { return nil; }
+ (nullable VConsoleNetworkEntry *)entryFromWebJSON:(NSString *)json { return nil; }

@end

#endif
