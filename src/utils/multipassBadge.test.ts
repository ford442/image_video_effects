import { getMultipassBadgeLabel } from '../utils/multipassBadge';

describe('multipassBadge', () => {
  it('returns graph pass count for ripple-tank', () => {
    expect(getMultipassBadgeLabel('ripple-tank')).toBe('graph · 7 passes');
  });

  it('returns graph pass count for fabric-of-reality', () => {
    expect(getMultipassBadgeLabel('fabric-of-reality')).toBe('graph · 7 passes');
  });

  it('returns graph pass count for photonic-caustics-graph', () => {
    expect(getMultipassBadgeLabel('photonic-caustics-graph')).toBe('graph · 4 passes');
  });

  it('returns graph pass counts for the new Physics Lab flagships', () => {
    expect(getMultipassBadgeLabel('chromatographic-fluid')).toBe('graph · 7 passes');
    expect(getMultipassBadgeLabel('gray-scott-tank')).toBe('graph · 6 passes');
    expect(getMultipassBadgeLabel('optical-flow-dream')).toBe('graph · 4 passes');
  });

  it('returns graph pass count for quantum-foam graph entry', () => {
    expect(getMultipassBadgeLabel('quantum-foam-pass1')).toBe('graph · 3 passes');
  });

  it('returns linear pass count for multipass chains', () => {
    expect(getMultipassBadgeLabel('rd-on-video-pass1')).toBe('3-pass');
  });

  it('returns null for single-pass shaders', () => {
    expect(getMultipassBadgeLabel('wave-equation')).toBeNull();
  });
});
