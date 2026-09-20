#!/usr/bin/env python3
"""
`#include "_lib.wgsl"` expansion for WGSL — Python mirror.

Mirror of src/wasm/bridge/wgslInclude.ts, which is the source of truth. The two
are held byte-identical on the fixture corpus by scripts/verify-wgsl-include.mjs
(`npm run verify:wgsl-include`), so a change here without a matching change
there fails CI.

Exists because scripts/bindgroup_checker.py parses raw WGSL text and would see
no bindings at all in a shader that gets them from _prelude.wgsl. The other
Python audits (extraBuffer, dead sliders, workgroup size, orphan defs) read
only the shader's own body and do not need expansion.

Contract: src/contracts/wgsl_include.json
"""

import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SHADER_ROOT = PROJECT_ROOT / "public" / "shaders"

INCLUDE_RE = re.compile(r'^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$')
HAS_INCLUDE_RE = re.compile(r"^[ \t]*#include[ \t]", re.MULTILINE)

MAX_DEPTH = 8
LIBRARY_PREFIX = "_"


class WgslIncludeError(Exception):
    """Raised for a malformed, missing, cyclic or repeated include."""


def strip_comments(source: str) -> str:
    """
    Blank out comment bodies, preserving every newline so line numbers and
    offsets stay aligned with the original.
    """
    out = []
    i = 0
    n = len(source)
    while i < n:
        two = source[i : i + 2]
        if two == "//":
            while i < n and source[i] != "\n":
                out.append(" ")
                i += 1
        elif two == "/*":
            depth = 0
            while i < n:
                pair = source[i : i + 2]
                if pair == "/*":
                    depth += 1
                    out.append("  ")
                    i += 2
                elif pair == "*/":
                    depth -= 1
                    out.append("  ")
                    i += 2
                    if depth == 0:
                        break
                else:
                    out.append("\n" if source[i] == "\n" else " ")
                    i += 1
        else:
            out.append(source[i])
            i += 1
    return "".join(out)


def has_wgsl_include(source: str) -> bool:
    """True when the source has at least one live (non-commented) directive."""
    return bool(HAS_INCLUDE_RE.search(strip_comments(source)))


def _validate_name(name: str, parent: str) -> None:
    if "/" in name or "\\" in name:
        raise WgslIncludeError(
            f'{parent}: #include "{name}" — public/shaders is flat, a path separator is not allowed'
        )
    if not name.endswith(".wgsl"):
        raise WgslIncludeError(f'{parent}: #include "{name}" — must end in .wgsl')
    if not name.startswith(LIBRARY_PREFIX):
        raise WgslIncludeError(
            f'{parent}: #include "{name}" — only "{LIBRARY_PREFIX}"-prefixed library files may be '
            "included, so a catalog shader cannot be inlined into another"
        )


def _default_resolver(name: str):
    path = SHADER_ROOT / name
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8")


def expand_wgsl_includes(source: str, resolve=None, entry: str = "<entry>") -> str:
    """
    Expand every `#include` in *source*.

    Returns *source* unchanged when it has no directive, so the overwhelming
    majority of the catalog costs one regex search.

    *resolve* takes an include name and returns its text, or None if missing.
    Defaults to reading from public/shaders.
    """
    if not has_wgsl_include(source):
        return source

    if resolve is None:
        resolve = _default_resolver

    seen = {}

    def expand(text: str, file: str, stack) -> str:
        if len(stack) > MAX_DEPTH:
            chain = " -> ".join(list(stack) + [file])
            raise WgslIncludeError(f"#include nesting deeper than {MAX_DEPTH}: {chain}")

        lines = text.split("\n")
        blanked = strip_comments(text).split("\n")
        out = []

        for i, line in enumerate(lines):
            match = INCLUDE_RE.match(blanked[i]) if i < len(blanked) else None
            if not match:
                out.append(line)
                continue

            name = match.group(1)
            line_no = i + 1
            _validate_name(name, file)

            if name in stack or name == file:
                chain = " -> ".join(list(stack) + [file, name])
                raise WgslIncludeError(f"#include cycle: {chain}")

            previous = seen.get(name)
            if previous is not None:
                raise WgslIncludeError(
                    f'{file}:{line_no}: #include "{name}" was already included by {previous} — '
                    "WGSL has no include guards, so the second copy would redeclare every symbol"
                )
            seen[name] = f"{file}:{line_no}"

            included = resolve(name)
            if included is None:
                raise WgslIncludeError(
                    f'{file}:{line_no}: #include "{name}" — file not found under public/shaders'
                )

            out.append(f"// #include-expanded: {name} (from {file}:{line_no})")
            out.append(expand(included, name, list(stack) + [file]))

        return "\n".join(out)

    return expand(source, entry, [])


def expand_file(path) -> str:
    """Expand a shader file on disk, using its basename in diagnostics."""
    path = Path(path)
    return expand_wgsl_includes(path.read_text(encoding="utf-8"), entry=path.name)


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("usage: wgsl_include.py <shader.wgsl>", file=sys.stderr)
        raise SystemExit(2)
    try:
        print(expand_file(sys.argv[1]), end="")
    except WgslIncludeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
