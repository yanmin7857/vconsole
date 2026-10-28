#import "VConsoleCompat.h"
#import "VConsoleWebViewController.h"
#import "VConsoleWebInspector.h"
#import "VConsoleToast.h"
#import "VConsoleUICommon.h"
#import <WebKit/WebKit.h>

/// 面板行高
static const CGFloat kVConsoleWebRowHeight = 30;
/// 快捷操作 chips 行高
static const CGFloat kVConsoleWebChipRowHeight = 32;

/// 把字符串转成安全的 JS 字面量（含引号/反斜杠转义），用于把用户输入的选择器拼进脚本
static NSString *VConsoleJSStringLiteral(NSString *s) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[s ?: @""] options:0 error:nil];
    NSString *arr = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"[\"\"]";
    // arr 形如 ["..."]，去掉首尾方括号即得字面量
    if (arr.length >= 2) return [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
    return @"\"\"";
}

/// chips 样式：圆角胶囊按钮
static UIButton *VConsoleMakeChipButton(NSString *title, id target, SEL action) {
    UIButton *b;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.title = title;
        cfg.baseForegroundColor = VConsoleBlueColor();
        cfg.background.backgroundColor = VConsoleTertiarySystemFillColor();
        cfg.background.cornerRadius = 8;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(5, 12, 5, 12);
        cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
            NSMutableDictionary *out = [incoming mutableCopy];
            out[NSFontAttributeName] = VConsoleScaledFont(13, UIFontWeightMedium);
            return out;
        };
        b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
    } else {
        b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font = VConsoleScaledFont(13, UIFontWeightMedium);
        b.tintColor = VConsoleBlueColor();
        b.backgroundColor = VConsoleTertiarySystemFillColor();
        b.contentEdgeInsets = UIEdgeInsetsMake(5, 12, 5, 12);
        b.layer.cornerRadius = 8;
    }
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

@interface VConsoleWebViewController ()
@property (nonatomic, strong) UIButton *targetButton;
@property (nonatomic, strong) UIButton *refreshButton;
@property (nonatomic, strong) UITextField *jsField;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UITextView *outputView;
/// 当前选中的目标（弱引用：WebView 释放后自动失效，由 refresh 重新选一个）
@property (nonatomic, weak, nullable) WKWebView *selectedWebView;
@property (nonatomic, strong) NSDateFormatter *timeFormatter;
@end

@implementation VConsoleWebViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VConsoleBackgroundColor();

    _timeFormatter = [[NSDateFormatter alloc] init];
    _timeFormatter.dateFormat = @"HH:mm:ss";

    // 目标选择行：目标按钮（左侧，占满剩余宽度）+ 刷新按钮
    _targetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _targetButton.translatesAutoresizingMaskIntoConstraints = NO;
    _targetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _targetButton.titleLabel.font = VConsoleScaledFont(13, UIFontWeightMedium);
    [_targetButton setTitleColor:VConsoleLabelColor() forState:UIControlStateNormal];
    [_targetButton addTarget:self action:@selector(targetTapped) forControlEvents:UIControlEventTouchUpInside];
    _targetButton.isAccessibilityElement = YES;
    _targetButton.accessibilityLabel = @"目标 WebView";
    _targetButton.accessibilityHint = @"轻点切换要操作的 WebView";
    [self.view addSubview:_targetButton];

    _refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_refreshButton setImage:VConsoleImageNamed(@"arrow.clockwise") forState:UIControlStateNormal];
    _refreshButton.tintColor = VConsoleBlueColor();
    [_refreshButton addTarget:self action:@selector(refresh) forControlEvents:UIControlEventTouchUpInside];
    _refreshButton.isAccessibilityElement = YES;
    _refreshButton.accessibilityLabel = @"刷新 WebView 列表";
    [self.view addSubview:_refreshButton];

    // 快捷操作 chips（横向可滚动）
    UIScrollView *chipScroll = [[UIScrollView alloc] init];
    chipScroll.translatesAutoresizingMaskIntoConstraints = NO;
    chipScroll.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:chipScroll];

    UIStackView *chipStack = [[UIStackView alloc] init];
    chipStack.axis = UILayoutConstraintAxisHorizontal;
    chipStack.spacing = 8;
    chipStack.translatesAutoresizingMaskIntoConstraints = NO;
    [chipScroll addSubview:chipStack];

    NSArray<NSArray<NSString *> *> *chips = @[
        @[@"页面信息", NSStringFromSelector(@selector(actPageInfo))],
        @[@"取 HTML", NSStringFromSelector(@selector(actGetHTML))],
        @[@"取文本", NSStringFromSelector(@selector(actGetText))],
        @[@"查询选择器", NSStringFromSelector(@selector(actQuery))],
        @[@"高亮元素", NSStringFromSelector(@selector(actHighlight))],
        @[@"取消高亮", NSStringFromSelector(@selector(actClearHighlight))],
        @[@"清缓存", NSStringFromSelector(@selector(actClearCache))],
        @[@"清空输出", NSStringFromSelector(@selector(actClearOutput))],
    ];
    for (NSArray<NSString *> *c in chips) {
        [chipStack addArrangedSubview:VConsoleMakeChipButton(c[0], self, NSSelectorFromString(c[1]))];
    }

    // JS 输入行
    _jsField = [[UITextField alloc] init];
    _jsField.translatesAutoresizingMaskIntoConstraints = NO;
    _jsField.placeholder = @"输入 JS 后回车执行，如 document.title";
    _jsField.font = [UIFont systemFontOfSize:13];
    _jsField.borderStyle = UITextBorderStyleRoundedRect;
    _jsField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _jsField.autocorrectionType = UITextAutocorrectionTypeNo;
    _jsField.returnKeyType = UIReturnKeyGo;
    [_jsField addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventEditingDidEndOnExit];
    [self.view addSubview:_jsField];

    _runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _runButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_runButton setTitle:@"执行" forState:UIControlStateNormal];
    _runButton.titleLabel.font = VConsoleScaledFont(13, UIFontWeightSemibold);
    [_runButton setTitleColor:VConsoleBlueColor() forState:UIControlStateNormal];
    [_runButton addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_runButton];

    // 输出区（只读、可选中复制）
    _outputView = [[UITextView alloc] init];
    _outputView.translatesAutoresizingMaskIntoConstraints = NO;
    _outputView.editable = NO;
    _outputView.font = VConsoleScaledMonospaceFont(11);
    _outputView.textColor = VConsoleLabelColor();
    _outputView.backgroundColor = VConsoleSecondaryBackgroundColor();
    _outputView.layer.cornerRadius = 8;
    _outputView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    _outputView.text = @"选择目标 WebView 后，可执行 JS 操作页面 DOM。\n";
    [self.view addSubview:_outputView];

    // 约束
    [_targetButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6].active = YES;
    [_targetButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12].active = YES;
    [_targetButton.heightAnchor constraintEqualToConstant:kVConsoleWebRowHeight].active = YES;
    [_refreshButton.centerYAnchor constraintEqualToAnchor:_targetButton.centerYAnchor].active = YES;
    [_refreshButton.leadingAnchor constraintEqualToAnchor:_targetButton.trailingAnchor constant:6].active = YES;
    [_refreshButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12].active = YES;
    [_refreshButton.widthAnchor constraintEqualToConstant:32].active = YES;

    [chipScroll.topAnchor constraintEqualToAnchor:_targetButton.bottomAnchor constant:6].active = YES;
    [chipScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [chipScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [chipScroll.heightAnchor constraintEqualToConstant:kVConsoleWebChipRowHeight].active = YES;
    [chipStack.topAnchor constraintEqualToAnchor:chipScroll.topAnchor].active = YES;
    [chipStack.bottomAnchor constraintEqualToAnchor:chipScroll.bottomAnchor].active = YES;
    [chipStack.leadingAnchor constraintEqualToAnchor:chipScroll.leadingAnchor constant:12].active = YES;
    [chipStack.trailingAnchor constraintEqualToAnchor:chipScroll.trailingAnchor constant:-12].active = YES;
    [chipStack.heightAnchor constraintEqualToAnchor:chipScroll.heightAnchor].active = YES;

    [_jsField.topAnchor constraintEqualToAnchor:chipScroll.bottomAnchor constant:6].active = YES;
    [_jsField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12].active = YES;
    [_jsField.heightAnchor constraintEqualToConstant:34].active = YES;
    [_runButton.centerYAnchor constraintEqualToAnchor:_jsField.centerYAnchor].active = YES;
    [_runButton.leadingAnchor constraintEqualToAnchor:_jsField.trailingAnchor constant:6].active = YES;
    [_runButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12].active = YES;
    [_runButton.widthAnchor constraintEqualToConstant:48].active = YES;

    [_outputView.topAnchor constraintEqualToAnchor:_jsField.bottomAnchor constant:6].active = YES;
    [_outputView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12].active = YES;
    [_outputView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12].active = YES;
    [_outputView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-8].active = YES;

    [self refresh];
}

#pragma mark - 目标选择

/// 当前存活的目标列表（每次实时读取，避免面板强持有 WebView 使其无法释放）
- (NSArray<WKWebView *> *)currentWebViews {
    return [VConsoleWebInspector liveWebViews];
}

- (void)refresh {
    NSArray<WKWebView *> *list = [self currentWebViews];
    // 选中的目标已被释放 → 回落到第一个
    if (self.selectedWebView && ![list containsObject:self.selectedWebView]) {
        self.selectedWebView = nil;
    }
    if (!self.selectedWebView) self.selectedWebView = list.firstObject;
    [self updateTargetButton];
}

- (void)updateTargetButton {
    NSArray<WKWebView *> *list = [self currentWebViews];
    if (list.count == 0) {
        [self.targetButton setTitle:@"无 WebView（点击刷新）" forState:UIControlStateNormal];
        [self.targetButton setTitleColor:VConsoleSecondaryLabelColor() forState:UIControlStateNormal];
        return;
    }
    NSUInteger idx = [list indexOfObject:self.selectedWebView];
    if (idx == NSNotFound) idx = 0;
    NSString *host = list[idx].URL.host ?: @"about:blank";
    NSString *title = [NSString stringWithFormat:@"目标：WebView %lu · %@  ▾",
                       (unsigned long)(idx + 1), host];
    [self.targetButton setTitle:title forState:UIControlStateNormal];
    [self.targetButton setTitleColor:VConsoleLabelColor() forState:UIControlStateNormal];
}

- (void)targetTapped {
    NSArray<WKWebView *> *list = [self currentWebViews];
    if (list.count == 0) {
        [self toast:@"当前没有存活的 WebView"];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择目标 WebView"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger i = 0; i < list.count; i++) {
        __weak WKWebView *wv = list[i];
        NSString *host = wv.URL.host ?: @"about:blank";
        NSString *title = [NSString stringWithFormat:@"WebView %lu · %@", (unsigned long)(i + 1), host];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            __strong typeof(weakSelf) self_ = weakSelf;
            [self_ setSelectedTarget:wv];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // iPad 需指明 popover 锚点
    sheet.popoverPresentationController.sourceView = self.targetButton;
    sheet.popoverPresentationController.sourceRect = self.targetButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)setSelectedTarget:(nullable WKWebView *)webView {
    self.selectedWebView = webView;
    [self updateTargetButton];
}

/// 取当前目标；无目标时提示并返回 nil
- (nullable WKWebView *)resolveTarget {
    if (!self.selectedWebView) {
        NSArray<WKWebView *> *list = [self currentWebViews];
        self.selectedWebView = list.firstObject;
    }
    if (!self.selectedWebView) {
        [self toast:@"请先打开一个 WKWebView"];
        return nil;
    }
    return self.selectedWebView;
}

#pragma mark - 快捷操作

- (void)actPageInfo {
    WKWebView *wv = [self resolveTarget];
    if (!wv) return;
    __weak typeof(self) weakSelf = self;
    [VConsoleWebInspector fetchPageInfoForWebView:wv completion:^(NSString *info) {
        [weakSelf appendOutput:@"页面信息" body:info];
    }];
}

- (void)actGetHTML {
    [self runScript:@"document.documentElement ? document.documentElement.outerHTML : ''" title:@"取 HTML"];
}

- (void)actGetText {
    [self runScript:@"document.body ? document.body.innerText : ''" title:@"取文本"];
}

- (void)actQuery {
    __weak typeof(self) weakSelf = self;
    [self promptForSelectorWithTitle:@"查询元素" completion:^(NSString *sel) {
        NSString *js = [NSString stringWithFormat:
            @"(function(){"
            @"  try {"
            @"    var list = document.querySelectorAll(%@);"
            @"    if (!list.length) return '未匹配到元素：' + %@;"
            @"    var html = list[0].outerHTML || '';"
            @"    if (html.length > 500) html = html.slice(0, 500) + '…';"
            @"    return '匹配 ' + list.length + ' 个元素\\n第一个：' + html;"
            @"  } catch (e) { return '❌ ' + e.message; }"
            @"})();",
            VConsoleJSStringLiteral(sel), VConsoleJSStringLiteral(sel)];
        [weakSelf runScript:js title:[NSString stringWithFormat:@"查询 %@", sel]];
    }];
}

- (void)actHighlight {
    __weak typeof(self) weakSelf = self;
    [self promptForSelectorWithTitle:@"高亮元素" completion:^(NSString *sel) {
        NSString *js = [NSString stringWithFormat:
            @"(function(){"
            @"  try {"
            @"    var old = document.querySelectorAll('[data-vcs-hl]');"
            @"    for (var i = 0; i < old.length; i++) { old[i].style.outline = ''; old[i].removeAttribute('data-vcs-hl'); }"
            @"    var list = document.querySelectorAll(%@);"
            @"    for (var j = 0; j < list.length; j++) { list[j].style.outline = '2px solid #e35d5d'; list[j].setAttribute('data-vcs-hl', '1'); }"
            @"    return '已高亮 ' + list.length + ' 个元素：' + %@;"
            @"  } catch (e) { return '❌ ' + e.message; }"
            @"})();",
            VConsoleJSStringLiteral(sel), VConsoleJSStringLiteral(sel)];
        [weakSelf runScript:js title:[NSString stringWithFormat:@"高亮 %@", sel]];
    }];
}

- (void)actClearHighlight {
    [self runScript:
        @"(function(){"
        @"  var old = document.querySelectorAll('[data-vcs-hl]');"
        @"  for (var i = 0; i < old.length; i++) { old[i].style.outline = ''; old[i].removeAttribute('data-vcs-hl'); }"
        @"  return '已清除 ' + old.length + ' 处高亮';"
        @"})();" title:@"取消高亮"];
}

- (void)actClearOutput {
    self.outputView.text = @"";
}

- (void)actClearCache {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"清除 WebView 缓存"
                                                                  message:@"所有 WebView 共用一个数据存储，清除后需重新加载页面。"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    void (^add)(NSString *, NSSet<NSString *> *) = ^(NSString *title, NSSet<NSString *> *types) {
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [weakSelf clearDataTypes:types title:title];
        }]];
    };
    add(@"全部网站数据（含 Cookie）", [WKWebsiteDataStore allWebsiteDataTypes]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    add(@"仅缓存（保留 Cookie / 登录态）",
        [NSSet setWithObjects:WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                               WKWebsiteDataTypeOfflineWebApplicationCache, nil]);
#pragma clang diagnostic pop
    add(@"仅 Cookie（保留缓存）", [NSSet setWithObject:WKWebsiteDataTypeCookies]);
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2,
                                                                self.view.bounds.size.height / 3, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)clearDataTypes:(NSSet<NSString *> *)types title:(NSString *)title {
    __weak typeof(self) weakSelf = self;
    [VConsoleWebInspector clearDataTypes:types completion:^{
        VConsoleHapticWarning();
        [weakSelf toast:[NSString stringWithFormat:@"已清除：%@", title]];
        [weakSelf appendOutput:title body:@"✅ 清理完成（页面可能需要重新加载）"];
    }];
}

#pragma mark - JS 执行

- (void)runTapped {
    NSString *js = [self.jsField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (js.length == 0) return;
    [self runScript:js title:js];
}

- (void)runScript:(NSString *)js title:(NSString *)title {
    WKWebView *wv = [self resolveTarget];
    if (!wv) return;
    __weak typeof(self) weakSelf = self;
    [VConsoleWebInspector evaluateScript:js inWebView:wv completion:^(NSString *result) {
        [weakSelf appendOutput:title body:result];
    }];
}

- (void)promptForSelectorWithTitle:(NSString *)title completion:(void (^)(NSString *selector))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:@"输入 CSS 选择器，如 #app .item"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"CSS 选择器";
        tf.font = [UIFont systemFontOfSize:14];
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak UIAlertController *weakAlert = alert; // 避免 alert → action → block → alert 循环引用
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *sel = weakAlert.textFields.firstObject.text ?: @"";
        sel = [sel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (sel.length == 0) return;
        if (completion) completion(sel);
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 输出

- (void)appendOutput:(NSString *)title body:(NSString *)body {
    NSString *ts = [self.timeFormatter stringFromDate:[NSDate date]];
    NSString *block = [NSString stringWithFormat:@"▸ %@  %@\n%@\n\n", title ?: @"", ts, body ?: @""];
    NSString *text = [self.outputView.text stringByAppendingString:block];
    self.outputView.text = text;
    // 滚动到底部，保证最新结果可见
    if (text.length > 0) {
        [self.outputView scrollRangeToVisible:NSMakeRange(text.length - 1, 1)];
    }
}

- (void)toast:(NSString *)msg {
    [VConsoleToast showInView:self.view message:msg];
}

@end
