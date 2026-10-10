#!/usr/bin/env python3
"""The new_shader.py scaffold must emit a definition the schema gate accepts (no pytest required)."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS))

from new_shader import build_definition, infer_category, sanitize_shader_id  # noqa: E402

VALIDATOR = _SCRIPTS / "validate_shader_definitions.mjs"


def _validate(folder: str, shader_id: str, definition: dict) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / folder / f"{shader_id}.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(definition, indent=2) + "\n", encoding="utf-8")
        return subprocess.run(["node", str(VALIDATOR), str(path)], capture_output=True, text=True)


def test_scaffold_is_schema_valid_for_every_inferred_category():
    for name in ("My New Effect", "gen-fresh-nebula", "sim-ring-world", "interactive-poke", "pp-soft-focus"):
        shader_id = sanitize_shader_id(name)
        folder = infer_category(shader_id, None)
        result = _validate(folder, shader_id, build_definition(shader_id, folder))
        assert result.returncode == 0, f"{shader_id}: {result.stderr}"


def test_validator_rejects_a_legacy_key():
    shader_id = "legacy-key-probe"
    definition = build_definition(shader_id, "generative")
    definition["updatedParams"] = []
    result = _validate("generative", shader_id, definition)
    assert result.returncode != 0 and "updatedParams" in result.stderr


def main() -> int:
    tests = [test_scaffold_is_schema_valid_for_every_inferred_category, test_validator_rejects_a_legacy_key]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"OK  {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"FAIL {t.__name__}: {e}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
