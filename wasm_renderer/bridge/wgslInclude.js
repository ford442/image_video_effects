// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

const INCLUDE_RE = /^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$/;
const WGSL_INCLUDE_MAX_DEPTH = 8;
const WGSL_LIBRARY_PREFIX = "_";
class WgslIncludeError extends Error {
  constructor(message) {
    super(message);
    this.name = "WgslIncludeError";
  }
}
function hasWgslInclude(source) {
  return /^[ \t]*#include[ \t]/m.test(stripComments(source));
}
function stripComments(source) {
  let out = "";
  let i = 0;
  while (i < source.length) {
    const two = source.slice(i, i + 2);
    if (two === "//") {
      while (i < source.length && source[i] !== "\n") {
        out += " ";
        i += 1;
      }
    } else if (two === "/*") {
      let depth = 0;
      while (i < source.length) {
        const pair = source.slice(i, i + 2);
        if (pair === "/*") {
          depth += 1;
          out += "  ";
          i += 2;
        } else if (pair === "*/") {
          depth -= 1;
          out += "  ";
          i += 2;
          if (depth === 0) break;
        } else {
          out += source[i] === "\n" ? "\n" : " ";
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
function validateName(name, parent) {
  if (name.includes("/") || name.includes("\\")) {
    throw new WgslIncludeError(
      `${parent}: #include "${name}" \u2014 public/shaders is flat, a path separator is not allowed`
    );
  }
  if (!name.endsWith(".wgsl")) {
    throw new WgslIncludeError(`${parent}: #include "${name}" \u2014 must end in .wgsl`);
  }
  if (!name.startsWith(WGSL_LIBRARY_PREFIX)) {
    throw new WgslIncludeError(
      `${parent}: #include "${name}" \u2014 only "${WGSL_LIBRARY_PREFIX}"-prefixed library files may be included, so a catalog shader cannot be inlined into another`
    );
  }
}
async function expandWgslIncludes(source, resolve, entry = "<entry>") {
  if (!hasWgslInclude(source)) return source;
  const seen = /* @__PURE__ */ new Map();
  const expand = async (text, file, stack) => {
    if (stack.length > WGSL_INCLUDE_MAX_DEPTH) {
      throw new WgslIncludeError(
        `#include nesting deeper than ${WGSL_INCLUDE_MAX_DEPTH}: ${[...stack, file].join(" -> ")}`
      );
    }
    const lines = text.split("\n");
    const blanked = stripComments(text).split("\n");
    const out = [];
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
          `#include cycle: ${[...stack, file, name].join(" -> ")}`
        );
      }
      const previous = seen.get(name);
      if (previous !== void 0) {
        throw new WgslIncludeError(
          `${file}:${lineNo}: #include "${name}" was already included by ${previous} \u2014 WGSL has no include guards, so the second copy would redeclare every symbol`
        );
      }
      seen.set(name, `${file}:${lineNo}`);
      const included = await resolve(name);
      if (included === null) {
        throw new WgslIncludeError(`${file}:${lineNo}: #include "${name}" \u2014 file not found under public/shaders`);
      }
      out.push(`// #include-expanded: ${name} (from ${file}:${lineNo})`);
      out.push(await expand(included, name, [...stack, file]));
    }
    return out.join("\n");
  };
  return expand(source, entry, []);
}
export {
  WGSL_INCLUDE_MAX_DEPTH,
  WGSL_LIBRARY_PREFIX,
  WgslIncludeError,
  expandWgslIncludes,
  hasWgslInclude
};
