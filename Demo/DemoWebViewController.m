#import "VConsoleCompat.h"
#import "DemoWebViewController.h"
#import <WebKit/WebKit.h>

// 演示页 HTML：属性与 JS 字符串统一用单引号，避免 ObjC 字面量转义。
// api.github.com 返回 Access-Control-Allow-Origin: *，从 loadHTMLString 的
// 空源页面可以读到响应体；example.com 无 CORS 头，用于演示跨域拦截路径。
static NSString *const kDemoHTML =
    @"<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>"
    @"<style>body{font-family:-apple-system;padding:16px;background:#fff;color:#111}"
    @"button{display:block;width:100%;padding:12px;margin:8px 0;font-size:16px;"
    @"border-radius:8px;border:0;background:#1cb873;color:#fff}"
    @"#out{word-break:break-all;color:#666;font-size:13px;margin-top:12px;min-height:20px}</style></head>"
    @"<body><h3>WKWebView 网络监控测试</h3>"
    @"<p style='font-size:14px;color:#666'>页面加载时已自动发出 fetch + XHR；"
    @"按钮可再次触发。回到控制台「网络」面板查看带 H5 标记的记录。</p>"
    @"<button onclick='fireFetch()'>fetch 请求（github api）</button>"
    @"<button onclick='fireXhr()'>XHR 请求（github api）</button>"
    @"<button onclick='fireCors()'>跨域拦截请求（预期失败）</button>"
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
    @"fireFetch();fireXhr();"
    @"</script></body></html>";

@interface DemoWebViewController ()
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation DemoWebViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WKWebView H5";
    self.view.backgroundColor = VConsoleBackgroundColor();

    // 显式走指定初始化器（initWithFrame:configuration:），
    // 与 VConsoleWebViewMonitor 的 hook 路径完全一致
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];

    [self.webView loadHTMLString:kDemoHTML baseURL:nil];
}

@end
