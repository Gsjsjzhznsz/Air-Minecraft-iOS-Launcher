#import <UIKit/UIKit.h>

// ============================================================================
// Task 188（FCL 式控件仓库）：应用内浏览远程控件布局仓库（GitHub 仓库
// controls/ 目录 + index.json 索引，参考 Fold Craft Launcher 的控制仓库
// 设计），一键下载社区布局到本地 controlmap/，随后经编辑器"加载"菜单
// 或游戏内控件设置使用。下载源：raw.githubusercontent.com 主源 +
// jsDelivr CDN 回退。
// ============================================================================
@interface ControlRepoViewController : UITableViewController
/// 下载完成后的回调（文件名不含 .json 后缀，与 actionOpenFilePicker
/// 的 whenItemSelected 语义一致）。
@property (nonatomic, copy) void (^whenLayoutDownloaded)(NSString *fileName);
@end
