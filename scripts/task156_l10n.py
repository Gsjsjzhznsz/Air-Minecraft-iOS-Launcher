#!/usr/bin/env python3
"""Task 156 l10n batch:
1) new key background.effect.footer (blur/opacity slider semantics) in 6 languages
2) rewrite preference.detail.fsr1_setting -- honest mg-family support statement
   (Task154 retired launcher-side FSR on MobileGL Vulkan/ES; users kept reporting
   "FSR unusable on es/vulkan" -- the row must say where it works and where to
   use video.resolution instead)
Updates every lproj's key count 1945 -> 1946.
"""
import io, re, sys

BASE = "Natives/resources"

FOOTER = {
    "zh-Hans": "上方“透明度”控制界面材质的不透明程度（数值越低，壁纸透出越多）；下方“模糊程度”控制背景高斯模糊的强度（数值越低，背景越清晰）。仅在“UI效果”选择毛玻璃或半透明时生效。",
    "zh-CN":   "上方“透明度”控制界面材质的不透明程度（数值越低，壁纸透出越多）；下方“模糊程度”控制背景高斯模糊的强度（数值越低，背景越清晰）。仅在“UI效果”选择毛玻璃或半透明时生效。",
    "zh-Hant": "上方「透明度」控制介面材質的不透明程度（數值越低，桌布透出越多）；下方「模糊程度」控制背景高斯模糊的強度（數值越低，背景越清晰）。僅在「UI效果」選擇毛玻璃或半透明時生效。",
    "en":      "Opacity controls how translucent the UI material is (lower = more wallpaper shows through). Blur Level controls the strength of the background Gaussian blur (lower = sharper background). Both only take effect when UI Effect is set to Blur or Translucent.",
    "ja":      "「不透明度」はUI素材の不透明度を制御します（低いほど壁紙が透けて見えます）。「ぼかしレベル」は背景のガウスぼかしの強さを制御します（低いほど背景が鮮明になります）。UI効果がぼかし/半透明に設定されている場合のみ有効です。",
    "km":      "Opacity គ្រប់គ្រងភាពស្រអាប់នៃវត្ថុ UI (កាន់តែទាប = ផ្ទាំងរូបភាពបង្ហាញច្រើនជាង)។ Blur Level គ្រប់គ្រងកម្រិតនៃការធ្វើឱ្យព្រិល Gaussian នៃផ្ទៃខាងក្រោយ (កាន់តែទាប = ផ្ទៃខាងក្រោយច្បាស់ជាង)។ មានប្រសិទ្ធភាពនៅពេល UI Effect ត្រូវបានកំណត់ទៅ Blur ឬ Translucent ប៉ុណ្ណោះ។",
}

FSR = {
    "zh-Hans": "AMD FidelityFX Super Resolution 1.0 超分辨率。选择档位即自动降低渲染分辨率（超高品质 77%／高品质 67%／均衡 59%／性能优先 50%），再由渲染器放大回全分辨率表面。仅对 MobileGlues（内置 FSR1）与 Zink（EASU 升采样）渲染器生效；mg 系列（Vulkan／ES／OpenGL 4.0 后端）、MoltenVK、gl4es 均不支持启动器侧 FSR——这些渲染器需要画质／帧率权衡时，请改用视频设置中的「分辨率」缩放。",
    "zh-CN":   "AMD FidelityFX Super Resolution 1.0 超分辨率。选择档位即自动降低渲染分辨率（超高品质 77%／高品质 67%／均衡 59%／性能优先 50%），再由渲染器放大回全分辨率表面。仅对 MobileGlues（内置 FSR1）与 Zink（EASU 升采样）渲染器生效；mg 系列（Vulkan／ES／OpenGL 4.0 后端）、MoltenVK、gl4es 均不支持启动器侧 FSR——这些渲染器需要画质／帧率权衡时，请改用视频设置中的「分辨率」缩放。",
    "zh-Hant": "AMD FidelityFX Super Resolution 1.0 超解析度。選擇檔位即自動降低渲染解析度（超高品質 77%／高品質 67%／均衡 59%／效能優先 50%），再由渲染器放大回全解析度表面。僅對 MobileGlues（內建 FSR1）與 Zink（EASU 昇採樣）渲染器生效；mg 系列（Vulkan／ES／OpenGL 4.0 後端）、MoltenVK、gl4es 均不支援啟動器側 FSR——這些渲染器需要畫質／幀率取捨時，請改用影片設定中的「解析度」縮放。",
    "en":      "AMD FidelityFX Super Resolution 1.0 upscaling. Picking a preset lowers the render resolution (Ultra Quality 77% / Quality 67% / Balanced 59% / Performance 50%) and the renderer upscales it back to the full-resolution surface. Only works with the MobileGlues (built-in FSR1) and Zink (EASU) renderers. The mg family (Vulkan / ES / OpenGL 4.0 backends), MoltenVK and gl4es do not support launcher-side FSR -- for those renderers use the Resolution scaler in Video settings instead.",
    "ja":      "AMD FidelityFX Super Resolution 1.0 アップスケーリング。プリセットを選ぶと描画解像度が下がり（超高品質 77%／高品質 67%／バランス 59%／パフォーマンス 50%）、レンダラーがフル解像度表面へ拡大します。MobileGlues（内蔵 FSR1）と Zink（EASU）レンダラーのみ有効。mg ファミリー（Vulkan／ES／OpenGL 4.0 バックエンド）、MoltenVK、gl4es はランチャー側 FSR 非対応です--これらのレンダラーでは映像設定の「解像度」スケーラーを使用してください。",
    "km":      "AMD FidelityFX Super Resolution 1.0 upscaling. Picking a preset lowers the render resolution (Ultra Quality 77% / Quality 67% / Balanced 59% / Performance 50%) and the renderer upscales it back to the full-resolution surface. Only works with the MobileGlues (built-in FSR1) and Zink (EASU) renderers. The mg family (Vulkan / ES / OpenGL 4.0 backends), MoltenVK and gl4es do not support launcher-side FSR -- for those renderers use the Resolution scaler in Video settings instead.",
}

for lang in ["zh-Hans", "zh-CN", "zh-Hant", "en", "ja", "km"]:
    path = f"{BASE}/{lang}.lproj/Localizable.strings"
    with io.open(path, "r", encoding="utf-8") as f:
        text = f.read()

    # 1) replace FSR detail value (single-line entry)
    pat = re.compile(r'^"preference\.detail\.fsr1_setting" = ".*";$', re.M)
    m = pat.search(text)
    assert m, f"{lang}: fsr detail line not found"
    text = pat.sub(lambda _: '"preference.detail.fsr1_setting" = "%s";' % FSR[lang], text, count=1)

    # 2) insert footer key after the bing.footer.hint line (keeps grouping)
    if '"background.effect.footer"' in text:
        print(f"[task156] {lang}: footer key already present")
    else:
        anchor_pat = re.compile(r'^"bing\.footer\.hint" = ".*";$', re.M)
        m2 = anchor_pat.search(text)
        assert m2, f"{lang}: bing.footer.hint anchor not found"
        insert_line = '\n"background.effect.footer" = "%s";' % FOOTER[lang]
        text = text[:m2.end()] + insert_line + text[m2.end():]

    with io.open(path, "w", encoding="utf-8") as f:
        f.write(text)

    # report key count
    n = len(re.findall(r'^"[^"]+"\s*=', text, re.M))
    print(f"[task156] {lang}: fsr detail rewritten, footer added, key count = {n}")
