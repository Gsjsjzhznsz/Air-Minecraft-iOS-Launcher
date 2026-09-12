#import <UIKit/UIKit.h>
#import "customcontrols/ControlButton.h"
#import "customcontrols/ControlLayout.h"

typedef NSString* (^GetDefaultCtrlBlock)();
typedef void (^SetDefaultCtrlBlock)(NSString *);

@interface ControlHandleView : UIView
@property(nonatomic, weak) ControlButton* target;
@end

@interface CustomControlsViewController : UIViewController

@property(nonatomic) GetDefaultCtrlBlock getDefaultCtrl;
@property(nonatomic) SetDefaultCtrlBlock setDefaultCtrl;

@property(nonatomic) UIGestureRecognizer* currentGesture;

@property(nonatomic) ControlLayout* ctrlView;
@property(nonatomic) ControlHandleView* resizeView;

@end

@interface CustomControlsViewController(UndoManager)
- (void)doAddButton:(ControlButton *)button atIndex:(NSNumber *)index;
- (void)doRemoveButton:(ControlButton *)button;
- (void)doMoveOrResizeButton:(ControlButton *)button from:(CGRect)from to:(CGRect)to;
- (void)doUpdateButton:(ControlButton *)button from:(NSMutableDictionary *)from to:(NSMutableDictionary *)to;
@end

@interface CCMenuViewController : UIViewController
@property(nonatomic) ControlButton* targetButton;
/// Task 62：呈现时由编辑器注入的弱引用。不能依赖 presentingViewController——
/// UIKit 会把容器子 VC（如被 UINavigationController 包裹的编辑器）的 present
/// 请求转发给容器，那时 presentingViewController 是导航控制器而不是编辑器，
/// 盲转型发 doUpdateButton:from:to: 会导致 “unrecognized selector” 闪退。
@property(nonatomic, weak) CustomControlsViewController* controlsEditor;
@end
