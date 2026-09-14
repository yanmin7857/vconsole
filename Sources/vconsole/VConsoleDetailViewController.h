#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 通用详情页：展示日志/网络/存储条目的完整文本，可复制。
@interface VConsoleDetailViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title detail:(NSString *)detail;

/// 带折叠版的初始化：foldedDetail 非空且与 detail 不同时，
/// 默认展示折叠版，导航栏出现「展开全部 / 折叠」切换。
/// 传 nil 等价于上面的普通初始化。
- (instancetype)initWithTitle:(NSString *)title
                       detail:(NSString *)detail
                 foldedDetail:(nullable NSString *)foldedDetail;

@end

NS_ASSUME_NONNULL_END
