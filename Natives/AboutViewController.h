//
//  AboutViewController.h
//  Amethyst
//
//  Task217：启动器"关于"页（设置二级菜单入口）。
//
//  内容：应用图标/名称/版本（动态读 Info.plist）、QQ 群、启动器更新区
//  （检查更新 + 启动时自动检查，从设置·通用区迁移而来——用户指令
//  "将启动器更新功能的 2 个选项移动到关于页面"）、许可证声明（AGPL-3.0
//  + 许可证内容所在处）、Fork 溯源致谢。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AboutViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
