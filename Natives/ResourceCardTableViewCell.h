//
//  ResourceCardTableViewCell.h
//  Amethyst
//
//  资源管理卡片 Cell 公共基类（Prisma-Design L2 标准卡片）
//  供 Mod / Shader / ResourcePack / DataPack / World / Modpack 六个资源管理界面复用。
//
//  卡片结构（参照 VersionCardCell 正面基准）：
//  - 三层卡片背景：半透明基底(白 0.08) + BackgroundManager 毛玻璃 + 0.5pt 白 0.10 描边 + 轻阴影
//  - 圆角 12pt + kCACornerCurveContinuous；contentView 裁圆角，外层 cell 用 shadowPath 保留阴影
//  - 左侧 40×40 图标容器（10pt continuous 圆角，资源类型语义色背景）内嵌 22×22 白色 SF Symbol
//  - 中部：名称(15pt Semibold) / 副标题(12pt) / 元信息(11pt，可选第三行)
//  - 右侧 accessory 插槽：toggleSwitch / chevronImageView / updateBadge（懒加载，默认隐藏）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ResourceCardTableViewCell : UITableViewCell

#pragma mark - 内容视图（子类直接访问配置）

/// 左侧图标容器（40×40，10pt continuous 圆角，背景色 = 资源类型语义色）
@property (nonatomic, strong, readonly) UIView *iconContainer;
/// 图标本体（22×22，白色 SF Symbol，居中于 iconContainer）
@property (nonatomic, strong, readonly) UIImageView *iconImageView;
/// 名称（15pt Semibold / labelColor）
@property (nonatomic, strong, readonly) UILabel *nameLabel;
/// 副标题（12pt Regular / secondaryLabelColor）
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
/// 元信息第三行（11pt / tertiaryLabelColor，可选，configure 传 nil 时隐藏）
@property (nonatomic, strong, readonly) UILabel *detailLabel;

#pragma mark - 右侧 accessory 插槽（懒加载，默认隐藏）

/// accessory 区横向容器（toggleSwitch / chevron / updateBadge 懒加载时自动加入；
/// 子类可将自己的 accessory 视图 addArrangedSubview 进来，stack 会自动收起隐藏项）
@property (nonatomic, strong, readonly) UIStackView *accessoryStack;
/// 启用/禁用开关插槽（首次访问时创建并加入 accessory 区，默认隐藏）
@property (nonatomic, strong, readonly) UISwitch *toggleSwitch;
/// chevron.right 指示插槽（tertiaryLabelColor，默认隐藏）
@property (nonatomic, strong, readonly) UIImageView *chevronImageView;
/// 更新徽章插槽（16×16 arrow.up.circle.fill，accent 色，默认隐藏）
@property (nonatomic, strong, readonly) UIImageView *updateBadge;

#pragma mark - 配置

/// 通用配置：图标 SF Symbol + 类型语义色 + 标题/副标题/元信息（subtitle/detail 传 nil 隐藏对应行）
- (void)configureWithIcon:(NSString *)sfSymbolName
                iconColor:(nullable UIColor *)color
                    title:(NSString *)title
                 subtitle:(nullable NSString *)subtitle
                   detail:(nullable NSString *)detail;

#pragma mark - 批量选择（勾选）模式视觉

/// 开启后 cell 勾选时显示 1.5pt accent 边框 + accent 0.08 染色；
/// 由 ResourceListViewController setSelectMode: 触发 UITableView 编辑模式时会自动同步。
- (void)setSelectionModeEnabled:(BOOL)enabled;

/// 手动设置选中态（内部走 setSelected:，仅在选择模式开启时显示选中视觉）
- (void)setCardSelected:(BOOL)selected animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
