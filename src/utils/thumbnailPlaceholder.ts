export const CATEGORY_LABELS: Record<string, string> = {
  'interactive-mouse': '🖱️ Interactive',
  'artistic': '🎨 Artistic',
  'generative': '✨ Generative',
  'distortion': '🔮 Distortion',
  'image': '🖼️ Image',
  'visual-effects': '🎬 Visual Effects',
  'retro-glitch': '📺 Retro / Glitch',
  'liquid-effects': '💧 Liquid',
  'simulation': '🧬 Simulation',
  'geometric': '📐 Geometric',
  'lighting-effects': '💡 Lighting',
  'advanced-hybrid': '⚡ Hybrid',
  'post-processing': '🎞️ Post',
  'hybrid': '🔀 Hybrid',
  other: '✨ Other',
};

/** Per-category gradient colors for missing thumbnail placeholders. */
export const CATEGORY_PLACEHOLDER_STYLES: Record<string, { from: string; to: string; accent: string }> = {
  'interactive-mouse': { from: '#1a2a4a', to: '#0d1528', accent: '#6eb5ff' },
  artistic: { from: '#3a1a4a', to: '#1a0d28', accent: '#e94596' },
  generative: { from: '#2a1a4a', to: '#120d28', accent: '#c9a227' },
  distortion: { from: '#1a3a4a', to: '#0d2028', accent: '#40e0d0' },
  image: { from: '#2a2a3a', to: '#141420', accent: '#a0a8c0' },
  'visual-effects': { from: '#3a2a1a', to: '#1a1408', accent: '#ffb347' },
  'retro-glitch': { from: '#2a1a2a', to: '#140814', accent: '#ff6ec7' },
  'liquid-effects': { from: '#0a2a3a', to: '#051420', accent: '#4fc3f7' },
  simulation: { from: '#1a3a2a', to: '#0d2018', accent: '#66bb6a' },
  geometric: { from: '#2a2a1a', to: '#141008', accent: '#ffd54f' },
  'lighting-effects': { from: '#2a1a1a', to: '#140808', accent: '#ffab40' },
  'advanced-hybrid': { from: '#1a2a3a', to: '#0d1418', accent: '#80cbc4' },
  'post-processing': { from: '#2a1a3a', to: '#140d20', accent: '#b39ddb' },
  hybrid: { from: '#1a3a3a', to: '#0d2020', accent: '#4dd0e1' },
  other: { from: '#1a1a2a', to: '#0d0d18', accent: '#9090a8' },
};

export function getCategoryLabel(category?: string): string {
  if (!category) return CATEGORY_LABELS.other;
  return CATEGORY_LABELS[category] || CATEGORY_LABELS.other;
}

export function getCategoryGlyph(category?: string): string {
  return getCategoryLabel(category).slice(0, 2);
}

export function getCategoryPlaceholderStyle(category?: string): {
  background: string;
  color: string;
} {
  const key = category && CATEGORY_PLACEHOLDER_STYLES[category] ? category : 'other';
  const palette = CATEGORY_PLACEHOLDER_STYLES[key];
  return {
    background: `linear-gradient(135deg, ${palette.from} 0%, ${palette.to} 100%)`,
    color: palette.accent,
  };
}

export function truncateShaderName(name: string, maxLen = 28): string {
  if (name.length <= maxLen) return name;
  return `${name.slice(0, maxLen - 1)}…`;
}
