//
//  AnnouncementListViewController.h
//  Amethyst
//
//  公告列表视图控制器
//  参考 MinecraftNewsViewController 的瀑布流卡片风格，简化实现：
//  - 双列 UICollectionViewCompositionalLayout 布局
//  - 每个 cell 显示标题、日期、摘要
//  - priority=high 的卡片左侧有蓝色条
//  - 点击进入详情页 AnnouncementDetailViewController
//  - 支持下拉刷新与右上角强制刷新
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AnnouncementListViewController : UIViewController

@end

NS_ASSUME_NONNULL_END
