#import <Security/Security.h>
#import "BaseAuthenticator.h"
#import "ThirdPartyAuthenticator.h"
#import "../LauncherPreferences.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

@implementation BaseAuthenticator

static BaseAuthenticator *current = nil;

+ (id)current {
    if (current == nil) {
        // selected_account 现在存储的是 accountId（旧版存储 username，loadSavedName 会自动迁移）
        NSString *savedAccount = getPrefObject(@"internal.selected_account");
        if (savedAccount.length > 0) {
            [self loadSavedName:savedAccount];
        }
    }
    return current;
}

+ (void)setCurrent:(BaseAuthenticator *)auth {
    current = auth;
}

/// 根据账户数据生成唯一 accountId。
/// - 微软账户：使用 xuid（Xbox User Hash，全局唯一且稳定，登录后不变）
/// - 第三方账户：使用 profileId（角色 UUID，由认证服务器分配，唯一稳定）
/// - 本地账户：无天然唯一 ID，生成随机 UUID
/// 这样同名账户也能通过 accountId 区分，文件名不再冲突。
+ (NSString *)generateAccountIdForData:(NSMutableDictionary *)authData {
    // 微软账户：优先使用 xuid（XSTS 响应中的 uhs，全局唯一且稳定）
    NSString *xuid = authData[@"xuid"];
    if (xuid && [xuid length] > 0) {
        return xuid;
    }
    // 第三方账户：使用 profileId（角色 UUID，由认证服务器分配，唯一稳定）
    NSString *profileId = authData[@"profileId"];
    if (profileId && [profileId length] > 0 &&
        ![profileId isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
        return profileId;
    }
    // 本地账户：无天然唯一 ID，生成随机 UUID
    return [[NSUUID UUID] UUIDString];
}

+ (id)loadSavedName:(NSString *)accountId {
    // accountId 可能是新格式的 accountId，也可能是旧格式的 username（迁移场景）
    NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), accountId];
    NSMutableDictionary *authData = parseJSONFromFile(path);
    if (authData[@"NSErrorObject"] != nil) {
        NSError *error = ((NSError *)authData[@"NSErrorObject"]);
        if (error.code != NSFileReadNoSuchFileError) {
            showDialog(localize(@"Error", nil), error.localizedDescription);
        }
        return nil;
    }

    // 根据账户数据创建对应类型的 authenticator（initWithData 会设置 current 单例）
    // Task 128：优先读显式 accountType 标记（zl2 的 AccountType 思路；登录时
    // 由各 authenticator 写入）。旧文件的键位嗅探保留为回退（expiresAt/clientToken），
    // 三处判别器（此处 / AccountList 的 clientToken 嗅探 / Java 端 clientToken+xuid）
    // 口径不一导致的串类自此统一。
    BaseAuthenticator *auth = nil;
    NSString *ame128_type = authData[@"accountType"];
    if ([ame128_type isEqualToString:@"thirdparty"]) {
        auth = [[ThirdPartyAuthenticator alloc] initWithData:authData];
    } else if ([ame128_type isEqualToString:@"microsoft"]) {
        auth = [[MicrosoftAuthenticator alloc] initWithData:authData];
    } else if ([ame128_type isEqualToString:@"local"]) {
        auth = [[LocalAuthenticator alloc] initWithData:authData];
    } else if ([authData[@"expiresAt"] longValue] == 0) {
        auth = [[LocalAuthenticator alloc] initWithData:authData];
    } else if (authData[@"clientToken"] != nil) {
        // If there is a clientToken, this is a third-party account
        auth = [[ThirdPartyAuthenticator alloc] initWithData:authData];
    } else {
        auth = [[MicrosoftAuthenticator alloc] initWithData:authData];
    }

    // 迁移旧格式账户：若 authData 没有 accountId 字段，说明是旧版按 username 命名的账户。
    // 生成 accountId，保存到新文件 <accountId>.json，删除旧文件 <username>.json，
    // 迁移头像文件，并更新 selected_account。
    NSString *existingAccountId = authData[@"accountId"];
    if (existingAccountId == nil || [existingAccountId length] == 0) {
        NSString *newAccountId = [BaseAuthenticator generateAccountIdForData:authData];
        authData[@"accountId"] = newAccountId;

        NSString *newPath = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), newAccountId];
        NSError *saveError = saveJSONToFile(authData, newPath);

        if (saveError == nil) {
            // 删除旧文件（如果 accountId 入参与生成的 newAccountId 不同，说明入参是旧 username）
            if (![accountId isEqualToString:newAccountId]) {
                [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            }
            // 迁移头像文件：<username>.png → <accountId>.png
            // 头像目录是 <Documents>/avatars/，与账户目录（POJAV_HOME/accounts/）分离
            NSString *username = authData[@"username"];
            if (username && username.length > 0 && ![username isEqualToString:newAccountId]) {
                NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *oldAvatarPath = [NSString stringWithFormat:@"%@/avatars/%@.png", docsDir, username];
                NSString *newAvatarPath = [NSString stringWithFormat:@"%@/avatars/%@.png", docsDir, newAccountId];
                // 仅当旧头像存在且新头像不存在时迁移，避免覆盖
                if ([NSFileManager.defaultManager fileExistsAtPath:oldAvatarPath] &&
                    ![NSFileManager.defaultManager fileExistsAtPath:newAvatarPath]) {
                    [NSFileManager.defaultManager moveItemAtPath:oldAvatarPath toPath:newAvatarPath error:nil];
                }
            }
            // 更新 selected_account：若当前选中的是旧 username/accountId，改为新的 accountId
            if ([getPrefObject(@"internal.selected_account") isEqualToString:accountId]) {
                setPrefObject(@"internal.selected_account", newAccountId);
            }
        }
    }

    return auth;
}

- (id)initWithData:(NSMutableDictionary *)data {
    current = self = [self init];
    self.authData = data;
    return self;
}

- (id)initWithInput:(NSString *)string {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"input"] = string;
    return [self initWithData:data];
}

- (void)loginWithCallback:(Callback)callback {
}

- (void)refreshTokenWithCallback:(Callback)callback {
}

- (BOOL)saveChanges {
    NSError *error;

    [self.authData removeObjectForKey:@"input"];
    [self.authData removeObjectForKey:@"password"];
    // oldusername 机制已废弃：文件名改用 accountId，username 变更不再需要重命名文件
    [self.authData removeObjectForKey:@"oldusername"];

    // 确保 accountId 存在（首次保存时兜底生成，正常登录流程已在子类设置）
    NSString *accountId = self.authData[@"accountId"];
    if (accountId == nil || [accountId length] == 0) {
        accountId = [BaseAuthenticator generateAccountIdForData:self.authData];
        self.authData[@"accountId"] = accountId;
    }

    // 文件名使用 accountId（唯一标识），同名账户不再冲突
    NSString *newPath = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), accountId];
    error = saveJSONToFile(self.authData, newPath);

    if (error != nil) {
        showDialog(@"Error while saving file", error.localizedDescription);
    } else {
        // 保存选中的账户（accountId），确保重启后能恢复登录状态
        setPrefObject(@"internal.selected_account", accountId);
    }
    return error == nil;
}

@end
