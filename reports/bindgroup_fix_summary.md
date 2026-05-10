# BindGroup Auto-Fix Summary

**Generated:** 2026-05-09 23:54 UTC  
**Tool:** `scripts/fix_bindgroups.py`

## Overview

| Metric | Count |
| --- | --- |
| Total shaders processed | 971 |
| Incompatible **before** fix | 3 |
| Incompatible **after** fix | 3 |
| Shaders auto-fixed | 0 |
| Shaders already compatible | 964 |
| Shaders requiring manual review | 2 |
| Shaders skipped (templates/render) | 5 |

## Fix Types Applied

| Fix Type | Shaders Fixed |
| --- | --- |

## Auto-Fixed Shaders

| Shader | Fixes Applied |
| --- | --- |

## Shaders Requiring Manual Review

These shaders could not be auto-fixed. Human intervention is needed.

| Shader | Issues |
| --- | --- |
| `gen-superfluid-quantum-foam` | Uniforms missing ripples but has extra fields ['custom_params'] – manual layout fix required |
| `plasma` | binding 12 wrong type: 'array<PlasmaBall, 50>' |

## Remaining Incompatible Shaders (post-fix)

| Shader | Errors |
| --- | --- |
| `_hash_library` | No @compute, @vertex, or @fragment entry points found |
| `gen-superfluid-quantum-foam` | Uniforms struct missing fields: ['ripples'] |
| `plasma` | Binding 12 (plasmaBalls) has incompatible type: 'array<PlasmaBall, 50>' |

---

## Violation Type Reference

| Violation | Auto-fixable? | Fix applied |
| --- | --- | --- |
| `binding_10_access: read → read_write` | ✅ Yes | Changed `<storage, read>` to `<storage, read_write>` |
| `binding_12_access: <storage> → <storage, read>` | ✅ Yes | Added `, read` access qualifier |
| `added_missing_bindings` | ✅ Yes | Inserted canonical stub declarations |
| `uniforms_ripples_field_added` | ✅ Yes | Appended `ripples` field to Uniforms struct |
| Binding 12 wrong struct type (`array<PlasmaBall, …>`) | ❌ No | Needs custom rewrite |
| Uniforms struct with extra fields + missing `ripples` | ❌ No | Memory-layout conflict, manual fix |
| No `@compute` entry point | ❌ No | Library/utility file |
