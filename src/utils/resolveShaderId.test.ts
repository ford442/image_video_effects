import { getShaderIdAliases, resolveShaderId } from './resolveShaderId';

describe('resolveShaderId', () => {
  it('maps hyphen aliases to underscore canonical ids', () => {
    expect(resolveShaderId('aurora-borealis')).toBe('aurora_borealis');
    expect(resolveShaderId('kimi-flock-symphony')).toBe('kimi_flock_symphony');
  });

  it('passes through canonical and unknown ids', () => {
    expect(resolveShaderId('aurora_borealis')).toBe('aurora_borealis');
    expect(resolveShaderId('plasma-storm')).toBe('plasma-storm');
  });

  it('documents legacy aliases for underscore catalog ids without hyphen collisions', () => {
    const aliases = getShaderIdAliases();
    expect(Object.keys(aliases)).toHaveLength(20);
    expect(resolveShaderId('gen-quantum-foam')).toBe('gen-quantum-foam');
    expect(resolveShaderId('temporal-echo')).toBe('temporal-echo');
  });
});
