#import <UIKit/UIKit.h>

#define realUIIdiom UIDevice.currentDevice.userInterfaceIdiom
extern NSNotificationName UIPresentationControllerPresentationTransitionWillBeginNotification;

@interface UIDevice(hook)
- (NSString *)completeOSVersion;
@end

@interface UIImageView(hook)
@property(nonatomic) BOOL isSizeFixed;
@end

@interface UIImage(hook)
- (UIImage *)hook_imageWithSize:(CGSize)size;
@end

// private functions
@interface UIContextMenuInteraction(ame_private)
- (void)_presentMenuAtLocation:(CGPoint)location;
@end
@interface _UIContextMenuStyle : NSObject <NSCopying>
@property(nonatomic) NSInteger preferredLayout;
+ (instancetype)defaultStyle;
@end

@interface UIDevice(ame_private)
- (NSString *)buildVersion;
- (void)_setActiveUserInterfaceIdiom:(NSInteger)idiom;
@end

@interface UIImage(ame_private)
- (UIImage *)_imageWithSize:(CGSize)size;
@end

@interface UIScreen(ame_private)
- (void)_setUserInterfaceIdiom:(NSInteger)idiom;
@end

@interface UITextField(ame_private)
@property(assign, nonatomic) NSInteger nonEditingLinebreakMode;
@end

@interface UIWindow(global)
+ (UIWindow *)mainWindow;
+ (UIWindow *)externalWindow;
@end

@protocol _UIPointerInteractionDriver<NSObject>
@property (assign, nonatomic) UIView *view;
@end

@interface UIPointerInteraction(ame_private)
- (NSArray <id<_UIPointerInteractionDriver>> *)drivers;
- (id<_UIPointerInteractionDriver>)driver;
@end

/*
@interface WFTextTokenTextView : UITextField
@property(nonatomic) NSString* placeholder
@end
*/
