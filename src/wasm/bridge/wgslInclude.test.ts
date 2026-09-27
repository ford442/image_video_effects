import {
  WGSL_INCLUDE_MAX_DEPTH,
  WgslIncludeError,
  expandWgslIncludes,
  hasWgslInclude,
} from './wgslInclude';

/** Resolver over an in-memory file map. */
const from = (files: Record<string, string>) => async (name: string) => files[name] ?? null;

describe('hasWgslInclude', () => {
  it('finds a live directive', () => {
    expect(hasWgslInclude('#include "_prelude.wgsl"')).toBe(true);
    expect(hasWgslInclude('  \t#include "_prelude.wgsl"')).toBe(true);
    expect(hasWgslInclude('fn main() {}\n#include "_a.wgsl"\n')).toBe(true);
  });

  it('ignores a directive that is only mentioned in a comment', () => {
    expect(hasWgslInclude('// #include "_prelude.wgsl"')).toBe(false);
    expect(hasWgslInclude('/*\n#include "_prelude.wgsl"\n*/')).toBe(false);
  });

  it('is false for the shape of every current catalog shader', () => {
    expect(hasWgslInclude('@group(0) @binding(0) var s: sampler;\nfn main() {}')).toBe(false);
  });
});

describe('expandWgslIncludes', () => {
  it('returns a source with no directive byte-identical', async () => {
    const src = '@group(0) @binding(0) var s: sampler;\n\nfn main() {}\n';
    await expect(expandWgslIncludes(src, from({}))).resolves.toBe(src);
  });

  it('substitutes the file and records where it came from', async () => {
    const out = await expandWgslIncludes(
      '#include "_a.wgsl"\nfn main() {}',
      from({ '_a.wgsl': 'fn helper() {}' }),
      'entry.wgsl',
    );
    expect(out).toBe('// #include-expanded: _a.wgsl (from entry.wgsl:1)\nfn helper() {}\nfn main() {}');
  });

  it('expands nested includes depth-first', async () => {
    const out = await expandWgslIncludes(
      '#include "_b.wgsl"',
      from({ '_b.wgsl': '#include "_a.wgsl"\nfn b() {}', '_a.wgsl': 'fn a() {}' }),
      'entry.wgsl',
    );
    expect(out).toContain('fn a() {}');
    expect(out.indexOf('fn a() {}')).toBeLessThan(out.indexOf('fn b() {}'));
  });

  it('leaves a commented-out directive alone', async () => {
    const src = '// #include "_a.wgsl"\n#include "_b.wgsl"';
    const out = await expandWgslIncludes(src, from({ '_b.wgsl': 'fn b() {}' }), 'entry.wgsl');
    expect(out).toContain('// #include "_a.wgsl"');
    expect(out).toContain('fn b() {}');
    expect(out).not.toContain('fn a()');
  });

  it('rejects a cycle, naming the chain', async () => {
    await expect(
      expandWgslIncludes(
        '#include "_a.wgsl"',
        from({ '_a.wgsl': '#include "_b.wgsl"', '_b.wgsl': '#include "_a.wgsl"' }),
        'entry.wgsl',
      ),
    ).rejects.toThrow(/cycle: entry\.wgsl -> _a\.wgsl -> _b\.wgsl -> _a\.wgsl/);
  });

  it('rejects the same library included twice — WGSL has no include guards', async () => {
    await expect(
      expandWgslIncludes(
        '#include "_a.wgsl"\n#include "_a.wgsl"',
        from({ '_a.wgsl': 'fn a() {}' }),
        'entry.wgsl',
      ),
    ).rejects.toThrow(/already included by entry\.wgsl:1/);
  });

  it('rejects a repeat reached through different paths', async () => {
    await expect(
      expandWgslIncludes(
        '#include "_a.wgsl"\n#include "_b.wgsl"',
        from({ '_a.wgsl': 'fn a() {}', '_b.wgsl': '#include "_a.wgsl"' }),
        'entry.wgsl',
      ),
    ).rejects.toThrow(/already included/);
  });

  it('rejects a missing file', async () => {
    await expect(
      expandWgslIncludes('#include "_nope.wgsl"', from({}), 'entry.wgsl'),
    ).rejects.toThrow(/file not found/);
  });

  it('rejects a path separator rather than resolving it', async () => {
    await expect(
      expandWgslIncludes('#include "../_a.wgsl"', from({}), 'entry.wgsl'),
    ).rejects.toThrow(/path separator is not allowed/);
    await expect(
      expandWgslIncludes('#include "sub/_a.wgsl"', from({}), 'entry.wgsl'),
    ).rejects.toThrow(/path separator is not allowed/);
  });

  it('refuses to inline a catalog shader', async () => {
    await expect(
      expandWgslIncludes('#include "plasma-orb.wgsl"', from({}), 'entry.wgsl'),
    ).rejects.toThrow(/only "_"-prefixed library files/);
  });

  it('requires a .wgsl extension', async () => {
    await expect(
      expandWgslIncludes('#include "_a.txt"', from({}), 'entry.wgsl'),
    ).rejects.toThrow(/must end in \.wgsl/);
  });

  it(`stops at depth ${WGSL_INCLUDE_MAX_DEPTH}`, async () => {
    // Each level includes the next; distinct names so the repeat guard is not
    // what trips first.
    const files: Record<string, string> = {};
    for (let i = 1; i <= 20; i += 1) files[`_d${i}.wgsl`] = `#include "_d${i + 1}.wgsl"`;

    await expect(
      expandWgslIncludes('#include "_d1.wgsl"', from(files), 'entry.wgsl'),
    ).rejects.toThrow(new RegExp(`nesting deeper than ${WGSL_INCLUDE_MAX_DEPTH}`));
  });

  it('throws WgslIncludeError, not a bare Error', async () => {
    await expect(
      expandWgslIncludes('#include "_nope.wgsl"', from({}), 'entry.wgsl'),
    ).rejects.toBeInstanceOf(WgslIncludeError);
  });

  it('does not treat a mid-line #include as a directive', async () => {
    const src = 'fn main() { } #include "_a.wgsl"';
    await expect(expandWgslIncludes(src, from({ '_a.wgsl': 'fn a() {}' }))).resolves.toBe(src);
  });
});
