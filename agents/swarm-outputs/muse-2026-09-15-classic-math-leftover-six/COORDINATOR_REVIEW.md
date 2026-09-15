# COORDINATOR REVIEW — Classic math / CA / reaction leftover six

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9. All files: Idea Card written
before diff (BRIEFS.md), each numbered idea greppable in WGSL, KEEP VERBATIM
holds (modes/kernel/param roles intact, params byte-exact), no shared overlay
(each file's additions are family-native and distinct), A packing matches C
reads, springs/ripples added nowhere, Naga + gate per file.

| File | Card | Ideas pointable | Keep verbatim | Overlay-free | Packing honest | Params exact | Naga/gate | Verdict |
|---|---|---|---|---|---|---|---|---|
| gen-rgb-diffraction | ✅ | ✅ envSinc, blazePhase | ✅ | ✅ (no spring; mouse via grating physics) | ✅ display RGBA | ✅ | ✅ | PASS |
| gen-verlet-cloth-wind | ✅ | ✅ frontT, warpHi | ✅ | ✅ (poke stays direct) | ✅ lattice raw + documented unread display region | ✅ | ✅ | PASS |
| gen-sierpinski-tetrahedron | ✅ | ✅ depthShelf, currentPhase | ✅ | ✅ | ✅ raw trap state, C.r blend kept | ✅ | ✅ | PASS |
| gen-cellular-automata-tapestry | ✅ | ✅ bandEdge, anisoPh | ✅ | ✅ | ✅ raw sim | ✅ | ✅ | PASS |
| gen-audio-spirograph-julia | ✅ | ✅ hypotrochoid, filament | ✅ | ✅ | ✅ display RGBA | ✅ | ✅ | PASS |
| gen-belousov-zhabotinsky | ✅ | ✅ refractory, epsilonField | ✅ | ✅ | ✅ raw sim + B detail | ✅ | ✅ | PASS |

Batch: 6/6 PASS. Diff composition per file is ideas + named floor fixes, not
header/ACES boilerplate (largest floor-only delta is the BZ exact-load +
guard conversion, which is a correctness fix on float history — documented).
No generic spring/ripple/IQ stamp anywhere in the batch.
