#import "LauncherHelpViewController.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "utils.h"

// ============================================================================
// Task 82：启动器"使用问题"（FAQ）页面
//
// 左侧边栏新增"使用问题"标签，收录项目迭代中反复出现的用户问题与结论
// （每条都来自真实日志判读，非泛泛帮助文案）。语言跟随本 fork 的 AI 模块
// 先例：直接使用中文（用户主语言），不做 54 语言 l10n。
//
// 交互：按分类分组，点击问题行展开/收起答案，同一时刻允许多条同时展开。
// ============================================================================

@interface LauncherHelpFaqItem : NSObject
@property (nonatomic, copy) NSString *question;
@property (nonatomic, copy) NSString *answer;
@property (nonatomic, copy) NSString *iconName;
@end

@implementation LauncherHelpFaqItem
@end

@interface LauncherHelpViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, strong) NSArray<NSArray<LauncherHelpFaqItem *> *> *itemsByCategory;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *expandedPaths;
@end

@implementation LauncherHelpViewController

#pragma mark - Data

- (void)buildFaqData {
    // 每条目为项目 worklog 中定案的真实结论（Task 34-83）+ 社区/上游常见问题
    // （PojavLauncher/Amethyst issue tracker、Iris/Sodium 兼容性报告）整理。
    LauncherHelpFaqItem *renderer = [[LauncherHelpFaqItem alloc] init];
    renderer.iconName = @"cpu";
    renderer.question = @"渲染器应该怎么选？各渲染器是什么原理？";
    renderer.answer = @"渲染器在 设置 → 视频设置 → 渲染器 中选择（游戏未运行时才能改）：\n\n"
                      @"• Zink：把游戏的 OpenGL 转译到系统 Vulkan 栈上运行（GL→Vulkan→Metal），适合 26.x 新版本和装了模组的场景，区块加载更流畅；\n"
                      @"• MobileGlues：OpenGL→Metal 转译层，兼容性好，适合轻量场景和老版本；加载区块时每帧转译开销较大（安卓设备同样如此，属已知特性）；\n"
                      @"• MoltenVK：独立的渲染器，直接把 Vulkan API 映射到 Metal。MC 26.2+ 可在 游戏内 视频设置 → 图形 切到 Vulkan 后端配合使用（配合帧率解锁可超过屏幕刷新率）；它和 Zink 是两个互相独立的选项——Zink 用的是系统 Vulkan 栈，不等于\"选择 MoltenVK 渲染器\"；\n"
                      @"• 自动：由启动器按版本自动选择。\n\n"
                      @"简单记法：玩新版本/整合包用 Zink；老版本/轻量场景用 MobileGlues；需要 Vulkan 后端时选 MoltenVK。";

    LauncherHelpFaqItem *mgLag = [[LauncherHelpFaqItem alloc] init];
    mgLag.iconName = @"speedometer";
    mgLag.question = @"MobileGlues 加载区块时卡顿正常吗？";
    mgLag.answer = @"正常（已知特性）。MobileGlues 是 OpenGL → Metal 的转译层，26.x 新区块管线对它压力较大：同视距下转译调用量约为老版本的 3 倍，移动时帧率会明显下降；安卓设备跑 MobileGlues 同样卡顿，是上游转译栈的固有开销。\n\n"
                   @"缓解办法（按性价比排序）：\n"
                   @"1. 换 Zink 渲染器（区块流式吞吐明显更高）；\n"
                   @"2. 开启 FSR 超分辨率降低渲染分辨率（见下条）；\n"
                   @"3. 视距保持 10 左右即可，调大只会放大加载风暴时长。\n\n"
                   @"已排除的因素：GC、内存容量、GPU 性能都不是该卡顿的原因，单纯加大内存分配不会治愈它。";

    LauncherHelpFaqItem *fsr = [[LauncherHelpFaqItem alloc] init];
    fsr.iconName = @"square.grid.3x2";
    fsr.question = @"FSR 超分辨率怎么用？支持哪些渲染器？";
    fsr.answer = @"FSR 1.0 在 设置 → 视频设置 → FSR 1.0 超分辨率 中选择档位（超高品质 77%／高品质 67%／均衡 59%／性能优先 50%）：开启后游戏自动以低分辨率渲染，再由 FSR 的 EASU 算法放大回全屏，帧率明显提升、画质轻微下降。\n\n"
                 @"支持的渲染器（多渲染器支持为近期新增）：\n"
                 @"• MobileGlues：内置 FSR1（推荐，最成熟）；\n"
                 @"• Zink：同一套 EASU 升采样算法，呈现前放大（早期版本在 Zink 上先后出现过绿色花屏和\"画面分裂\"两种显示异常，均已修复——前者是 GLSL 4.1 上限的版本适配与半精度函数补齐，后者是升采样与画面回读的执行顺序颠倒，现已是回读前放大、显式锁定默认帧缓冲的封闭链路）；\n"
                 @"• 其它渲染器（MoltenVK/自动/gl4es 等）：暂不支持。MoltenVK 的纯 Vulkan 后端无呈现钩子，需要 FSR 请选 MobileGlues 或 Zink。\n\n"
                 @"注意：\n"
                 @"1. 分辨率滑条保持 100% 即可，不需要再手动降低分辨率（那反而会二次缩放）；\n"
                 @"2. 早期版本的\"开启后黑屏\"\"画面缩在左下角\"\"Zink 下绿色花屏\"均已分别修复（着色器降级修复 + 渲染视口识别修复 + 着色器版本适配与半精度函数补齐），如仍出现请上传日志反馈；\n"
                 @"3. FSR 升采样是在游戏画面渲染完成后一次性完成的，开销极小；若感觉\"开了 FSR 反而卡\"，多半是区块加载卡顿（参考 MobileGlues 卡顿一条），与 FSR 无关。";

    LauncherHelpFaqItem *metalFx = [[LauncherHelpFaqItem alloc] init];
    metalFx.iconName = @"wand.and.stars";
    metalFx.question = @"能不能用 MetalFX 时域放大（Temporal）代替 FSR？";
    metalFx.answer = @"短答案：时域（Temporal）版目前做不到，这是引擎层的硬性依赖，不是启动器不想接。\n\n"
                     @"【为什么做不到】\n"
                     @"MetalFX 的时域模式需要游戏每帧提供：逐像素运动向量图（Motion Vectors，API 必填）、深度图、相机抖动与重投影矩阵。Minecraft 原版渲染管线不产出运动向量——这需要在游戏的渲染器内部新增一个“速度通道”，属于引擎/模组层级的改造（相当于 Sodium/Iris 级别的工作量）。启动器的呈现桥只能看到最终成品帧，没有任何一帧的深度与相机信息，无法凭空合成出正确的运动向量；强行做纯时域累积会产生严重重影（拖影/鬼影），Apple 的接口也直接要求该输入。\n\n"
                     @"【空间（Spatial）版呢】\n"
                     @"MetalFX 空间版和 FSR 1.0 同为单帧升采样，画质同级，接上还需要 iOS 16+／A13+ 的设备门槛与额外的纹理互操作层，收益边际很小，暂不引入。\n\n"
                     @"【现在的建议】\n"
                     @"追求帧率：用 FSR 超高品质/高品质档（Zink 或 MobileGlues）；追求画质：关 FSR 用原生化渲染。若未来上游（Sodium 系或 Mojang）产出运动向量，启动器侧接入时域放大会重新评估。";

    LauncherHelpFaqItem *armAsr = [[LauncherHelpFaqItem alloc] init];
    armAsr.iconName = @"speedometer";
    armAsr.question = @"能不能用 Arm ASR（Arm Accuracy Super Resolution）代替 FSR？";
    armAsr.answer = @"短答案：现阶段不引入。Arm ASR 与 MetalFX 时域不同，它没有运动向量的硬依赖（和 FSR 1.0 一样是单帧空间超分，本身就是从 FSR1 衍生调优来的），卡点在实现形态与收益两端：\n\n"
                    @"【为什么接不上】\n"
                    @"Arm ASR 的官方实现是面向 Vulkan/DX12 的计算着色器（compute shader），而 Zink 走系统 Vulkan 栈时给游戏的 OpenGL 上限是 4.1——不含 4.3 才有的计算着色器，参考实现原样跑不起来；要移植只能把它的算法改写成片元着色器（与启动器内置 FSR 同样的做法）。\n\n"
                    @"【为什么收益小】\n"
                    @"Arm ASR 的性能卖点主要来自为 Mali GPU（Arm 自家 GPU）调优的计算着色器分块与共享内存访存；在 Apple GPU 上经片元管线跑，这些优势全部消失，剩下的画质差异相对 FSR1 很小（同为 FSR1 衍生算法）。\n\n"
                    @"【现在的建议】\n"
                    @"Zink 上最实际的帧率提升就是把 FSR 用起来：最新版本已补齐 Zink 的 GLSL 4.1 适配（版本自动降级 + 半精度打包函数补齐）。若未来切换到原生 Vulkan/Metal 呈现路径（有计算着色器），ASR 与 MetalFX 空间版会重新评估。";

    LauncherHelpFaqItem *upscalerAlt = [[LauncherHelpFaqItem alloc] init];
    upscalerAlt.iconName = @"wand.and.stars";
    upscalerAlt.question = @"FSR 1.0 有哪些替代方案？为什么最后还是选它？";
    upscalerAlt.answer = @"单帧空间放大这一类算法里，可选方案和结论如下（2024-2025 年公开评测与源码调研）：\n\n"
                    @"【NVIDIA NIS（Image Scaling）】开源（MIT）、单 pass 放大+锐化合一、跨平台（AMD/Intel 也能用）。公开对比评测的结论是画质与 FSR 1 同级、几乎一致；理论上单 pass 更省带宽。这是唯一值得未来考虑的同级替代——接入需要做一轮 GLSL 版本适配（与我们已完成的 FSR 适配同量级工作量）。\n\n"
                    @"【Qualcomm GSR（Game Super Resolution）】开源（BSD-3）、单 pass 空间放大。卖点是专为 Adreno GPU 的波占用率调优——Apple GPU 上这些优化全部落空，画质又与 FSR1 同源同级，换它没有收益。\n\n"
                    @"【Apple MetalFX 空间版】Digital Foundry 在生化危机 Mac 版的实测画质还不如 FSR 1（同一游戏引擎、同为空间放大），且接入需 iOS 16+／A13+ 与额外的纹理互操作层。\n\n"
                    @"【Anime4K／FSRCNNX 等视频系算法】面向动画内容的边缘重建，通用 3D 场景收益不稳定，计算量也更高，不适合游戏实时全屏放大。\n\n"
                    @"【时域家族（DLSS／FSR 2-3／XeSS／MetalFX Temporal／Arm ASR）】画质上限确实高一档，但全部依赖游戏引擎输出的运动向量／深度／抖动序列——启动器侧无法凭空合成，详见前两条 Arm ASR 与 MetalFX 的说明。\n\n"
                    @"结论：FSR 1 的 EASU 在\"单帧空间放大\"类别里本就是第一梯队画质（部分实测还优于 MetalFX 空间版），我们且已完成 Zink 的 GL 4.1 适配；换任何同级算法收益都小于一次适配的风险。真正的画质跃升点在未来时域输入可用之时。";

    LauncherHelpFaqItem *fpsUnlock = [[LauncherHelpFaqItem alloc] init];
    fpsUnlock.iconName = @"timer";
    fpsUnlock.question = @"帧率上限 / 垂直同步怎么调？";
    fpsUnlock.answer = @"• 帧率上限：游戏内 视频设置 → 最大帧率（也可在启动器 Java 参数里看到 -Dmax.fps 解锁层）。设为\"无限制\"或高数值即靠上限；\n"
                       @"• 垂直同步：游戏内 视频设置 → 垂直同步 关闭后，各渲染器的呈现模式会切到立即呈现（不再等待刷新率），高刷设备收益明显；\n"
                       @"• 帧率仍上不去时先分辨瓶颈：GPU 满载（降视距/开 FSR）还是区块加载卡（换 Zink/降视距）；\n"
                       @"• 帧率波动大但平均不低：多为区块流式风暴，参考 MobileGlues 卡顿一条。";

    LauncherHelpFaqItem *blurry = [[LauncherHelpFaqItem alloc] init];
    blurry.iconName = @"eye";
    blurry.question = @"画面模糊 / 发虚怎么办？";
    blurry.answer = @"常见原因与对策：\n\n"
                    @"1. FSR 档位太低（均衡/性能优先）：换\"超高品质\"或关闭 FSR 对比；\n"
                    @"2. 分辨率滑条被手动调低过：恢复 100%（降分辨率应优先用 FSR 档位，画质好得多）；\n"
                    @"3. 历史版本的 1x 钉扎模糊已修复（渲染表面与物理像素 1:1），如再现请反馈；\n"
                    @"4. UI 缩放调太低：游戏内 视频设置 → 界面缩放 调大。\n\n"
                    @"提示：判断\"糊\"还是\"分辨率低\"——截图放大看方块边缘：锯齿状=分辨率，雾蒙蒙=滤镜/缩放。";

    LauncherHelpFaqItem *shader = [[LauncherHelpFaqItem alloc] init];
    shader.iconName = @"sun.max";
    shader.question = @"光影（Iris/OptiFine）和优化模组能装吗？有哪些坑？";
    shader.answer = @"可以，但务必注意版本配对（社区最高频崩溃原因）：\n\n"
                    @"1. Iris 与 Sodium 版本强绑定：Iris 会固定要求的 Sodium 版本，只更新其中一个会报\"模组不兼容\"（Some of your mods are incompatible）——两个一起更新，或都用启动器推荐版本；\n"
                    @"2. 26.x 的 Sodium 系列另有 Sodium Options API 等依赖，报错信息里出现 dependency conflicts 时按提示补齐/对齐版本；\n"
                    @"3. OptiFine 与 Sodium/Iris 互斥，不要同时安装；\n"
                    @"4. 光影对 GPU 压力大：先用中低档光影测试，稳定后再上高强度；开光影后建议 Zink 渲染器 + FSR；\n"
                    @"5. 装完模组启动崩溃：先看崩溃报告\"Caused by\"段（游戏内菜单可查看），十有八九是版本不匹配而不是启动器问题。";

    LauncherHelpFaqItem *keyboard = [[LauncherHelpFaqItem alloc] init];
    keyboard.iconName = @"keyboard";
    keyboard.question = @"游戏里怎么打字（聊天、命令、命名）？两个键盘按钮有什么区别？";
    keyboard.answer = @"先说用法：打字前要先打开文本框（点聊天按钮或按 T 键打开聊天），再打字才会进框。\n\n"
                      @"两种键盘，两个按钮，作用不同：\n\n"
                      @"【系统键盘】✎ 图标（\"输入法\"按钮）\n"
                      @"弹的是 iOS 系统软键盘，支持中文输入法、联想、emoji。触发方式：\n"
                      @"1. 点按控件布局上的\"✎ 输入法\"按钮（再点一次收起）；\n"
                      @"2. 或双指长按屏幕（需先在 设置 → 控制 → 双指呼出键盘 中开启）。\n\n"
                      @"【按钮键盘】⌨ 图标（\"键盘\"抽屉）\n"
                      @"展开后是一整面按键面板（QWERTY + 符号 + F 键），按字母直接上屏，不弹系统键盘：\n"
                      @"• 按住 SHIFT 再按字母出大写；\"大写锁定\"按钮可切换大小写状态；\n"
                      @"• 符号键受 SHIFT 影响（如 SHIFT+, 出 <）；\n"
                      @"• Ctrl/Alt 按住时按字母是快捷键语义，不进文本（和真实键盘一致）。\n\n"
                      @"排障：\n"
                      @"1. 按字母没反应：确认聊天框已打开（T 键或聊天按钮）；\n"
                      @"2. 早期版本⌨ 面板完全点不动（面板背景板吞掉了触摸，已修复）；老安装升级后第一次进游戏若仍异常，可在键位调整里“恢复默认控件”拿最新出厂布局；\n"
                      @"3. 某个具体按键行为不对（如符号错位）：可能是自定义布局改过键位，恢复默认控件即可。\n"
                      @"4. 仍无效请上传日志反馈（日志里能看到每个按钮的触发记录）。";

    LauncherHelpFaqItem *joystick = [[LauncherHelpFaqItem alloc] init];
    joystick.iconName = @"gamecontroller";
    joystick.question = @"摇杆推了没反应 / 必须按住 Shift 才能动？";
    joystick.answer = @"这类问题在新版本中已系统性修复（虚拟按键状态直写 + 键位档自动纠错 + 摇杆心跳重发），正常情况下推杆即走。\n\n"
                      @"如果仍遇到：\n"
                      @"1. 检查 设置 → 控制 → 默认控件方案 是否为\"custom\"（自定义布局）；\n"
                      @"2. 检查游戏内 按键绑定 是否被改坏（恢复默认即可）；\n"
                      @"3. 升级到最新构建后再试一次——旧构建的输入修复不完整。";

    LauncherHelpFaqItem *peripheral = [[LauncherHelpFaqItem alloc] init];
    peripheral.iconName = @"magicmouse";
    peripheral.question = @"蓝牙鼠标 / 手柄连接有什么注意事项？";
    peripheral.answer = @"• 蓝牙鼠标：最好在启动游戏之前连接/打开。游戏中途开启的鼠标偶尔不会被识别（上游已知问题），遇到时退出游戏重进一次即可；\n"
                        @"• 鼠标指针锁定：进入游戏抓取视角后指针自动锁定；设置里有\"隐藏硬件指针\"选项按需开关；\n"
                        @"• 手柄：支持 Xbox 布局（设置 → 控制 → 手柄类型 可切换），摇杆/扳机/肩键均有默认映射，可用按键绑定自定义；\n"
                        @"• 手柄漂移/不识别：先在系统设置里确认手柄本身正常，再检查游戏内按键绑定是否被清空。";

    LauncherHelpFaqItem *layout = [[LauncherHelpFaqItem alloc] init];
    layout.iconName = @"rectangle.3.group";
    layout.question = @"自定义控件布局怎么编辑？改坏了怎么恢复？";
    layout.answer = @"编辑：游戏内打开菜单 → 键位调整（或在 设置 → 控制 → 默认控件方案 选 custom 后进入编辑），支持拖动、缩放、加按钮/抽屉/摇杆，改完保存为新布局。\n\n"
                    @"恢复：编辑界面里有\"恢复默认控件\"——出厂布局会删除重建（自建的其他布局不受影响）。布局文件损坏导致进游戏零控件时，启动器会自动回落默认布局保住可玩性。\n\n"
                    @"提示：出厂 custom 布局带一整面\"键盘图标\"抽屉（按键面板），常用键都有；\"恢复默认控件\"也会拿到修正过键位的最新出厂版本。";

    LauncherHelpFaqItem *modpack = [[LauncherHelpFaqItem alloc] init];
    modpack.iconName = @"shippingbox";
    modpack.question = @"安装整合包提示\"缺少父版本 JSON / json 丢失\"？";
    modpack.answer = @"新版已支持自动补拉：整合包安装过程中父版本 JSON 缺失或损坏时，启动器会自动从 Mojang 官方源与 BMCLAPI 镜像双源补拉，通常无需手动预装原版。\n\n"
                     @"如果仍失败：\n"
                      @"1. 检查网络（两个源都不通才会报错）；\n"
                      @"2. 也可先在下载页手动安装对应原版版本再装整合包；\n"
                      @"3. 重试前完全退出启动器再打开。";

    LauncherHelpFaqItem *modInstall = [[LauncherHelpFaqItem alloc] init];
    modInstall.iconName = @"puzzlepiece.extension";
    modInstall.question = @"模组怎么安装？装完崩溃/报不兼容？";
    modInstall.answer = @"安装：把 .jar 放进对应版本的 mods 文件夹（版本隔离开启时在 实例目录/versions/版本名/mods）。Fabric 模组需要先装 Fabric Loader，Forge 同理。\n\n"
                        @"崩溃排查顺序：\n"
                        @"1. 看崩溃报告的\"Caused by\"与\"Mixin apply failed\"段——绝大多数是模组间版本冲突或与 MC 版本不匹配；\n"
                        @"2. 优化类模组（Sodium/Iris/Lithium 等）互相之间以及和其它渲染类模组冲突高发，新增模组后逐个排查；\n"
                        @"3. 同名功能模组二选一（两种小地图、两种优化包不能共存）；\n"
                        @"4. 全部移除后仍崩溃再来怀疑启动器——这时请带上日志反馈。";

    LauncherHelpFaqItem *javaVersion = [[LauncherHelpFaqItem alloc] init];
    javaVersion.iconName = @"curlybraces";
    javaVersion.question = @"不同 MC 版本要用哪个 Java？";
    javaVersion.answer = @"启动器会按游戏版本自动选择正确的 Java 运行时，一般无需手动干预：\n\n"
                         @"• MC 26.x（年份制新版本）→ Java 25；\n"
                         @"• MC 1.20.5 – 1.21.x → Java 21；\n"
                         @"• MC 1.18 – 1.20.4 → Java 17；\n"
                         @"• MC 1.17 → Java 16；\n"
                         @"• MC 1.16.5 及更早 → Java 8。\n\n"
                         @"整合包 profile 里声明的 javaVersion 启动器会自动纠正（旧版整合包写错的值不再影响启动）。手动安装 Forge 时若提示 Java 版本不符，检查启动器的 Java 运行时设置是否被改过。";

    LauncherHelpFaqItem *memory = [[LauncherHelpFaqItem alloc] init];
    memory.iconName = @"internaldrive";
    memory.question = @"内存分配和性能有哪些建议？";
    memory.answer = @"默认自动分配已按设备物理内存的合理比例设置（大内存设备约 50%），一般够用。手动调整参考：\n\n"
                    @"• 4GB 设备：2–3GB；\n"
                    @"• 6GB 设备：3–4GB；\n"
                    @"• 8GB 及以上：4–5GB 足够（MC 本体吃不满更多；分太多反而让系统/渲染进程紧张）。\n\n"
                    @"其它性价比提示：\n"
                    @"• 视距 10 是甜点位，调大主要增加加载风暴时长和内存占用；\n"
                    @"• 渲染分辨率：优先用 FSR 档位降分辨率，而不是手动调分辨率滑条；\n"
                    @"• 卡顿时先分清是\"加载区块卡\"（换 Zink / 开 FSR / 降视距）还是\"整体帧率低\"（降视距/分辨率/光影），对症下药。";

    LauncherHelpFaqItem *data = [[LauncherHelpFaqItem alloc] init];
    data.iconName = @"folder";
    data.question = @"启动器的数据（存档、模组、布局）存在哪里？怎么备份？";
    data.answer = @"全部在应用沙盒 Documents 目录（POJAV_HOME）下：\n\n"
                  @"• versions/：游戏版本与隔离的模组/配置；\n"
                  @"• saves/：存档；\n"
                  @"• controlmap/：自定义控件布局（default.json 为默认布局，可在 设置 → 键位调整 里编辑）；\n"
                  @"• MG/：MobileGlues 渲染器配置（config.json，含 FSR 档位）。\n\n"
                  @"备份：通过\"文件\"App 或侧边栏的文件管理入口把整个 Documents 目录拷出即可；换机/重装时拷回同位置。卸载重装启动器会清空沙盒数据，重要存档请先备份。\n\n"
                  @"日志 latestlog.txt 也在这里——反馈问题时直接取用。";

    LauncherHelpFaqItem *download = [[LauncherHelpFaqItem alloc] init];
    download.iconName = @"arrow.down.circle";
    download.question = @"下载版本/资源很慢或失败？";
    download.answer = @"启动器使用 Mojang 官方源与 BMCLAPI 镜像双源，失败时会自动切换重试。仍慢/失败时：\n\n"
                      @"1. 确认网络对 piston-meta.mojang.com 或 bmclapi2.bangbang93.com 至少一个可达；\n"
                      @"2. 校验下载源设置（设置里可切换首选源），国内网络优先 BMCLAPI；\n"
                      @"3. 版本清单加载失败：完全退出启动器重开（远端清单会重新拉取）；\n"
                      @"4. 大文件（资源包/整合包）中断：重新点下载会续传/重试，不需要清数据。";

    LauncherHelpFaqItem *xray = [[LauncherHelpFaqItem alloc] init];
    xray.iconName = @"eye.fill";
    xray.question = @"方块、实体、云层出现\"透视/穿透\"怎么办？";
    xray.answer = @"这通常是 Sodium 模组的\"改进透明\"选项与渲染器之间的兼容性问题，不是启动器或存档坏了。\n\n"
                  @"解决方法：游戏内打开 视频设置 → Sodium → 找到\"改进透明\"（Improve transparency / 半透明排序）并关闭，穿透即消失。\n\n"
                  @"此问题与渲染器类型无关，换 Zink 或 MobileGlues 都可能遇到，关闭该选项即可。";

    LauncherHelpFaqItem *greenFx = [[LauncherHelpFaqItem alloc] init];
    greenFx.iconName = @"paintpalette";
    greenFx.question = @"开 FSR 后画面出现绿色/花屏区域（尤其 Zink）？";
    greenFx.answer = @"已修复（两轮）。原因：Zink 走系统 Vulkan 栈，其着色器语言（GLSL）上限是 4.1，而 FSR 升采样着色器声明的是 4.5——旧版本里编译失败后走了降级路径，但降级没能真正告诉游戏\"恢复全分辨率渲染\"，导致画面只有左下角一块在渲染、其余区域是未初始化的显存内容（表现为绿色/花屏大块区域）。\n\n"
                     @"修复经历了两轮：\n"
                     @"1. 第一轮：着色器版本自动适配 Zink 的 GLSL 上限 + 升采样不可用时真正切回全分辨率渲染（不再留绿屏）；\n"
                     @"2. 第二轮：补齐 4.1 缺失的半精度打包函数、勘误着色器类型常量——Zink 下升采样从此可以正常启用（不再依赖降级）。\n\n"
                     @"如仍见到绿色区域：请上传 latestlog.txt 反馈（日志里能看出走的是哪条路径）。";

    LauncherHelpFaqItem *background = [[LauncherHelpFaqItem alloc] init];
    background.iconName = @"rectangle.on.rectangle";
    background.question = @"切到后台再回来，游戏冻结/黑屏/掉帧异常？";
    background.answer = @"这是 iOS 对 GPU 后台权限的限制，Zink（Vulkan）路径下尤其明显：App 退到后台时，系统会立刻回收 GPU 提交权限，而游戏渲染线程若还在提交工作，Vulkan 设备就会永久丢失（日志里表现为 VK_ERROR_DEVICE_LOST / zink: DEVICE LOST），回到前台后画面冻结、触摸无响应。\n\n"
                        @"现状与建议：\n"
                        @"1. 游戏中尽量别切后台（分屏拉通知栏/控制中心一般没事，完整切换才会触发）；\n"
                        @"2. 已发生冻结：只能退出游戏重进（Vulkan 设备丢失不可恢复）；\n"
                        @"3. 需要频繁切后台的场景（查攻略等）：用 MobileGlues 渲染器（Metal 路径对后台切换更宽容）或用其他设备查攻略；\n"
                        @"4. 短暂回前台后花屏但还能玩：属帧队列残留，多玩几秒会自愈。\n\n"
                        @"注：这不是内存不足，也不是启动器杀进程——加大内存分配无效。设备丢失的自动恢复需要底层重建 Vulkan 设备，已在路线图上。";

    LauncherHelpFaqItem *crash = [[LauncherHelpFaqItem alloc] init];
    crash.iconName = @"exclamationmark.triangle";
    crash.question = @"遇到崩溃/黑屏该怎么反馈？";
    crash.answer = @"最有价值的是日志文件 latestlog.txt（位于启动器沙盒 Documents 目录，游戏内也可通过菜单查看）：每次游戏会话结束后它会自动保留，把它连同以下信息一起反馈即可：\n\n"
                   @"1. 设备型号与系统版本（如 iPad Air M4 / iPadOS 26.6）；\n"
                   @"2. 游戏版本与模组列表（如 26.3 + Sodium）；\n"
                   @"3. 渲染器与 FSR 设置；\n"
                   @"4. 问题发生的时机（进世界时/游玩中/暂停回来时）。\n\n"
                   @"大多数问题可以只靠日志定位，不需要录屏。历史上仅凭日志就定位过的典型案例：取档瞬间的渲染竞态崩溃、区块管线上译开销、Sodium 透明排序穿透等。";

    LauncherHelpFaqItem *stuck = [[LauncherHelpFaqItem alloc] init];
    stuck.iconName = @"questionmark.circle";
    stuck.question = @"\"卡在某个界面/转圈/闪退\"的通用自救步骤？";
    stuck.answer = @"按顺序尝试（每步后重试）：\n\n"
                   @"1. 完全退出启动器（上划杀进程）再打开——解决大部分瞬时状态问题；\n"
                   @"2. 换一个渲染器试（Zink ↔ MobileGlues）——区分渲染器问题还是环境问题；\n"
                   @"3. 关闭 FSR/降低分辨率——排除升采样路径；\n"
                   @"4. 新建一个纯净存档/无模组版本进入——排除存档与模组因素；\n"
                   @"5. 还不行：带着 latestlog.txt 反馈（见上条），说明走到第几步、卡在什么画面。\n\n"
                   @"不要随手\"清除所有数据\"——多数问题与数据无关，清了既丢存档又不解决问题。";

    self.categories = @[ @"渲染与性能", @"输入与控制", @"安装与数据", @"故障排除" ];
    self.itemsByCategory = @[
        @[ renderer, mgLag, fsr, metalFx, armAsr, upscalerAlt, fpsUnlock, blurry, shader ],
        @[ keyboard, joystick, peripheral, layout ],
        @[ modpack, modInstall, javaVersion, memory, data, download ],
        @[ xray, greenFx, background, crash, stuck ]
    ];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"使用问题";

    // 与其他内容页一致：透出全局背景（图片/视频/毛玻璃）
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.expandedPaths = [NSMutableSet set];
    [self buildFaqData];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"HelpFaqCell"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 收起大标题，保持列表可视面积
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.categories.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.categories[section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.itemsByCategory[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HelpFaqCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor secondarySystemBackgroundColor];

    LauncherHelpFaqItem *item = self.itemsByCategory[indexPath.section][indexPath.row];
    BOOL expanded = [self.expandedPaths containsObject:@(indexPath.row * 1000 + indexPath.section)];

    // 问题行：图标 + 问题 + 展开指示箭头
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:item.question
                                                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor
    }];
    if (expanded) {
        // 答案直接拼进同一 cell（动态行高展开），问题与答案之间空一行
        NSString *answerBlock = [NSString stringWithFormat:@"\n\n%@", item.answer];
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:answerBlock
                                                                       attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:14],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor
        }]];
    }
    cell.textLabel.attributedText = title;
    cell.textLabel.numberOfLines = 0;

    UIImage *icon = [UIImage systemImageNamed:item.iconName];
    cell.imageView.image = [icon imageWithTintColor:accentColor()
                              renderingMode:UIImageRenderingModeAlwaysOriginal];

    cell.accessoryType = expanded ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *key = @(indexPath.row * 1000 + indexPath.section);
    if ([self.expandedPaths containsObject:key]) {
        [self.expandedPaths removeObject:key];
    } else {
        [self.expandedPaths addObject:key];
    }
    // 只刷新这一行（展开/收起动画），避免整表 reload 造成的滚动位置跳动
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
}

@end
