//
//  UIViewController+NMPanel.h
//  NeomorphKit
//
//  Task 127：所有子级面板的新拟物基底样式（单一执法点配套工具）。
//
//  背景（5.1.0 用户实测反馈）："所有子级面板都需要使用新拟物设计"
//  ——主界面/侧栏/右面板/设置页在 Task89 已完成新拟态化，但从侧栏推入的
//  子级面板（账户管理/下载历史/文件列表/Mod 管理/帮助等 29 个）仍是
//  系统默认白/黑底，与整体语言割裂。
//
//  设计（保守增量，不破坏既有定制）：
//  - nm_applySubpanelNeomorphStyle 只做"基底画布"统一：
//      1) 视图背景 -> NMTheme nm_background（新拟态画布色）
//      2) 递归发现 UITableView -> 背景清透（画布透出）+ 分隔线主题化
//  - 幂等：重复调用无副作用（objc_setAssociatedObject 做标记）
//  - 逃生舱（不覆盖既有定制）：
//      * 视图背景已是 clearColor（BackgroundManager.makeViewControllerTransparent
//        处理过的全局背景透出面板）-> 跳过背景改写，仅调表格
//      * VC 实现了 nm_subpanelExcludesNeomorphStyle 并返回 YES -> 整体跳过
//  - 单一执法点：LauncherNavigationController pushViewController: 与根 VC
//    各调一次（见 LauncherNavigationController.m Task127 注释），所有现存
//    与未来新增的子面板自动继承，无需逐个改造。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (NMPanel)

/// 应用子面板新拟物基底样式（幂等；见头注释的保守规则）
- (void)nm_applySubpanelNeomorphStyle;

/// 逃生舱：返回 YES 的 VC 不参与 Task127 基底统一（默认 NO）
/// （子类可覆盖；用于完全自绘的特殊面板，如视频背景裁剪器）
- (BOOL)nm_subpanelExcludesNeomorphStyle;

@end

NS_ASSUME_NONNULL_END
