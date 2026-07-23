//
//  AnnouncementDetailViewController.h
//  Amethyst
//
//  公告详情视图控制器
//  - 顶部标题（大字）+ 日期（小字灰色）
//  - 正文用 UITextView + MarkdownParser 渲染的 NSAttributedString
//  - 若公告有 actionURL，底部显示按钮（SFSafariViewController 打开）
//

#import <UIKit/UIKit.h>

@class AnnouncementItem;

NS_ASSUME_NONNULL_BEGIN

@interface AnnouncementDetailViewController : UIViewController

/// 使用指定公告构造详情页
- (instancetype)initWithAnnouncement:(AnnouncementItem *)item;

@end

NS_ASSUME_NONNULL_END
