#import "ControlButton.h"
#import "ControlLayout.h"
#import "ControlSubButton.h"
#import "CustomControlsUtils.h"
#import "../LauncherPreferences.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

@interface ControlLayout ()
@end

@implementation ControlLayout

- (void)loadControlLayout:(NSMutableDictionary *)layoutDictionary {
    self.layoutDictionary = layoutDictionary;

    CGFloat currentScale = [self.layoutDictionary[@"scaledAt"] floatValue];
    CGFloat savedScale = getPrefFloat(@"control.button_scale");
    loadControlObject(self, self.layoutDictionary);

    self.layoutDictionary[@"scaledAt"] = @(savedScale);
}

- (void)loadControlFile:(NSString *)name {
    [self removeAllButtons];

    NSString *controlFilePath = [NSString stringWithFormat:@"%s/controlmap/%@", getenv("POJAV_HOME"), name];

    self.layoutDictionary = parseJSONFromFile(controlFilePath);
    if (self.layoutDictionary[@"NSErrorObject"] != nil) {
        showDialog(localize(@"Error", nil), [NSString stringWithFormat:@"Could not open %@: %@", controlFilePath, [self.layoutDictionary[@"NSErrorObject"] localizedDescription]]);
        // Task 64 防御性回落：布局解析失败 = 零控件上屏 = "进游戏控件全部无反应"。
        // 旧布局在历史保存崩溃中写坏（或升级换代后字段不兼容）时，与其让玩家
        // 拿着空屏干瞪眼，不如回落加载出厂 default.json 保住可玩性；玩家仍可
        // 通过游戏内菜单/编辑器的"恢复默认控件"显式重建。仅当失败的不是
        // default.json 本身才回落（防递归；出厂文件由启动时
        // generateAndSaveDefaultControl 保证存在，二次失败概率极低）。
        if (![name isEqualToString:@"default.json"]) {
            NSString *defaultPath = [NSString stringWithFormat:@"%s/controlmap/default.json", getenv("POJAV_HOME")];
            NSMutableDictionary *fallback = parseJSONFromFile(defaultPath);
            if (fallback[@"NSErrorObject"] == nil) {
                NSLog(@"[CustomControls] Task64 parse-fail fallback: %@ -> default.json (controls kept alive)", name);
                [self loadControlLayout:fallback];
            } else {
                NSLog(@"[CustomControls] Task64 parse-fail fallback failed: default.json also unreadable");
            }
        }
        return;
    }
    [self loadControlLayout:self.layoutDictionary];
}

- (void)removeAllButtons {
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self.layoutDictionary removeAllObjects];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    return action == @selector(actionMenuExit:) ||
        action == @selector(actionMenuSave:) ||
        action == @selector(actionMenuLoad:) ||
        action == @selector(actionMenuSetDef:) ||
        action == @selector(actionMenuAddButton:) ||
        action == @selector(actionMenuAddDrawer:) ||
        action == @selector(actionMenuAddSubButton:) ||
        action == @selector(actionMenuBtnCopy:) ||
        action == @selector(actionMenuBtnDelete:) ||
        action == @selector(actionMenuBtnEdit:) ||
        action == @selector(actionMenuBtnSafeArea:);
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = [super hitTest:point withEvent:event];
    if (result == self && !isControlModifiable) {
        return nil;
    }
    return result;
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];

    for (UIView *view in self.subviews) {
        if (![view isKindOfClass:ControlButton.class]) {
            continue;
        }
        [(ControlButton *)view update];
    }

    CGFloat savedScale = getPrefFloat(@"control.button_scale");
    self.layoutDictionary[@"scaledAt"] = @(savedScale);
}

// https://nsantoine.dev/posts/CALayerCaptureHiding
- (void)hideViewFromCapture:(BOOL)hide {
    if ([self.layer respondsToSelector:@selector(disableUpdateMask)]) {
        NSUInteger hideFlag = (1 << 1) | (1 << 4);
        self.layer.disableUpdateMask = hide ? hideFlag : 0;
    }
}

@end
