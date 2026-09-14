//
//  TestMain.m
//  vconsole 单元测试（纯逻辑，不依赖 UI）
//  运行方式：bash Tests/run_tests.sh（编译后在 iOS 模拟器内执行）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "VConsoleJSONFormatter.h"
#import "VConsoleLogEntry.h"
#import "VConsoleNetworkEntry.h"
#import "VConsoleMockCenter.h"
#import "VConsoleStorageInspector.h"
#import "VConsoleLogger.h"
#import "VConsoleWebViewMonitor.h"

static int g_failed = 0;
static int g_passed = 0;

#define VCTAssert(cond, name) do { \
    if (cond) { g_passed++; printf("PASS  %s\n", name); } \
    else { g_failed++; printf("FAIL  %s  (%s:%d)\n", name, __FILE__, __LINE__); } \
} while (0)

static void testJSONFormatter(void) {
    // JSON 字符串美化
    NSString *pretty = [VConsoleJSONFormatter prettyBodyIfJSON:@"{\"b\":1,\"a\":2}"];
    VCTAssert(pretty.length > 0 && ![pretty hasPrefix:@"ERROR"], "JSONFormatter: JSON 字符串可美化");
    VCTAssert([pretty rangeOfString:@"\n"].location != NSNotFound, "JSONFormatter: 美化结果含换行缩进");

    // 非 JSON 文本原样返回
    NSString *plain = [VConsoleJSONFormatter prettyBodyIfJSON:@"hello world"];
    VCTAssert([plain isEqualToString:@"hello world"], "JSONFormatter: 纯文本原样返回");

    // 空串安全
    NSString *empty = [VConsoleJSONFormatter prettyBodyIfJSON:@""];
    VCTAssert(empty != nil, "JSONFormatter: 空串不崩溃");
}

static void testLogEntryCache(void) {
    VConsoleLogEntry *e1 = [[VConsoleLogEntry alloc] initWithLevel:VConsoleLogLevelInfo
                                                 message:@"{\"k\":1}"];
    VCTAssert(e1.messageLooksLikeJSON, "LogEntry: JSON 判定为真");
    VCTAssert([e1.displayMessage rangeOfString:@"\n"].location != NSNotFound,
              "LogEntry: JSON 展示文本被美化");
    // 缓存一致性：两次读取返回同一对象
    VCTAssert(e1.displayMessage == e1.displayMessage, "LogEntry: displayMessage 懒加载缓存生效");

    VConsoleLogEntry *e2 = [[VConsoleLogEntry alloc] initWithLevel:VConsoleLogLevelWarn
                                                 message:@"普通文本"];
    VCTAssert(!e2.messageLooksLikeJSON, "LogEntry: 非 JSON 判定为假");
    VCTAssert([e2.displayMessage isEqualToString:@"普通文本"], "LogEntry: 普通文本展示不变");
    VCTAssert([e2.levelName isEqualToString:@"WARN"], "LogEntry: 级别名正确");
}

static void testNetworkEntryText(void) {
    VConsoleNetworkEntry *e = [[VConsoleNetworkEntry alloc] init];
    e.statusCode = 200;
    e.durationMs = 1234.5;
    VCTAssert([[e statusText] isEqualToString:@"200"], "NetworkEntry: 状态文本");
    VCTAssert([[e durationText] isEqualToString:@"1235 ms"], "NetworkEntry: 耗时文本取整");
    VCTAssert([e statusText] == [e statusText], "NetworkEntry: statusText 缓存生效");

    VConsoleNetworkEntry *m = [[VConsoleNetworkEntry alloc] init];
    m.statusCode = 200;
    m.mocked = YES;
    VCTAssert([[m statusText] isEqualToString:@"200 · MOCK"], "NetworkEntry: mocked 状态带 MOCK 标记");

    VConsoleNetworkEntry *err = [[VConsoleNetworkEntry alloc] init];
    err.error = @"timeout";
    VCTAssert([[err statusText] isEqualToString:@"ERROR"], "NetworkEntry: 错误状态文本");
}

static void testCurlBuilder(void) {
    VConsoleNetworkEntry *e = [[VConsoleNetworkEntry alloc] init];
    e.method = @"POST";
    e.url = @"https://api.example.com/v1/user's/profile";
    e.requestHeaders = @{@"Content-Type": @"application/json",
                         @"Accept-Encoding": @"gzip",
                         @"Content-Length": @"18",
                         @"X-Token": @"abc123"};
    e.requestBody = @"{\"name\":\"it's me\"}";
    NSString *curl = [e curlCommand];

    VCTAssert([curl hasPrefix:@"curl -X POST "], "cURL: 以方法开头");
    // POSIX 单引号内 \' 不是合法转义（复制到终端会 unmatched quote），
    // 正确惯用法是 '\''（闭引号 + 转义引号 + 重开引号）
    VCTAssert([curl rangeOfString:@"user'\\''s"].location != NSNotFound, "cURL: URL 单引号已转义");
    VCTAssert([curl rangeOfString:@"-H 'Content-Type: application/json'"].location != NSNotFound,
              "cURL: 保留 Content-Type");
    VCTAssert([curl rangeOfString:@"Accept-Encoding"].location == NSNotFound,
              "cURL: 跳过 Accept-Encoding");
    VCTAssert([curl rangeOfString:@"Content-Length"].location == NSNotFound,
              "cURL: 跳过 Content-Length");
    VCTAssert([curl rangeOfString:@"--data-raw '"].location != NSNotFound, "cURL: body 用 --data-raw");
    VCTAssert([curl rangeOfString:@"it'\\''s"].location != NSNotFound, "cURL: body 单引号已转义");
}

static void testWebViewMonitorParse(void) {
    // JS 钩子回传的 JSON → VConsoleNetworkEntry 解析（与注入脚本的消息格式一一对应）
    NSString *json = @"{\"kind\":\"xhr\",\"method\":\"POST\",\"url\":\"https://api.example.com/v1/a\","
        "\"reqHeaders\":{\"X-Token\":\"abc\"},\"reqBody\":\"{\\\"k\\\":1}\",\"status\":200,"
        "\"respHeaders\":\"Content-Type: application/json\\r\\nX-B: 2\\r\\n\","
        "\"respBody\":\"ok\",\"duration\":87.6}";
    VConsoleNetworkEntry *e = [VConsoleWebViewMonitor entryFromWebJSON:json];
    VCTAssert(e != nil, "WebView: JSON 可解析为 entry");
    VCTAssert(e.fromWeb, "WebView: entry 标记来自 H5");
    VCTAssert([e.method isEqualToString:@"POST"], "WebView: 方法解析正确");
    VCTAssert([e.url isEqualToString:@"https://api.example.com/v1/a"], "WebView: URL 解析正确");
    VCTAssert([e.requestHeaders[@"X-Token"] isEqualToString:@"abc"], "WebView: 请求头解析正确");
    VCTAssert(e.statusCode == 200, "WebView: 状态码解析正确");
    VCTAssert([e.responseHeaders count] == 2
              && [e.responseHeaders[@"Content-Type"] isEqualToString:@"application/json"],
              "WebView: 响应头按行解析为字典");
    VCTAssert([e.responseBody isEqualToString:@"ok"], "WebView: 响应体解析正确");
    VCTAssert(e.responseSize == 2, "WebView: 响应大小按 UTF8 字节计算");
    VCTAssert([[e durationText] isEqualToString:@"88 ms"], "WebView: JS 耗时解析并取整");
    VCTAssert([[e statusText] hasSuffix:@"200 · H5"], "WebView: 状态文本带 H5 标记");
    VCTAssert(!e.error, "WebView: 成功请求无错误信息");

    // 失败请求（CORS / 网络错误）：status=0 + error
    VConsoleNetworkEntry *err = [VConsoleWebViewMonitor entryFromWebJSON:
        @"{\"kind\":\"fetch\",\"method\":\"GET\",\"url\":\"https://x.com/\","
        "\"status\":0,\"error\":\"Load failed\",\"duration\":12.3}"];
    VCTAssert([err.error isEqualToString:@"Load failed"], "WebView: 错误信息解析正确");
    VCTAssert([[err statusText] isEqualToString:@"ERROR · H5"], "WebView: 失败状态显示 ERROR");

    // 非法输入安全返回 nil
    VCTAssert([VConsoleWebViewMonitor entryFromWebJSON:@"not json"] == nil, "WebView: 非 JSON 返回 nil");
    VCTAssert([VConsoleWebViewMonitor entryFromWebJSON:@""] == nil, "WebView: 空串返回 nil");
}

static void testMockCenterLookup(void) {
    // 构造临时 mock 目录
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vcstest-mock"];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];

    // 第 1 级：action 独立文件
    [@"{\"from\":\"action-file\"}" writeToFile:[dir stringByAppendingPathComponent:@"getUserInfo.json"]
                                    atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // 第 2 级：模块文件（action 为 key）
    [@"{\"initSurveyInfo\": {\"from\":\"module-file\"}}"
      writeToFile:[dir stringByAppendingPathComponent:@"ECarSurveyAction.json"]
      atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // 第 3 级：全局 mock.json（嵌套 + 扁平兜底）
    [@"{\"ECarLossAction\": {\"getCarLoss\": {\"from\":\"global-nested\"}}, \"flatAction\": {\"from\":\"global-flat\"}}"
      writeToFile:[dir stringByAppendingPathComponent:@"mock.json"]
      atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<NSString *> *dirs = @[dir];
    NSURL *url = [NSURL URLWithString:@"https://api.example.com/api/ECarSurveyAction/initSurveyInfo"];

    // 模块文件命中
    VConsoleMockResult *r1 = [VConsoleMockCenter lookupForURL:url searchDirectories:dirs];
    VCTAssert(r1 != nil, "Mock: 模块文件命中");
    VCTAssert([r1.module isEqualToString:@"ECarSurveyAction"] && [r1.action isEqualToString:@"initSurveyInfo"],
              "Mock: module/action 解析正确");
    NSString *b1 = [[NSString alloc] initWithData:r1.data encoding:NSUTF8StringEncoding];
    VCTAssert([b1 containsString:@"module-file"], "Mock: 返回模块文件中该 action 的响应");

    // action 独立文件命中（优先级高于模块文件）
    VConsoleMockResult *r2 = [VConsoleMockCenter lookupForURL:
                         [NSURL URLWithString:@"https://api.example.com/api/anything/getUserInfo"]
                                       searchDirectories:dirs];
    VCTAssert(r2 != nil, "Mock: action 独立文件命中");
    NSString *b2 = [[NSString alloc] initWithData:r2.data encoding:NSUTF8StringEncoding];
    VCTAssert([b2 containsString:@"action-file"], "Mock: action 文件整文件即响应");

    // 全局嵌套结构命中
    VConsoleMockResult *r3 = [VConsoleMockCenter lookupForURL:
                         [NSURL URLWithString:@"https://api.example.com/api/ECarLossAction/getCarLoss"]
                                       searchDirectories:dirs];
    VCTAssert(r3 != nil, "Mock: 全局 mock.json 嵌套命中");
    NSString *b3 = [[NSString alloc] initWithData:r3.data encoding:NSUTF8StringEncoding];
    VCTAssert([b3 containsString:@"global-nested"], "Mock: 返回全局嵌套响应");

    // 全局扁平结构兜底
    VConsoleMockResult *r4 = [VConsoleMockCenter lookupForURL:
                         [NSURL URLWithString:@"https://api.example.com/api/SomeModule/flatAction"]
                                       searchDirectories:dirs];
    VCTAssert(r4 != nil, "Mock: 全局扁平结构兜底命中");

    // 未命中
    VConsoleMockResult *r5 = [VConsoleMockCenter lookupForURL:
                         [NSURL URLWithString:@"https://api.example.com/api/none/notExist"]
                                       searchDirectories:dirs];
    VCTAssert(r5 == nil, "Mock: 未命中返回 nil");

    // 清理
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

static void testStorageInspector(void) {
    // describeValue 对常见类型不崩溃且产出可读文本
    NSString *s = [VConsoleStorageInspector describeValue:@"hello"];
    VCTAssert([s length] > 0, "StorageInspector: 字符串描述非空");
    NSString *n = [VConsoleStorageInspector describeValue:@(42)];
    VCTAssert([n length] > 0, "StorageInspector: 数值描述非空");
    NSString *a = [VConsoleStorageInspector describeValue:@[@1, @2, @3]];
    VCTAssert([a length] > 0, "StorageInspector: 数组描述非空");
    NSString *d = [VConsoleStorageInspector describeValue:@{@"k": @"v"}];
    VCTAssert([d length] > 0, "StorageInspector: 字典描述非空");

    // UserDefaults 列举（plist 结构）
    [[NSUserDefaults standardUserDefaults] setObject:@"vcstest" forKey:@"vcs.test.key"];
    NSArray *items = [[VConsoleStorageInspector shared] userDefaultsItems];
    BOOL found = NO;
    for (NSDictionary *item in items) {
        if ([item[@"key"] isEqualToString:@"vcs.test.key"]) found = YES;
    }
    VCTAssert(found, "StorageInspector: userDefaultsItems 含测试 key");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"vcs.test.key"];
}

static void testLoggerLevelFilter(void) {
    VConsoleLogLevel old = [[VConsoleLogger shared] levelFilter];
    [[VConsoleLogger shared] setLevelFilter:VConsoleLogLevelWarn];
    VCTAssert([[VConsoleLogger shared] levelFilter] == VConsoleLogLevelWarn, "Logger: 级别过滤读写一致");
    [[VConsoleLogger shared] setLevelFilter:old];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // simctl spawn 下 stdout 非 tty 为块缓冲，改为无缓冲便于实时观察进度
        setvbuf(stdout, NULL, _IONBF, 0);
        printf("=== vconsole unit tests ===\n");
        testJSONFormatter();
        testLogEntryCache();
        testNetworkEntryText();
        testCurlBuilder();
        testWebViewMonitorParse();
        testMockCenterLookup();
        testStorageInspector();
        testLoggerLevelFilter();
        printf("\n%d passed, %d failed\n", g_passed, g_failed);
        return (g_failed == 0) ? 0 : 1;
    }
}
