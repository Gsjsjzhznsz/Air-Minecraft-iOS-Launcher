#import "BaseAuthenticator.h"

@implementation LocalAuthenticator

- (void)loginWithCallback:(Callback)callback {
    self.authData[@"username"] = self.authData[@"input"];
    self.authData[@"profileId"] = @"00000000-0000-0000-0000-000000000000";
    // 本地账户无天然唯一 ID，生成随机 UUID 作为 accountId，使同名本地账户可共存
    self.authData[@"accountId"] = [[NSUUID UUID] UUIDString];
    // Task 128：显式账户类型标记（防键位嗅探串类，见 BaseAuthenticator.loadSavedName）
    self.authData[@"accountType"] = @"local";
    // 使用Minecraft Headshot API加载头像
    self.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://api.rms.net.cn/head/%@", self.authData[@"username"]];
    callback(nil, [super saveChanges]);
}

- (void)refreshTokenWithCallback:(Callback)callback {
    // Nothing to do
    callback(nil, YES);
}

@end
