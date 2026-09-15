#import "VConsoleCompat.h"
#import "DemoWebViewController.h"
#import <WebKit/WebKit.h>

// 演示页 HTML：属性与 JS 字符串统一用单引号，避免 ObjC 字面量转义。
// api.github.com 返回 Access-Control-Allow-Origin: *，从 loadHTMLString 的
// 空源页面可以读到响应体；example.com 无 CORS 头，用于演示跨域拦截路径。
static NSString *const kDemoHTML =
    @"<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>"
    @"<style>body{font-family:-apple-system;padding:16px;background:#fff;color:#111}"
    @"h3{margin:18px 0 8px;font-size:16px}"
    @"button{display:block;width:100%;padding:12px;margin:8px 0;font-size:16px;"
    @"border-radius:8px;border:0;background:#1cb873;color:#fff}"
    @"button.warn{background:#f0a020}"
    @"button.err{background:#e35d5d}"
    @"#out{word-break:break-all;color:#666;font-size:13px;margin-top:12px;min-height:20px}</style></head>"
    @"<body><h3>WKWebView H5 控制台测试</h3>"
    @"<p style='font-size:14px;color:#666'>页面加载时已自动发出 fetch + XHR。点击下方按钮触发 H5 的 console.* 打印，"
    @"回到 vConsole「日志」面板可看到带「· H5」前缀的记录；网络请求在「网络」面板查看。</p>"
    @"<h3>网络监控</h3>"
    @"<button onclick='fireFetch()'>fetch 请求（github api）</button>"
    @"<button onclick='fireXhr()'>XHR 请求（github api）</button>"
    @"<button onclick='fireCors()'>跨域拦截请求（预期失败）</button>"
    @"<h3>H5 Console 测试</h3>"
    @"<button onclick='fireLog()'>console.log</button>"
    @"<button onclick='fireInfo()'>console.info</button>"
    @"<button onclick='fireDebug()'>console.debug</button>"
    @"<button class='warn' onclick='fireWarn()'>console.warn</button>"
    @"<button class='err' onclick='fireError()'>console.error</button>"
    @"<button onclick='fireObj()'>console.log（对象 / 数组）</button>"
    @"<button onclick='fireAll()'>全部级别各打一条</button>"
    @"<div id='out'></div>"
    @"<script>"
    @"function out(t){document.getElementById('out').textContent=String(t)}"
    @"function fireFetch(){out('fetch 请求中...');"
    @"  fetch('https://api.github.com/zen?src=fetch')"
    @"    .then(function(r){return r.text()})"
    @"    .then(function(t){out('fetch 成功: '+t)})"
    @"    .catch(function(e){out('fetch 失败: '+e)})}"
    @"function fireXhr(){out('XHR 请求中...');"
    @"  var x=new XMLHttpRequest();"
    @"  x.open('GET','https://api.github.com/zen?src=xhr');"
    @"  x.onload=function(){out('XHR 成功: '+x.responseText)};"
    @"  x.onerror=function(){out('XHR 失败（跨域或网络错误）')};"
    @"  x.send()}"
    @"function fireCors(){out('跨域请求中...');"
    @"  fetch('https://example.com/')"
    @"    .then(function(r){out('意外成功: '+r.status)})"
    @"    .catch(function(e){out('预期失败: '+e)})}"
    @"function fireLog(){console.log('这是一条 H5 console.log 示例');out('已打印 console.log')}"
    @"function fireInfo(){console.info('这是一条 H5 console.info 示例');out('已打印 console.info')}"
    @"function fireDebug(){console.debug('这是一条 H5 console.debug 示例');out('已打印 console.debug')}"
    @"function fireWarn(){console.warn('这是一条 H5 console.warn 警告示例');out('已打印 console.warn')}"
    @"function fireError(){console.error('这是一条 H5 console.error 错误示例');out('已打印 console.error')}"
    @"function fireObj(){console.log({name:'vconsole',platform:'iOS',features:['log','network'],nested:{enabled:true,count:42}});out('已打印对象')}"
    @"function fireAll(){console.log('log 级别');console.info('info 级别');console.debug('debug 级别');console.warn('warn 级别');console.error('error 级别');out('已打印全部级别')}"
    @"fireFetch();fireXhr();"
    @"</script></body></html>";

@interface DemoWebViewController ()
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation DemoWebViewController

- (void)fireAllConsole {
    if (self.webView) {
        [self.webView evaluateJavaScript:@"fireAll()" completionHandler:nil];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WKWebView H5 控制台";
    self.view.backgroundColor = VConsoleBackgroundColor();

    // 显式走指定初始化器（initWithFrame:configuration:），
    // 与 VConsoleWebViewMonitor 的 hook 路径完全一致
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];

    [self.webView loadHTMLString:kDemoHTML baseURL:nil];

    // E2E 自动验证（脚本 / CI 用）：启动带 -vcsE2EConsole 时，页面加载后
    // 自动触发全部级别 console.* 打印，宿主侧读取日志面板快照校验 H5 日志是否被捕获。
    if ([[NSProcessInfo processInfo].arguments containsObject:@"-vcsE2EConsole"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:@"fireAll()" completionHandler:nil];
        });
    }
}

@end
