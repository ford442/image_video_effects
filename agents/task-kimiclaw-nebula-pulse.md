# Task: Generate Nebula Pulse Showcase Shader

## 目标
生成第 3 个 Showcase 着色器 **Nebula Pulse**（粒子能量云/星云），完成 Showcase 家族三部曲。

## 参考标准
- `agents/design-nebula-pulse.md` — 设计文档（视觉概念、行为要求、音频映射、参数建议）
- `agents/showcase-checklist-v1.md` — 验收清单
- `agents/prompt-showcase-batch-1.md` — 生成 prompt 模板

## 已完成的 Showcase 参考（质量和风格）
- `gen-ethereal-silk-veil` — A+ 评分，多层丝绸飘带，鼠标聚集，4 参数
- `gen-fractal-ember-lattice` — A+ 评分，六边形晶格碎裂，状态机，重组动画

## 视觉概念
由无数微小粒子组成的能量云/星云，像深空中的星爆或能量场。粒子有**组织性**——形成旋涡、波纹、或脉动的球状结构。色调以深紫、靛蓝、电蓝、亮白为主，带有明显的"宇宙感"和"能量感"。

对比：
- Ethereal Silk = 柔和、丝绸、流动
- Fractal Ember = 锐利、晶格、碎裂
- **Nebula Pulse = 有机、弥漫、能量、粒子**

## 核心行为要求

### Idle 状态（未锁定）
- 缓慢呼吸式的粒子扩散与收缩（像能量心脏在跳动）
- 12 秒内持续吸引人，粒子形成不断演化的图案（旋涡 → 波纹 → 球面波）
- 粒子数量要足够多（视觉上密集），但用噪声场驱动而非 O(n²) 交互
- 需要有**催眠感**，让人愿意一直看下去

### Mouse Claim 状态（锁定后）
- 鼠标附近粒子被**吸引聚集**，形成更亮、更密集的核心
- 聚集过程中亮度增加、运动速度加快、轨迹拖尾变长
- 鼠标移动时聚集核心跟随移动，像被拖拽的微型恒星
- 松开鼠标后粒子缓慢扩散回原始状态，不要瞬间消失
- Claim 后的变化要**明显且令人满足**，但不要破坏整体星云美感

### 音频反应映射
| 频段 | 映射 | 强度 |
|------|------|------|
| **Bass** | 粒子聚集强度 + 脉动幅度 | 高 |
| **Mid** | 粒子运动速度 + 旋涡频率 | 中 |
| **Treble** | 粒子闪烁 + 能量爆发 | 中高 |

### 参数设计（zoomParam1-4）
- `zoomParam1`：粒子扩散/收缩速度 + 整体脉动频率
- `zoomParam2`：粒子聚集密度 + 核心亮度
- `zoomParam3`：旋涡复杂度 / 图案演化速度
- `zoomParam4`：粒子拖尾长度 + 能量爆发强度

## 技术要求
- 必须符合 `WGSL_BUILTINS_GENERATIVE.md` 的规范
- 粒子系统性能友好：用噪声场驱动运动，避免粒子间交互
- 颜色深邃高级（深紫/靛蓝/电蓝/亮白），不能太"塑料"
- 粒子运动有"记忆"——受噪声场引导，形成可预测的美感
- Idle 时性能要好，适合长时间轮播
- naga 验证通过，无编译错误
- JSON 配置完整，含 showcase 标签和参数说明

## 输出要求
1. **WGSL 文件**：完整、可编译的代码，含 `gen-` 前缀的函数名
2. **JSON 配置**：包含在代码块中（```json 包裹）
3. **注释**：在代码中标注 Idle / Claim / Audio 行为区域

## 重要提示
- **一次只生成这一个 shader**（避免输出截断）
- 如果生成过程中被截断，请从断点处继续
- JSON 必须完整且格式正确，用 ```json 代码块包裹

## 验收标准（自检查）
- [ ] Idle 12 秒内持续吸引人，粒子形成不断演化的图案
- [ ] 运动自然流畅，有呼吸/脉动感
- [ ] 颜色深邃高级（深紫/靛蓝/电蓝/亮白）
- [ ] Claim 时粒子聚集效果明显且令人满足
- [ ] 聚集核心有亮度/速度增强，松开后自然扩散
- [ ] Bass 控制聚集强度，Mid 控制旋涡，Treble 控制闪烁爆发
- [ ] naga 验证通过
- [ ] JSON 配置完整，含 showcase 标签

## 交付文件
- `public/shaders/gen-nebula-pulse.wgsl`
- `shader_definitions/generative/gen-nebula-pulse.json`
- `agents/swarm-outputs/kimi-notes/gen-nebula-pulse.notes.kimi.md`（参数映射和验证命令）
