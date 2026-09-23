#import <UIKit/UIKit.h>
#import "PLPrefTableViewController.h"

@interface LauncherPreferencesViewController : PLPrefTableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIColorPickerViewControllerDelegate>

// Task156：深链目标键（右侧边栏信息卡点击直达）。设置后，viewDidAppear 会
// 滚动到 prefContents 中首个 key 匹配的行并高亮闪一下；nil = 普通打开。
// 已知目标：check_update / jit_enabler / memory_limit_help。
@property (nonatomic, copy, nullable) NSString *ameDeepLinkKey;

@end
