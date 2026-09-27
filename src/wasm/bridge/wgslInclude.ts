/**
 * `#include "_lib.wgsl"` expansion for WGSL.
 *
 * Source of truth for the expander. Lives under src/wasm/bridge so
 * scripts/emit-wasm-bridge.mjs emits it to both bridge copies, which lets the
 * WASM load path and the WebGPU fetch path share one implementation instead of
 * growing a second parser in C++.
 *
 * Contract: src/contracts/wgsl_include.json
 * Python mirror: scripts/wgsl_include.py (kept identical by verify:wgsl-include)
 *
 * Deliberately minimal — textual substitution of whole files, nothing else.
 * No macros, no conditionals, no include guards: WGSL cannot redeclare a
 * symbol, so including a library twice is an error rather than a no-op.
 */

/** Whole-line directive. Mirrors wgsl_include.json `directive.pattern`. */
const INCLUDE_RE = /^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$/;

export const WGSL_INCLUDE_MAX_DEPTH = 8;
export const WGSL_LIBRARY_PREFIX = '_';

export class WgslIncludeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WgslIncludeError';
  }
}

/** Resolves an include name to its source, or null when the file is absent. */
export type WgslIncludeResolver = (name: string) => Promise<string | null>;

/** Cheap check so callers can skip the whole machinery for the 1417 files that have none. */
export function hasWgslInclude(source: string): boolean {
  return /^[ \t]*#include[ \t]/m.test(stripComments(source));
}

/**
 * Blanks out comment bodies while preserving every newline, so line numbers and
 * offsets stay aligned with the original. Used only to decide whether a
 * directive is live; the text that gets expanded is always the original.
 */
function stripComments(source: string): string {
  let out = '';
  let i = 0;
  while (i < source.length) {
    const two = source.slice(i, i + 2);
    if (two === '//') {
      while (i < source.length && source[i] !== '\n') {
        out += ' ';
        i += 1;
      }
    } else if (two === '/*') {
      // WGSL block comments nest.
      let depth = 0;
      while (i < source.length) {
        const pair = source.slice(i, i + 2);
        if (pair === '/*') {
          depth += 1;
          out += '  ';
          i += 2;
        } else if (pair === '*/') {
          depth -= 1;
          out += '  ';
          i += 2;
          if (depth === 0) break;
        } else {
          out += source[i] === '\n' ? '\n' : ' ';
          i += 1;
        }
      }
    } else {
      out += source[i];
      i += 1;
    }
  }
  return out;
}

function validateName(name: string, parent: string): void {
  if (name.includes('/') || name.includes('\\')) {
    throw new WgslIncludeError(
      `${parent}: #include "${name}" — public/shaders is flat, a path separator is not allowed`,
    );
  }
  if (!name.endsWith('.wgsl')) {
    throw new WgslIncludeError(`${parent}: #include "${name}" — must end in .wgsl`);
  }
  if (!name.startsWith(WGSL_LIBRARY_PREFIX)) {
    throw new WgslIncludeError(
      `${parent}: #include "${name}" — only "${WGSL_LIBRARY_PREFIX}"-prefixed library files may be included, ` +
        `so a catalog shader cannot be inlined into another`,
    );
  }
}

/**
 * Expands every `#include` in `source`.
 *
 * Returns the source unchanged when it contains no directive, so the
 * overwhelming majority of the catalog costs one regex test.
 *
 * @param source  WGSL text.
 * @param resolve Loads an include by name; returns null when it does not exist.
 * @param entry   Name used for the entry file in error messages and markers.
 */
export async function expandWgslIncludes(
  source: string,
  resolve: WgslIncludeResolver,
  entry = '<entry>',
): Promise<string> {
  if (!hasWgslInclude(source)) return source;

  // Every file included anywhere in this expansion, in include order. WGSL has
  // no include guards, so a second include of the same file is an error.
  const seen = new Map<string, string>();

  const expand = async (text: string, file: string, stack: string[]): Promise<string> => {
    if (stack.length > WGSL_INCLUDE_MAX_DEPTH) {
      throw new WgslIncludeError(
        `#include nesting deeper than ${WGSL_INCLUDE_MAX_DEPTH}: ${[...stack, file].join(' -> ')}`,
      );
    }

    const lines = text.split('\n');
    // Comment-blanked twin: same line count, so index i means the same line in both.
    const blanked = stripComments(text).split('\n');
    const out: string[] = [];

    for (let i = 0; i < lines.length; i += 1) {
      const match = blanked[i]?.match(INCLUDE_RE);
      if (!match) {
        out.push(lines[i]);
        continue;
      }

      const name = match[1];
      const lineNo = i + 1;
      validateName(name, file);

      if (stack.includes(name) || name === file) {
        throw new WgslIncludeError(
          `#include cycle: ${[...stack, file, name].join(' -> ')}`,
        );
      }
      const previous = seen.get(name);
      if (previous !== undefined) {
        throw new WgslIncludeError(
          `${file}:${lineNo}: #include "${name}" was already included by ${previous} — ` +
            `WGSL has no include guards, so the second copy would redeclare every symbol`,
        );
      }
      seen.set(name, `${file}:${lineNo}`);

      const included = await resolve(name);
      if (included === null) {
        throw new WgslIncludeError(`${file}:${lineNo}: #include "${name}" — file not found under public/shaders`);
      }

      out.push(`// #include-expanded: ${name} (from ${file}:${lineNo})`);
      out.push(await expand(included, name, [...stack, file]));
    }

    return out.join('\n');
  };

  return expand(source, entry, []);
}
