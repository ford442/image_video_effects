# Coordinator review — slime / flow leftover eight

Pass/fail per file against Idea Cards. Plumbing floor is required but is not the upgrade.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not ≥70% boilerplate | Native (not overlay clone) | A packing matches C | Params exact | Springs native-only | Naga |
|---|---|---|---|---|---|---|---|---|---|
| sim-slime-mold-growth | yes | photoLuma; anastomosis | sensor loop + 4 params | yes | yes | raw trail | yes | none new | pass |
| sim-slime-mold-growth-em | yes | fieldLineDeposit; wipe/secE | dual-use params + [133..138] | yes | yes | raw trail/EM | yes | kept pointer hist | pass |
| slime-mold-on-video | yes | islandBridge; streamer/vein | follow/decay/food/glow | yes | yes | raw trail/food/drift | yes | none new | pass |
| luma-flow-field | yes | licHist; stagnate | isoFlow + 4 params | yes | yes | HDR history RGBA | yes | none new | pass |
| wave-equation-rgba-fluid | yes | breaking; stretch | wave+Jacobi+dye | yes (floor is C loads) | yes | raw h/v/p/dye | yes | none new | pass |
| spec-runge-kutta-advection | yes | filament; licDye | RK4 kept | yes | yes | HDR dye+\|vel\| | yes | none new | pass |
| sim-heat-haze-field | yes | plume; schliere | temp field + 4 params | yes | yes | raw thermal | yes | none new | pass |
| lichtenberg-fractal | yes | tip; scorch | DBM + curl + 4 params | yes (floor is C loads) | yes | charge/age/bias/scorch | yes | none new | pass |

**Batch result: PASS 8/8** (structural). Real-GPU visual QA remains external.

Skipped: physarum trio (extraBuffer[0..] agents); optical-flow-tracer (binding 13); sand-dunes generative; five sand/wave files already shipped this morning.
