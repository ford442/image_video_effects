Task: 完成 Batch 3 中的 E1-E3（translucent-nebula, prismatic-crystal, electric-eel），并为这三个着色器增加 psychedelic 色彩模式支持。

具体要求：

对于每个着色器：
- 保留原有配色作为默认模式
- 通过 `zoomParam4`（或合适参数）切换 psychedelic 模式：
  - Mode A: Neon Gradient（电紫 → 热粉 → 青色）
  - Mode B: Heat Map（深蓝 → 黄色 → 白色）
  - Mode C: Bioluminescent（深海蓝 → 青绿 → 亮绿）
- 确保 naga 验证通过
- 更新对应 JSON 的参数描述

优先处理顺序：translucent-nebula → prismatic-crystal → electric-eel

完成后生成简要报告（每个着色器的改动要点 + 验证结果）。
