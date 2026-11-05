# Shader catalog hygiene audit

Generated: 2026-11-04T09:54:21.171823+00:00

## Definition → WGSL

| Classification | Count |
|----------------|------:|
| `local` | 1414 |
| `storage-only` | 0 |
| `allowlisted` | 0 |
| `likely-broken` | 0 |
| `parse-error` | 0 |

## WGSL → Definition

| Classification | Count |
|----------------|------:|
| `cataloged` | 1415 |
| `template-prefix` | 7 |
| `subgroup-variant` | 0 |
| `multipass-secondary` | 28 |
| `orphan` | 2 |

**only_def** (defs without WGSL): 0
**only_wgsl** (unexpected orphans): 2

## Non-local definitions

_All definitions have a matching local WGSL file._

## Orphan WGSL files

_2 files need a shader_definitions JSON or ignore prefix._

- `optical-flow-advect.wgsl`
- `optical-flow-grade.wgsl`
