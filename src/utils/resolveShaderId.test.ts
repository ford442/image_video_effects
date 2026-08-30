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

  it('documents 22 legacy aliases', () => {
    expect(Object.keys(getShaderIdAliases())).toHaveLength(22);
  });
});
