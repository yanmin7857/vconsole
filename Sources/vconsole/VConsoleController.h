#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 管理独立的 overlay 窗口与调试面板，控制显示/隐藏。
@interface VConsoleController : NSObject

+ (instancetype)shared;

- (void)show;
- (void)hide;
- (void)toggle;
@property (nonatomic, assign, readonly) BOOL isVisible;

/// 切换面板 Tab：0 日志 / 1 网络 / 2 存储 / 3 系统。
/// 会自动创建面板（首次调用即触发懒加载），越界索引忽略；不改变面板可见性。
- (void)selectPanelTab:(NSInteger)index;

/// 关联主窗口上的悬浮按钮，面板打开时隐藏它。
- (void)setFloatingButton:(nullable UIButton *)button;

@end

NS_ASSUME_NONNULL_END
