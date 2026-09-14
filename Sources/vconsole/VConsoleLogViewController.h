#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 日志 Tab：展示分级日志，支持点开详情与清空。
@interface VConsoleLogViewController : UIViewController

- (void)refresh;

/// 键盘快捷键（Cmd+F）入口：聚焦顶部搜索框
- (void)focusSearch;

@end

NS_ASSUME_NONNULL_END
