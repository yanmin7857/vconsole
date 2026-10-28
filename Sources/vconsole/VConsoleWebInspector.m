#import "VConsoleCompat.h"
#import "VConsoleWebInspector.h"
#import <objc/runtime.h>

/// 关联对象 key：登记顺序（创建先后），用于 liveWebViews 的稳定排序。
static char sVConsoleWebViewOrderKey;

/// 弱引用表 + 互斥锁：init 可能在任意线程发生，列表读取在主线程。
static NSHashTable<WKWebView *> *sVConsoleWebViewTable = nil;
static NSUInteger sVConsoleWebViewCounter = 0;
static NSLock *sVConsoleWebViewLock = nil;

/// JS 结果文本的展示上限，超过则截断（与网络面板 body 截断同源，避免面板被大 HTML 撑爆）。
static const NSUInteger kVConsoleWebOutputMaxChars = 20000;

/// 把 evaluateJavaScript 的回调值转成可展示文本
static NSString *VConsoleStringifyJSResult(id result) {
    if (result == nil || result == [NSNull null]) return @"(null)";
    if ([result isKindOfClass:[NSString class]]) return result;
    if ([result isKindOfClass:[NSNumber class]]) return [result stringValue];
    if ([NSJSONSerialization isValidJSONObject:result]) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:result
                                                    options:NSJSONWritingPrettyPrinted
                                                      error:nil];
        if (d) return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
    }
    return [result description] ?: @"";
}

/// 截断过长文本并附上原始长度提示
static NSString *VConsoleTruncateOutput(NSString *text) {
    if (text.length <= kVConsoleWebOutputMaxChars) return text;
    return [NSString stringWithFormat:@"%@\n…（已截断，完整内容共 %lu 字符）",
            [text substringToIndex:kVConsoleWebOutputMaxChars], (unsigned long)text.length];
}

@implementation VConsoleWebInspector

#pragma mark - 实例跟踪

+ (void)registerWebView:(WKWebView *)webView {
    if (!webView) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // weakObjectsHashTable：不持有 WebView，实例释放后自动从表中消失
        sVConsoleWebViewTable = [NSHashTable weakObjectsHashTable];
        sVConsoleWebViewLock = [[NSLock alloc] init];
    });
    [sVConsoleWebViewLock lock];
    if (![sVConsoleWebViewTable containsObject:webView]) {
        objc_setAssociatedObject(webView, &sVConsoleWebViewOrderKey,
                                 @(sVConsoleWebViewCounter++), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sVConsoleWebViewTable addObject:webView];
    }
    [sVConsoleWebViewLock unlock];
}

+ (NSArray<WKWebView *> *)liveWebViews {
    if (!sVConsoleWebViewTable) return @[];
    [sVConsoleWebViewLock lock];
    NSArray<WKWebView *> *all = sVConsoleWebViewTable.allObjects;
    [sVConsoleWebViewLock unlock];
    return [all sortedArrayUsingComparator:^NSComparisonResult(WKWebView *a, WKWebView *b) {
        NSUInteger oa = [objc_getAssociatedObject(a, &sVConsoleWebViewOrderKey) unsignedIntegerValue];
        NSUInteger ob = [objc_getAssociatedObject(b, &sVConsoleWebViewOrderKey) unsignedIntegerValue];
        if (oa < ob) return NSOrderedAscending;
        if (oa > ob) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

#pragma mark - JS / DOM

+ (void)evaluateScript:(NSString *)js
             inWebView:(WKWebView *)webView
            completion:(void (^)(NSString *result))completion {
    void (^finish)(NSString *) = ^(NSString *text) {
        if (completion) completion(text ?: @"");
    };
    if (js.length == 0) { finish(@"❌ 脚本为空"); return; }
    if (!webView) { finish(@"❌ 未选择 WebView"); return; }
    // WKWebView 的 JS 执行需在主线程发起，回调也在主线程
    dispatch_async(dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
            if (error) {
                finish([NSString stringWithFormat:@"❌ %@", error.localizedDescription]);
            } else {
                finish(VConsoleTruncateOutput(VConsoleStringifyJSResult(result)));
            }
        }];
    });
}

+ (void)fetchPageInfoForWebView:(WKWebView *)webView
                     completion:(void (^)(NSString *info))completion {
    NSString *js =
        @"(function () {"
        @"  try {"
        @"    return JSON.stringify({"
        @"      title: document.title || '',"
        @"      url: location.href || '',"
        @"      readyState: document.readyState || '',"
        @"      elements: document.getElementsByTagName('*').length"
        @"    }, null, 2);"
        @"  } catch (e) { return '❌ ' + e.message; }"
        @"})();";
    [self evaluateScript:js inWebView:webView completion:^(NSString *result) {
        if (completion) completion(result);
    }];
}

#pragma mark - 缓存

+ (void)clearDataTypes:(NSSet<NSString *> *)dataTypes
            completion:(void (^)(void))completion {
    if (dataTypes.count == 0) {
        if (completion) completion();
        return;
    }
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    // modifiedSince 取 1970，等价于「清空该类型全部数据」
    [store removeDataOfTypes:dataTypes
               modifiedSince:[NSDate dateWithTimeIntervalSince1970:0]
           completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion();
        });
    }];
}

@end
