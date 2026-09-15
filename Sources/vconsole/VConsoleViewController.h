#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 调试面板容器：顶栏 + Tab（日志/网络/存储/系统）+ 子页面。
@interface VConsoleViewController : UIViewController

/// 面板即将显示时调用，用于刷新当前 Tab 数据。
- (void)refreshVisible;

/// 切换到指定 Tab：0 日志 / 1 网络 / 2 存储 / 3 系统。
/// 对标 H5 vConsole 的 vConsole.showTab()，供宿主在自动化演示 / 回归测试中驱动面板。
/// 越界索引忽略；索引与当前一致时只刷新数据。会自动确保视图已加载。
- (void)selectTabAtIndex:(NSInteger)index;

/// 面板弹入动画：从底部 spring 弹入 + 遮罩渐显。供 VConsoleController 在 show 时调用。
- (void)animatePanelIn;

/// 面板滑出动画：向下滑出 + 遮罩渐隐，完成后回调（用于隐藏 window）。
- (void)animatePanelOutWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
