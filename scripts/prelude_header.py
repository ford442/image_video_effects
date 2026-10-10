#!/usr/bin/env python3
"""
prelude_header.py — find, classify and remove a pasted 13-binding header.

Shared by scripts/migrate_to_prelude.py (the codemod) and
scripts/check_prelude_migration.py (the CI gate), so both agree on what counts
as "a pasted header" and on whether a file can be migrated.

A pasted header is the 13 `@group(0) @binding(0..12)` declarations plus
`struct Uniforms`, i.e. exactly what public/shaders/_prelude.wgsl declares.
Detection works on top-level declarations, not lines, so one-line headers,
declarations split across lines and headers interleaved with other code are all
handled. A file is migratable only when every one of the 14 declarations is
present exactly once and equal to the prelude's after comment/whitespace
normalization. Anything else (binding 13, @group(1), helpers, consts) is left
exactly where it is: WGSL module scope is order-independent.

Stdlib only: the wgsl-precommit-gate CI job has no `npm ci`.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from wgsl_include import expand_wgsl_includes

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
PRELUDE_NAME = "_prelude.wgsl"
PRELUDE_PATH = SHADERS_DIR / PRELUDE_NAME
INCLUDE_LINE = f'#include "{PRELUDE_NAME}"'

_DIRECTIVE_RE = re.compile(r'^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$', re.MULTILINE)
_BINDING_KEY_RE = re.compile(r"^@group\((\d+)\)@binding\((\d+)\)")
_BINDING_KEY_REVERSED_RE = re.compile(r"^@binding\((\d+)\)@group\((\d+)\)")
_STRUCT_UNIFORMS_RE = re.compile(r"^struct Uniforms\{")
_VAR_RE = re.compile(r"var(?:<[^>]*>)?\s*([A-Za-z_][A-Za-z0-9_]*)\s*:")
_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\d[\w.]*|\S")
_PUNCT_RE = re.compile(r"\s*([@()<>,:;{}=\[\]])\s*")

# Whole-line comments that only label the pasted header. Removed together with
# it when they sit next to a removed declaration; any other comment survives.
BOILERPLATE_COMMENT_RES = [
    re.compile(p, re.IGNORECASE)
    for p in (
        r"copy\s*paste\s*this\s*header",
        r"13[- ]binding",
        r"binding\s+contract",
        r"canonical\s+(binding|header)",
        r"standard\s+(binding|header|bind\s*group)",
        r"^//[\s\-=─═━*#~]*(group\s*0\s*)?(bindings?|uniforms?|binding\s+header|bind\s*group(\s*0)?|"
        r"header|resources|uniform\s+buffer|uniforms?\s+struct(ure)?|textures?(\s*(&|and)\s*samplers?)?|"
        r"samplers?|storage(\s+buffers?)?|textures?\s+and\s+buffers?|inputs?\s*/\s*outputs?)"
        r"[\s\-=─═━*#~:]*$",
    )
]
_COPY_PASTE_RE = re.compile(r"copy\s*paste\s*this\s*header", re.IGNORECASE)
_SEPARATOR_RE = re.compile(r"^\s*//[\s\-=─═━*#~_.]*$")

# Text of the struct's zoom_params field comment that carries no information.
_BORING_PARAM_COMMENT_RES = [
    re.compile(p, re.IGNORECASE)
    for p in (
        r"^\.?x\s*=\s*param\s*1\b",
        r"^\.?x(yzw)?\s*[,=:]?\s*(=\s*)?(user\s+)?params?\b",
        r"^(user\s+)?(slider\s+)?params?(\s*\(?p?1\s*(\.\.|-)\s*p?4\)?)?\.?$",
        r"^\.?xyzw\s*=\s*user params p1\.\.p4",
        r"^x\s*,\s*y\s*,\s*z\s*,\s*w\s*(=|:)?\s*(user\s+)?(slider\s+)?params?",
        r"^p1\s*(\.\.|-)\s*p4",
        r"^\.?x\s*=\s*p1\s*,\s*\.?y\s*=\s*p2\s*,\s*\.?z\s*=\s*p3\s*,\s*\.?w\s*=\s*p4\.?$",
        r"^(generic|param)\s*[0-9]",
        r"^ui\s+(sliders?|params?)",
    )
]


class HeaderScanError(Exception):
    """The file could not be split into top-level declarations."""


@dataclass
class Item:
    start: int
    end: int
    code: str  # comment-blanked source of the declaration
    key: tuple | None
    _norm: str | None = None

    @property
    def norm(self) -> str:
        if self._norm is None:
            self._norm = normalize(self.code)
        return self._norm


@dataclass
class Classification:
    status: str  # "migratable" | "refused" | "already-includes" | "mixed" | "no-header"
    reason: str | None = None
    detail: str | None = None
    items: list[Item] = field(default_factory=list)
    targets: list[Item] = field(default_factory=list)


@dataclass
class Rewrite:
    text: str
    linemap: dict[int, int | None]
    include_line: int
    removed_comments: list[str]
    relocated_comment: str | None


# ── scanning ────────────────────────────────────────────────────────────────

_COMMENT_START_RE = re.compile(r"//|/\*")
_BLOCK_TOKEN_RE = re.compile(r"/\*|\*/")
_NON_NEWLINE_RE = re.compile(r"[^\n]")


def _block_comment_end(source: str, start: int) -> int:
    """Offset just past the (nesting) block comment that opens at `start`."""
    depth, j, n = 0, start, len(source)
    while j < n:
        m = _BLOCK_TOKEN_RE.search(source, j)
        if not m:
            return n
        depth += 1 if m.group() == "/*" else -1
        j = m.end()
        if depth == 0:
            return j
    return n


def strip_comments(source: str) -> str:
    """
    Same result as wgsl_include.strip_comments (comment bodies blanked, every
    newline kept, offsets unchanged), but slice-based: the per-character
    original is the bottleneck when the gate classifies the whole catalog.
    test_prelude_migration.py holds the two identical over every shader.
    """
    out: list[str] = []
    pos, n = 0, len(source)
    while pos < n:
        m = _COMMENT_START_RE.search(source, pos)
        if not m:
            out.append(source[pos:])
            break
        start = m.start()
        out.append(source[pos:start])
        if m.group() == "//":
            end = source.find("\n", start)
            end = n if end == -1 else end
            out.append(" " * (end - start))
        else:
            end = _block_comment_end(source, start)
            out.append(_NON_NEWLINE_RE.sub(" ", source[start:end]))
        pos = end
    return "".join(out)



def blank_directives(blanked: str) -> str:
    """Blank `#include` lines (they are not WGSL) while keeping offsets."""
    return _DIRECTIVE_RE.sub(lambda m: " " * len(m.group(0)), blanked)


def normalize(text: str) -> str:
    """Comment-free declaration text → canonical spacing for comparison."""
    t = re.sub(r"\s+", " ", text).strip()
    t = _PUNCT_RE.sub(r"\1", t)
    t = t.replace(",}", "}").replace(",>", ">")
    if t.endswith("};"):
        t = t[:-1]
    return t


def item_key(norm: str) -> tuple | None:
    m = _BINDING_KEY_RE.match(norm)
    if m:
        return ("binding", int(m.group(1)), int(m.group(2)))
    m = _BINDING_KEY_REVERSED_RE.match(norm)
    if m:
        return ("binding", int(m.group(2)), int(m.group(1)))
    if _STRUCT_UNIFORMS_RE.match(norm):
        return ("struct", "Uniforms")
    return None


_SIGNIFICANT_RE = re.compile(r"[()\[\]{};]")
_NON_SPACE_RE = re.compile(r"\S")


def scan_items(source: str) -> list[Item]:
    """Split `source` into top-level declarations (offsets into `source`)."""
    blanked = blank_directives(strip_comments(source))
    items: list[Item] = []
    n = len(blanked)
    i = 0
    while True:
        m = _NON_SPACE_RE.search(blanked, i)
        if not m:
            break
        start = i = m.start()
        brace = paren = 0
        while True:
            sig = _SIGNIFICANT_RE.search(blanked, i)
            if not sig:
                raise HeaderScanError(f"unterminated declaration starting at offset {start}")
            c, i = sig.group(), sig.end()
            if c in "([":
                paren += 1
            elif c in ")]":
                paren -= 1
            elif c == "{":
                brace += 1
            elif c == "}":
                brace -= 1
                if brace == 0 and paren == 0:
                    # `struct S { ... };` — the `;` on the same line belongs to the struct.
                    j = i
                    while j < n and blanked[j] in " \t":
                        j += 1
                    if j < n and blanked[j] == ";":
                        i = j + 1
                    break
            elif brace == 0 and paren == 0:  # ";"
                break
            if brace < 0 or paren < 0:
                raise HeaderScanError(f"unbalanced bracket at offset {i - 1}")
        code = blanked[start:i]
        # Only bindings and structs can be header declarations; normalizing every
        # function body just to rule it out is what made the gate slow.
        if code.startswith(("@group", "@binding", "struct")):
            norm = normalize(code)
            items.append(Item(start, i, code, item_key(norm), norm))
        else:
            items.append(Item(start, i, code, None))
    return items


# ── the reference: what _prelude.wgsl declares ──────────────────────────────

TARGET_KEYS = [("binding", 0, b) for b in range(13)] + [("struct", "Uniforms")]


def prelude_reference(prelude_text: str | None = None) -> dict[tuple, str]:
    text = prelude_text if prelude_text is not None else PRELUDE_PATH.read_text(encoding="utf-8")
    ref = {it.key: it.norm for it in scan_items(text) if it.key in TARGET_KEYS}
    missing = [k for k in TARGET_KEYS if k not in ref]
    if missing:
        raise RuntimeError(f"{PRELUDE_NAME} does not declare {missing}")
    return ref


def struct_fields(norm: str) -> list[str]:
    body = norm[norm.index("{") + 1 : norm.rindex("}")]
    return [f.split(":", 1)[0] for f in body.split(",") if f]


def var_name(norm: str) -> str | None:
    m = _VAR_RE.search(norm)
    return m.group(1) if m else None


def includes_of(source: str) -> list[str]:
    return _DIRECTIVE_RE.findall(strip_comments(source))


def classify(source: str, ref: dict[tuple, str]) -> Classification:
    try:
        items = scan_items(source)
    except HeaderScanError as exc:
        return Classification("refused", "scan-error", str(exc))

    by_key: dict[tuple, list[Item]] = {}
    for it in items:
        if it.key in ref:
            by_key.setdefault(it.key, []).append(it)

    if PRELUDE_NAME in includes_of(source):
        if by_key:
            pasted = ", ".join(_describe(k) for k in sorted(by_key, key=TARGET_KEYS.index))
            return Classification("mixed", "mixed", f"includes {PRELUDE_NAME} and also declares {pasted}", items)
        return Classification("already-includes", None, None, items)

    if not by_key:
        return Classification("no-header", None, None, items)

    problems: list[tuple[str, str]] = []
    for key in TARGET_KEYS:
        found = by_key.get(key, [])
        if not found:
            problems.append(("missing-decl", f"no {_describe(key)}"))
            continue
        if len(found) > 1:
            problems.append(("duplicate-decl", f"{_describe(key)} declared {len(found)} times"))
            continue
        norm = found[0].norm
        if norm == ref[key]:
            continue
        if key[0] == "struct":
            mine, theirs = struct_fields(norm), struct_fields(ref[key])
            if sorted(mine) == sorted(theirs):
                problems.append(("struct-field-order", f"Uniforms fields in order {', '.join(mine)}"))
            elif set(theirs) < set(mine):
                extra = [f for f in mine if f not in theirs]
                problems.append(("struct-extra-fields", f"Uniforms has extra fields {', '.join(extra)}"))
            else:
                problems.append(("struct-mismatch", f"Uniforms is {norm}"))
        else:
            mine_name, ref_name = var_name(norm), var_name(ref[key])
            if mine_name != ref_name:
                problems.append(("renamed-binding", f"binding {key[2]} is `{mine_name}`, not `{ref_name}`"))
            else:
                problems.append(("binding-type", f"binding {key[2]} is `{norm}`"))

    if problems:
        # The most specific reason wins, so the tracker reason is stable.
        order = [
            "struct-field-order",
            "struct-extra-fields",
            "struct-mismatch",
            "renamed-binding",
            "binding-type",
            "duplicate-decl",
            "missing-decl",
        ]
        problems.sort(key=lambda p: order.index(p[0]))
        detail = "; ".join(d for _, d in problems)
        return Classification("refused", problems[0][0], detail, items)

    targets = [by_key[k][0] for k in TARGET_KEYS]
    return Classification("migratable", None, None, items, targets)


def _describe(key: tuple) -> str:
    return "struct Uniforms" if key[0] == "struct" else f"@group({key[1]}) @binding({key[2]})"


def pastes_header(source: str) -> bool:
    """True when the file declares any of the prelude's 14 declarations itself."""
    try:
        items = scan_items(source)
    except HeaderScanError:
        return bool(re.search(r"@group\(\s*0\s*\)\s*@binding\(\s*([0-9]|1[0-2])\s*\)", strip_comments(source)))
    return any(it.key in TARGET_KEYS for it in items)


# ── comments ────────────────────────────────────────────────────────────────


def extract_comments(source: str) -> list[tuple[int, int, str]]:
    """(start, end, text) for every comment, block comments nesting as in WGSL."""
    out = []
    pos, n = 0, len(source)
    while pos < n:
        m = _COMMENT_START_RE.search(source, pos)
        if not m:
            break
        start = m.start()
        if m.group() == "//":
            end = source.find("\n", start)
            end = n if end == -1 else end
        else:
            end = _block_comment_end(source, start)
        out.append((start, end, source[start:end]))
        pos = end
    return out


def _is_boilerplate(line: str) -> bool:
    stripped = line.strip()
    return any(r.search(stripped) for r in BOILERPLATE_COMMENT_RES)


def _zoom_params_comment(source: str, struct_item: Item) -> str | None:
    text = source[struct_item.start : struct_item.end]
    for line in text.split("\n"):
        code = line.split("//", 1)[0]
        if re.search(r"\bzoom_params\s*:", code) and "//" in line:
            comment = line.split("//", 1)[1].strip()
            if comment and not any(r.search(comment) for r in _BORING_PARAM_COMMENT_RES):
                return comment
    return None


# ── rewriting ───────────────────────────────────────────────────────────────


def rewrite(source: str, cls: Classification) -> Rewrite:
    """Remove the 14 declarations and put one include where the first one was."""
    assert cls.status == "migratable"
    blanked = blank_directives(strip_comments(source))
    masked = [False] * len(source)
    for it in cls.targets:
        for k in range(it.start, it.end):
            masked[k] = True

    had_final_newline = source.endswith("\n")
    lines = source.split("\n")
    if had_final_newline:
        lines.pop()
    offsets, pos = [], 0
    for line in lines:
        offsets.append(pos)
        pos += len(line) + 1

    # Per old line: "keep", "drop" (all content was header) or "partial".
    kinds: list[str] = []
    partial_text: dict[int, str] = {}
    for idx, line in enumerate(lines):
        start = offsets[idx]
        span = range(start, start + len(line))
        if not any(masked[k] for k in span):
            kinds.append("keep")
            continue
        rest_code = "".join(blanked[k] for k in span if not masked[k])
        if rest_code.strip() == "":
            kinds.append("drop")
            continue
        kinds.append("partial")
        partial_text[idx] = _cut_line(line, masked[start : start + len(line)])

    removed_lines = {i for i, k in enumerate(kinds) if k == "drop"}

    def is_comment_only(i: int) -> bool:
        return lines[i].strip().startswith("//") and blanked[offsets[i] : offsets[i] + len(lines[i])].strip() == ""

    def neighbour(i: int, step: int) -> int | None:
        j = i + step
        while 0 <= j < len(lines):
            if lines[j].strip() == "":
                j += step
                continue
            return j
        return None

    # Boilerplate labels next to the header go with it; repeat so a stack of
    # label lines above the header is consumed from the inside out.
    changed = True
    while changed:
        changed = False
        for i in range(len(lines)):
            if kinds[i] != "keep" or not is_comment_only(i) or not _is_boilerplate(lines[i]):
                continue
            if any(n is not None and n in removed_lines for n in (neighbour(i, -1), neighbour(i, 1))):
                kinds[i] = "boilerplate"
                removed_lines.add(i)
                changed = True
    # Separator rules whose nearest real neighbours on both sides were removed.
    changed = True
    while changed:
        changed = False
        for i in range(len(lines)):
            if kinds[i] != "keep" or not _SEPARATOR_RE.match(lines[i]):
                continue
            up, down = i - 1, i + 1
            while up >= 0 and (lines[up].strip() == "" or (kinds[up] == "keep" and _SEPARATOR_RE.match(lines[up]))):
                up -= 1
            while down < len(lines) and (
                lines[down].strip() == "" or (kinds[down] == "keep" and _SEPARATOR_RE.match(lines[down]))
            ):
                down += 1
            if up >= 0 and down < len(lines) and up in removed_lines and down in removed_lines:
                kinds[i] = "boilerplate"
                removed_lines.add(i)
                changed = True

    # A removed "COPY PASTE THIS HEADER" banner opened a block; the separator
    # rule directly under the last declaration of that block closed it.
    banner_lines = [i for i in range(len(lines)) if kinds[i] == "boilerplate" and _COPY_PASTE_RE.search(lines[i])]
    for b in banner_lines:
        j = b + 1
        while j < len(lines) and kinds[j] in ("drop", "boilerplate"):
            j += 1
        if j < len(lines) and j - 1 > b and kinds[j] == "keep" and _SEPARATOR_RE.match(lines[j]):
            kinds[j] = "boilerplate"
            removed_lines.add(j)

    first_line = min(source.count("\n", 0, it.start) for it in cls.targets)
    struct_item = cls.targets[-1]
    relocated = _zoom_params_comment(source, struct_item)

    # Build the output as (text, old line or None) so seams and the line map fall out.
    out: list[tuple[str, int | None]] = []
    inserted = False

    def insert_include() -> None:
        out.append((INCLUDE_LINE, None))
        if relocated:
            out.append((f"// zoom_params: {relocated}", None))

    for i, line in enumerate(lines):
        if i == first_line and not inserted:
            if kinds[i] == "partial" and _code_before_first_target(source, offsets[i], cls):
                out.append((partial_text[i], i))
                insert_include()
                inserted = True
                continue
            insert_include()
            inserted = True
        kind = kinds[i]
        if kind == "keep":
            out.append((line, i))
        elif kind == "partial":
            out.append((partial_text[i], i))
    if not inserted:
        insert_include()

    # Collapse runs of blank lines, but only across a removal seam.
    collapsed: list[tuple[str, int | None]] = []
    for text, origin in out:
        if text.strip() == "" and collapsed and collapsed[-1][0].strip() == "":
            prev_origin = collapsed[-1][1]
            if origin is None or prev_origin is None or origin != prev_origin + 1:
                continue
        collapsed.append((text, origin))
    # A file must not start with a blank line the original did not have.
    while collapsed and collapsed[0][0].strip() == "" and lines and lines[0].strip() != "":
        collapsed.pop(0)

    linemap: dict[int, int | None] = {i + 1: None for i in range(len(lines))}
    include_line = 0
    for new_idx, (text, origin) in enumerate(collapsed, start=1):
        if origin is not None:
            linemap[origin + 1] = new_idx
        elif text == INCLUDE_LINE:
            include_line = new_idx

    text = "\n".join(t for t, _ in collapsed) + ("\n" if had_final_newline else "")

    removed_comments = []
    for start, end, ctext in extract_comments(source):
        line_idx = source.count("\n", 0, start)
        if masked[start] or kinds[line_idx] in ("drop", "boilerplate"):
            removed_comments.append(ctext)

    return Rewrite(text, linemap, include_line, removed_comments, relocated)


def _cut_line(line: str, mask: list[bool]) -> str:
    """
    Remove the masked columns of a line that also holds kept code (minified
    files put `struct Uniforms{...};fn f()` on one line). Whitespace after a cut
    goes too when the cut started at the line start or after whitespace, so no
    double space or stray indent is left behind.
    """
    out: list[str] = []
    k, n = 0, len(line)
    while k < n:
        if not mask[k]:
            out.append(line[k])
            k += 1
            continue
        while k < n and mask[k]:
            k += 1
        if k == n:
            while out and out[-1] in " \t":
                out.pop()
        elif not out or out[-1] in " \t":
            while k < n and not mask[k] and line[k] in " \t":
                k += 1
    return "".join(out)


def _code_before_first_target(source: str, line_start: int, cls: Classification) -> bool:
    first = min(it.start for it in cls.targets)
    before = blank_directives(strip_comments(source))[line_start:first]
    return before.strip() != ""


# ── verification ────────────────────────────────────────────────────────────


def code_tokens(source: str, mask: list[tuple[int, int]] = ()) -> list[str]:
    blanked = list(blank_directives(strip_comments(source)))
    for start, end in mask:
        for k in range(start, end):
            blanked[k] = " "
    return _TOKEN_RE.findall("".join(blanked))


def verify(
    old: str,
    new: str,
    cls: Classification,
    rw: Rewrite,
    prelude_text: str,
) -> list[str]:
    """V1–V3 from the plan. Returns a list of failures (empty = proven equivalent)."""
    failures = []

    # V1: code outside the header is token-identical.
    old_tokens = code_tokens(old, [(it.start, it.end) for it in cls.targets])
    new_tokens = code_tokens(new)
    if old_tokens != new_tokens:
        idx = next((i for i, (a, b) in enumerate(zip(old_tokens, new_tokens)) if a != b), min(len(old_tokens), len(new_tokens)))
        failures.append(
            f"V1 code tokens differ at token {idx}: "
            f"{' '.join(old_tokens[max(0, idx - 3):idx + 3])!r} vs {' '.join(new_tokens[max(0, idx - 3):idx + 3])!r}"
        )

    # V2: every comment survives except the removed classes; banner lines byte-identical.
    old_comments = Counter(c for _, _, c in extract_comments(old))
    old_comments.subtract(Counter(rw.removed_comments))
    expected = +old_comments
    new_comments = Counter(c for _, _, c in extract_comments(new))
    if rw.relocated_comment:
        new_comments.subtract(Counter([f"// zoom_params: {rw.relocated_comment}"]))
    if +new_comments != expected:
        lost = expected - new_comments
        gained = new_comments - expected
        failures.append(f"V2 comments changed: lost {list(lost)[:3]}, gained {list(gained)[:3]}")
    for marker in ("Upgraded:", "Category:", "Features:", "Ideas:"):
        old_lines = [l for l in old.split("\n") if marker in l]
        new_lines = [l for l in new.split("\n") if marker in l]
        if old_lines != new_lines:
            failures.append(f"V2 banner line `{marker}` changed")

    # V3: the expanded module has the same declarations as the original.
    expanded = expand_wgsl_includes(new, lambda name: prelude_text if name == PRELUDE_NAME else _read_library(name), "<new>")
    if Counter(it.norm for it in scan_items(expanded)) != Counter(it.norm for it in scan_items(old)):
        failures.append("V3 expanded module declarations differ from the original")

    if new.count(INCLUDE_LINE) != 1:
        failures.append("exactly one prelude include expected")
    return failures


def _read_library(name: str) -> str | None:
    path = SHADERS_DIR / name
    return path.read_text(encoding="utf-8") if path.is_file() else None
