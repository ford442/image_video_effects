import { definitionParams, humanizeParamName, parseParamHeader, slotParamValues } from './wgslParams';

describe('parseParamHeader', () => {
  it('maps pragmas in order to p1..p4 / zoom_params.x..w', () => {
    const { params, problems } = parseParamHeader(
      ['// @param speed 0 4 1 Flow speed', 'fn x() {}', '//@param hue_shift 0 1 0.25', '// @param warpAmount -1 1 0'].join('\n'),
    );
    expect(problems).toEqual([]);
    expect(params.map((p) => [p.id, p.name, p.mapping, p.line])).toEqual([
      ['speed', 'Flow speed', 'zoom_params.x', 1],
      ['hue_shift', 'Hue Shift', 'zoom_params.y', 3],
      ['warpAmount', 'Warp Amount', 'zoom_params.z', 4],
    ]);
    expect(params[0]).toMatchObject({ min: 0, max: 4, default: 1, step: 0.01 });
  });

  it('reports bad pragmas on their line and keeps the good ones', () => {
    const src = [
      '// @param a 0 1',
      '// @param 9b 0 1 0',
      '// @param c 1 0 0.5',
      '// @param d 0 1 2',
      '// @param e 0 x 0',
      '// @param f 0 1 0.5',
      '// @param f 0 1 0.5',
      '// @param g 0 1 0', '// @param h 0 1 0', '// @param i 0 1 0', '// @param j 0 1 0',
    ].join('\n');
    const { params, problems } = parseParamHeader(src);
    expect(params.map((p) => p.id)).toEqual(['f', 'g', 'h', 'i']);
    expect(problems.map((p) => p.line)).toEqual([1, 2, 3, 4, 5, 7, 11]);
    expect(problems[6]?.message).toMatch(/only 4 sliders/);
  });

  it('ignores ordinary comments mentioning params', () => {
    expect(parseParamHeader('// the @params live in zoom_params\n// param x 0 1 0').params).toEqual([]);
  });
});

describe('slot values and definition params', () => {
  const { params } = parseParamHeader('// @param a 0 10 5\n// @param b 0 1 0.5');
  it('uses values clamped to range, defaults otherwise, 0 for unused lanes', () => {
    expect(slotParamValues(params)).toEqual([5, 0.5, 0, 0]);
    expect(slotParamValues(params, { a: 20, b: 0.1 })).toEqual([10, 0.1, 0, 0]);
  });
  it('drops editor-only fields', () => {
    expect(definitionParams(params)[0]).toEqual({ id: 'a', name: 'A', default: 5, min: 0, max: 10, step: 0.1, mapping: 'zoom_params.x' });
  });
  it('humanizes names', () => {
    expect(humanizeParamName('flowSpeed')).toBe('Flow Speed');
    expect(humanizeParamName('flow_speed')).toBe('Flow Speed');
  });
});
