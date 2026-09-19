//
//  UIViewController+NMPanel.m
//  NeomorphKit
//
//  Task 127：子面板新拟物基底样式实现。设计说明见头文件。
//

#import "UIViewController+NMPanel.h"
#import "NMTheme.h"
#import <objc/runtime.h>

static void *s_nm127_appliedKey = &s_nm127_appliedKey;

@implementation UIViewController (NMPanel)

- (BOOL)nm_subpanelExcludesNeomorphStyle {
    // 分类默认不排除；子类按需覆盖（见头注释）
    return NO;
}

- (void)nm_applySubpanelNeomorphStyle {
    // 幂等：每个 VC 实例只应用一次
    if (objc_getAssociatedObject(self, s_nm127_appliedKey)) return;
    objc_setAssociatedObject(self, s_nm127_appliedKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMICT);

    if ([self nm_subpanelExcludesNeomorphStyle]) return;

    UIView *rootView = self.view;
    if (!rootView) return;

    // (1) 基底画布：系统默认底（nil / systemBackground）-> 新拟态画布色。
    //     已是 clearColor 的（BackgroundManager 全局背景透出面板）不动——
    //     那是刻意的透明定制，覆盖会破坏背景照片/视频功能（Task111）。
    UIColor *bg = rootView.backgroundColor;
    BOOL transparentByDesign = (bg == UIColor.clearColor);
    if (!transparentByDesign) {
        rootView.backgroundColor = [NMTheme nm_background];
    }

    // (2) 表格基底：背景清透（画布/照片透出）+ 分隔线主题化。
    //     只动 UITableView 自身底色，不动 cell（cell 样式归各自实现：
    //     Task89 体系的卡片 cell 已自绘，普通 cell 维持系统样式即可）。
    //     遍历规则：深度上限 3（view > 容器 > 容器 > 表格 足以覆盖常规面板），
    //     且不深入 UITableView 内部（其子视图是 cell，不归基底样式管）。
    [self nm127_styleTableViewsInView:rootView depth:0];
}

- (void)nm127_styleTableViewsInView:(UIView *)view depth:(NSInteger)depth {
    if (depth > 3) return;
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *tv = (UITableView *)view;
        // 纯色画布场景：表格清透，画布色接管；照片透出场景同样清透（原本多为此值，幂等）
        if (tv.backgroundColor != UIColor.clearColor) {
            // 已被面板自定义为 surface 等主题色的不动（Task89 体系面板）
            if (tv.backgroundColor == nil ||
                [tv.backgroundColor isEqual:UIColor.systemBackground] ||
                [tv.backgroundColor isEqual:UIColor.groupTableViewBackgroundColor]) {
                tv.backgroundColor = UIColor.clearColor;
            }
        }
        tv.separatorColor = [NMTheme nm_secondaryLabel];
        // 滚动指示器跟随主题（浅主题深条/深主题浅条）
        if (@available(iOS 13.0, *)) {
            tv.indicatorStyle = [NMTheme shared].isDark
                ? UIScrollViewIndicatorStyleWhite
                : UIScrollViewIndicatorStyleBlack;
        }
        return;   // 不深入表格内部（cell 归各自实现）
    }
    for (UIView *sub in view.subviews) {
        [self nm127_styleTableViewsInView:sub depth:depth + 1];
    }
}

@end
