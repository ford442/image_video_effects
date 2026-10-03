# Kimi Claw Prompt - Showcase Shader Batch Generator
## 版本:Batch 1(2024-06-07)
## 目标:一次性生成 3 个不同视觉家族的展示级着色器

你正在为 Pixelocity 项目的 Generative Showcase 模式开发高质量展示级着色器。

**核心目标**:为 Generative Showcase 模式创建视觉冲击力强、idle 状态下就很吸引人、按 SPACE 锁定后有明显"claim"反馈、并且支持音频反应的生成式着色器。

**必须严格遵守**:
- 完全遵循 `WGSL_BUILTINS_GENERATIVE.md` 中的规范(通用 uniform 结构、hot-swap 流程、naga 验证通过、性能目标等)。
- 输出格式必须是:只输出 `.wgsl` 文件内容 + 对应的 JSON 条目。
- 着色器必须在 idle(未锁定)状态下有强烈的 hypnotic / 视觉吸引力,适合 12 秒自动轮播。
- 当 `mouseActive = 1.0` 时(用户按 SPACE 锁定),必须有明显、令人满意的视觉升级(强度、复杂度、运动速度等明显增强)。
- 通过 `zoomParam1-4` + `audio` (bass/mid/treble) 实现音频反应。

**本次任务**:请按顺序逐个生成下面 3 个不同视觉家族的展示级着色器。一次只输出一个完整的着色器(WGSL + JSON),等用户确认后再生成下一个:

1. **Ethereal Silk**(有机流动类)
2. **Fractal Ember**(分形晶格类)
3. **Nebula Pulse**(粒子能量场类)

**质量优先级说明**:
如果一次性生成 3 个着色器会导致整体质量下降,请优先保证 **Ethereal Silk** 和 **Fractal Ember** 的质量,Nebula Pulse 可以适当简化或降低复杂度。目标是产出至少 2 个高质量、可直接用于 Showcase 的着色器。

**输出安全策略**:
- 一次只输出一个着色器的完整内容(WGSL 代码 + JSON 配置)。
- JSON 必须包裹在 ```json 代码块中,确保格式完整。
- 如果输出超长,请主动说"内容较长,正在分步输出",先完成当前着色器再说下一个。

**输出要求**：
- 每个着色器单独输出完整 WGSL 代码 + 对应的 JSON 条目。
- JSON 中要包含合适的 `showcase` 标签和参数说明。
- 在每个着色器开头用注释写清楚设计意图（Idle / Claim / Audio 行为）。
- **JSON 必须包裹在 ```json 代码块中**，确保格式完整可解析。
- 优先保证视觉质量和 showcase 体验，其次再考虑参数丰富度。
- 如果输出过长，请分步输出：先完成 WGSL 代码，再输出 JSON 配置。

请按顺序输出这 3 个着色器。完成后告诉我每个着色器的核心亮点和潜在需要微调的地方。
