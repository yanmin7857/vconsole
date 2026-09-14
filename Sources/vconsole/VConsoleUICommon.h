#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 面板通用空态占位视图：SF Symbol 图标 + 主标题 + 副标题。
/// 供日志/网络/存储列表在无数据或无匹配结果时展示。
@interface VConsoleEmptyStateView : UIView

- (instancetype)initWithSymbol:(nullable NSString *)symbol
                         title:(NSString *)title
                      subtitle:(NSString *)subtitle;

- (void)configureSymbol:(nullable NSString *)symbol
                  title:(NSString *)title
               subtitle:(NSString *)subtitle;

@end

/// 轻触觉：切 Tab、点筛选 chip 等轻量确认
void VConsoleHapticLight(void);
/// 警告触觉：清空数据等破坏性操作
void VConsoleHapticWarning(void);
/// 成功触觉：复制完成等结果反馈
void VConsoleHapticSuccess(void);

/// NSUserDefaults 键：慢请求阈值（毫秒）。与 VConsoleDefaultsKey* 系列命名保持一致。
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeySlowThresholdMs;   // double: 慢请求阈值(ms)

/// 慢请求阈值被改写时派发（主线程）。网络页据此刷新 chip 标题与慢请求标记。
/// 用通知而不是 viewWillAppear：网络页是面板里的子 VC，present 设置页时不一定收到
/// viewWillAppear，子 VC 也不会自动转发，靠 viewWillAppear 会漏刷新。
FOUNDATION_EXPORT NSString * const VConsoleSlowThresholdDidChangeNotification;

/// 读取慢请求阈值（毫秒）。从未持久化过时返回默认 1000 ms。
NSTimeInterval VConsoleSlowRequestThresholdMs(void);
/// 写入慢请求阈值（毫秒）。非法值（<= 0）回落到默认 1000 ms。
void VConsoleSetSlowRequestThresholdMs(NSTimeInterval ms);

/// 网络列表排序方式
typedef NS_ENUM(NSInteger, VConsoleNetworkSortMode) {
    VConsoleNetworkSortModeDefault  = 0,  // 按发生顺序（默认，保持原有行为）
    VConsoleNetworkSortModeDuration = 1,  // 耗时降序
    VConsoleNetworkSortModeSize     = 2,  // 响应大小降序
    VConsoleNetworkSortModeStatus   = 3,  // 状态码降序（5xx/4xx 排前面）
};

/// NSUserDefaults 键：网络列表排序方式。与 VConsoleDefaultsKey* 系列命名保持一致。
FOUNDATION_EXPORT NSString * const VConsoleDefaultsKeyNetworkSortMode;   // NSInteger: VConsoleNetworkSortMode

/// 排序方式的短名，用于按钮标题（「默认」「耗时」「大小」「状态码」）
NSString *VConsoleSortModeTitle(VConsoleNetworkSortMode mode);
/// 读取当前排序方式。从未持久化过或值越界时返回 VConsoleNetworkSortModeDefault。
VConsoleNetworkSortMode VConsoleNetworkSortModeCurrent(void);
/// 写入排序方式（越界值回落默认）。
void VConsoleSetNetworkSortMode(VConsoleNetworkSortMode mode);

#pragma mark - 动态字体

/// 按系统文本样式返回跟随「系统字号」的字体。用于本身就是标准样式的文本。
UIFont *VConsoleFontForTextStyle(UIFontTextStyle style);
/// 以 designSize 为基准、跟随系统字号缩放的字体。用于我们有自己字号设计的文本：
/// 用 UIFontMetrics 缩放而不是 preferredFontForTextStyle:，后者会把我们的 13/11pt
/// 硬套成 17/13pt，丢掉面板既有的信息密度设计。
UIFont *VConsoleScaledFont(CGFloat designSize, UIFontWeight weight);
/// 等宽字体版本（日志 JSON / 详情正文用 Menlo），同样跟随系统字号缩放。
UIFont *VConsoleScaledMonospaceFont(CGFloat designSize);

/// 动态字体的「例外清单」——以下几处**故意不跟随**系统字号，改它们会把固定尺寸容器撑破，
/// 不要以为是漏改：
///   1. 面板 tabbar 上的徽标（16pt 圆角容器，字大了溢出圆角）
///   2. 筛选 chip 按钮（固定 26pt 高，跟随会撑破圆角背景）
///   3. 悬浮球上的文字（固定尺寸圆球）
///   4. 面板 tabbar 标题 / 底部 40pt 操作栏上的按钮（横向空间固定，跟随会与相邻标签撞约束）
/// 反之，列表正文与副标题、详情正文、设置页/存储页文本一律跟随。

/// 把 text 中所有 case-insensitive 命中 query 的片段加高亮背景。
/// query 为空或未命中时，返回带 font/color 的普通 attributed string。
/// text / query / font / color 任一为 nil 都不会崩溃（内部按安全默认值兜底）。
NSAttributedString *VConsoleHighlightedText(NSString *text, NSString *query, UIFont *font, UIColor *color);

NS_ASSUME_NONNULL_END
