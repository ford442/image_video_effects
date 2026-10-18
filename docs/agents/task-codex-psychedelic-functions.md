Task: 在 `WGSL_BUILTINS_GENERATIVE.md` 中新增 5 个高性能、Naga 安全的 psychedelic 工具函数。

需要添加的函数：

1. `psychedelicPalette(t: f32) -> vec3<f32>`
   时间驱动的 HSV 彩虹色板（可用于循环变色）

2. `neonGlow(color: vec3<f32>, intensity: f32) -> vec3<f32>`
   简洁的辉光增强（用于边缘发光）

3. `organicDrift(uv: vec2<f32>, time: f32, scale: f32) -> vec2<f32>`
   基于 noise 的有机位移（用于丝绸、液体、云类效果）

4. `pulseScale(time: f32, speed: f32) -> f32`
   平滑的呼吸式缩放动画

5. `chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32>`
   RGB 分离色差（可受音频或参数控制）

要求：
- 必须 Naga 安全（无 3D 纹理、无无界数组）
- 性能友好（适合 Showcase 长时间轮播）
- 每个函数都要带简短的使用示例注释
- 添加到 `WGSL_BUILTINS_GENERATIVE.md` 的合适位置（建议新建 `Psychedelic Utilities` 章节）

完成后报告新增函数的位置和验证结果。
