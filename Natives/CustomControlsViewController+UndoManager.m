#import "CustomControlsViewController.h"
#import "customcontrols/ControlDrawer.h"
#import "customcontrols/ControlJoystick.h"
#import "customcontrols/ControlLayout.h"
#import "utils.h"

@implementation CustomControlsViewController(UndoManager)

- (void)doAddButton:(ControlButton *)button atIndex:(NSNumber *)index {
    NSUndoManager *undo = self.undoManager;

    // Task191：insertObject nil 防护（"放大/操作控件崩溃"防御轮）。
    // 病历（dde0f82 装机 latestlog.1）：控件仓库下载 large-buttons 保存后
    // NSInvalidArgumentException '-[__NSArrayM insertObject:atIndex:]:
    // object cannot be nil'（裸地址栈，静态审计 12 处 insertObject 未闭环）。
    // 本方法 4 处 insertObject 的 object（button.properties / drawerData）
    // 在【布局切换后重放旧 undo 栈】时可悬垂：loadControlFile 重建
    // layoutDictionary 但不清 undo 栈，旧 invocation 携带的 button 与其
    // properties 可能已随旧字典释放（NSInvocation 默认不 retain 参数）。
    // 防御：object 为 nil 时打锚点日志跳过插入（视觉上少一个按钮，
    // 好过崩溃）；布局切换点同步清栈（见 loadControlFile 调用侧）。
    if (!button || !button.properties || !index) {
        NSLog(@"[CustomControls] Task191: doAddButton guarded (button=%ld properties=%ld index=%ld) -- stale undo replay?",
              (long)(!!button), (long)(!!(button ? button.properties : nil)), (long)(!!index));
        return;
    }

    if ([button isKindOfClass:ControlSubButton.class]) {
        undo.actionName = localize(@"custom_controls.button_menu.add_subbutton", nil);

        [self.ctrlView addSubview:button];
        ControlDrawer *drawer = ((ControlSubButton *)button).parentDrawer;
        [drawer.buttons insertObject:button atIndex:index.intValue]; 
        [drawer.drawerData[@"buttonProperties"] insertObject:button.properties atIndex:index.intValue];
        [drawer syncButtons];
    } else if ([button isKindOfClass:ControlDrawer.class]) {
        undo.actionName = localize(@"custom_controls.control_menu.add_drawer", nil);

        for (ControlSubButton *subButton in ((ControlDrawer *)button).buttons) {
            [self.ctrlView addSubview:subButton];
        }
        [self.ctrlView.layoutDictionary[@"mDrawerDataList"] insertObject:((ControlDrawer *)button).drawerData atIndex:index.intValue];
        [self.ctrlView addSubview:button];
    } else if ([button isKindOfClass:ControlJoystick.class]) {
        undo.actionName = localize(@"custom_controls.control_menu.add_joystick", nil);
        [self.ctrlView.layoutDictionary[@"mJoystickDataList"] insertObject:button.properties atIndex:index.intValue];
        [self.ctrlView addSubview:button];
    } else {
        undo.actionName = localize(@"custom_controls.control_menu.add_button", nil);
        [self.ctrlView.layoutDictionary[@"mControlDataList"] insertObject:button.properties atIndex:index.intValue];
        [self.ctrlView addSubview:button];
    }

    [[undo prepareWithInvocationTarget:self] doRemoveButton:button];
    if (undo.isUndoing) {
        undo.actionName = localize(@"Remove", nil);
    }
}

- (void)doRemoveButton:(ControlButton *)button {
    NSNumber *index;
    if ([button isKindOfClass:ControlSubButton.class]) {
        ControlDrawer *parent = ((ControlSubButton *)button).parentDrawer;
        index = @([parent.drawerData[@"buttonProperties"] indexOfObject:button.properties]);
        [parent.buttons removeObject:button];
        [parent.drawerData[@"buttonProperties"] removeObject:button.properties];
        [parent syncButtons];
    } else if ([button isKindOfClass:ControlDrawer.class]) {
        ControlDrawer *drawer = (ControlDrawer *)button;
        index = @([self.ctrlView.layoutDictionary[@"mDrawerDataList"] indexOfObject:drawer.drawerData]);
        [drawer.buttons makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [self.ctrlView.layoutDictionary[@"mDrawerDataList"] removeObject:drawer.drawerData];
    } else if ([button isKindOfClass:ControlJoystick.class]) {
        index = @([self.ctrlView.layoutDictionary[@"mJoystickDataList"] indexOfObject:button.properties]);
        [self.ctrlView.layoutDictionary[@"mJoystickDataList"] removeObject:button.properties];
    } else {
        index = @([self.ctrlView.layoutDictionary[@"mControlDataList"] indexOfObject:button.properties]);
        [self.ctrlView.layoutDictionary[@"mControlDataList"] removeObject:button.properties];
    }
    [button removeFromSuperview];
    self.resizeView.hidden = YES;

    NSUndoManager *undo = self.undoManager;
    [[undo prepareWithInvocationTarget:self] undoRemoveButton:button atIndex:index];
    if (!undo.isUndoing) {
        undo.actionName = localize(@"Remove", nil);
    }
}

- (void)undoRemoveButton:(ControlButton *)button atIndex:(NSNumber *)index {
    NSUndoManager *undo = self.undoManager;
    if (!undo.isUndoing) {
        undo.actionName = localize(@"Remove", nil);
    }
    [self doAddButton:button atIndex:index];
}

- (void)doMoveOrResizeButton:(ControlButton *)button from:(CGRect)from to:(CGRect)to
{
    NSUndoManager *undo = self.undoManager;
    [[undo prepareWithInvocationTarget:self] doMoveOrResizeButton:button from:to to:from];
    if (!undo.isUndoing) {
        if (CGSizeEqualToSize(from.size, to.size)) {
            undo.actionName = localize(@"Move", nil);
        } else {
            undo.actionName = localize(@"Resize", nil);
        }
    }

    [button snapAndAlignX:to.origin.x Y:to.origin.y];
    button.properties[@"width"] = @(to.size.width);
    button.properties[@"height"] = @(to.size.height);
    [button update];
    self.resizeView.frame = CGRectMake(CGRectGetMaxX(button.frame), CGRectGetMaxY(button.frame), self.resizeView.frame.size.width, self.resizeView.frame.size.height);
}

- (void)doUpdateButton:(ControlButton *)button from:(NSMutableDictionary *)from to:(NSMutableDictionary *)to
{
    NSUndoManager *undo = self.undoManager;
    [[undo prepareWithInvocationTarget:self] doUpdateButton:button from:to to:from];
    if (!undo.isUndoing) {
        undo.actionName = localize(@"Edit", nil);
    }

    for (NSString *key in to) {
        button.properties[key] = to[key];
    }

    @try {
        [button update];
    } @catch (NSException *exception) {
        button.properties[@"dynamicX"] = to[@"dynamicX"] = from[@"dynamicX"];
        button.properties[@"dynamicY"] = to[@"dynamicY"] = from[@"dynamicY"];
        @throw exception;
    }
}

@end
