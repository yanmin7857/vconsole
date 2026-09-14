#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 管理独立的 overlay 窗口与调试面板，控制显示/隐藏。
@interface VConsoleController : NSObject

+ (instancetype)shared;

- (void)show;
- (void)hide;
- (void)toggle;
@property (nonatomic, assign, readonly) BOOL isVisible;

/// 关联主窗口上的悬浮按钮，面板打开时隐藏它。
- (void)setFloatingButton:(nullable UIButton *)button;

@end

NS_ASSUME_NONNULL_END
