# COMMON — sonnet/batch-44 (user's line-count list, mixed gen/retro/image/sim)

Worktree: `/root/iv-sonnet-batch-44` (branch `sonnet/batch-44`, from origin/main 8b35ba3b). HEAD = origin/main for every comparison. Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12. Notes dir: `agents/swarm-outputs/claude-2026-11-19-sonnet-batch-44/` (gitignored → coordinator uses `git add -f`).

Coordinator already ran `migrate_to_prelude.py` (header-only infra) on emergent-calligraphic-weave, physarum-gemini, physarum-grokcf1. **Those three have no `Ideas:` line → first pass** (add `Upgraded:` date / `Ideas:` lines; if an older `Upgraded:` exists, append the date). The other seven ALREADY carry `Ideas:` (second pass): new ideas must be **additional** and native; earlier ideas KEEP VERBATIM.

physarum-gemini and physarum-grokcf1 are near-twins: give them DIFFERENT ideas so they stay distinct. Physarum sims: agent/trail state must live in A/C textures, not extraBuffer (extraBuffer is re-uploaded every frame).

Forks (two files each):
- **A** emergent-calligraphic-weave, gen-neuro-kinetic-bloom
- **B** scanline-drift, xerox-degrade
- **C** cyber-terminal-ascii, pixelation-drift
- **D** physarum-gemini, physarum-grokcf1
- **E** conv-gabor-texture-analyzer, conv-difference-of-gaussians-cascade

Each fork: read the law doc first; fix HEAD defects you find (blank/upside-down/dead sliders/wrong audio) and list them as rescues; verify with naga-wasm + SwiftShader render (see memory/AGENTS.md); time vs HEAD (target ≤ ~1.25×, trim if over); write NOTES-fork<X>.md here. Do NOT commit, do NOT touch other forks' files, do NOT git stash. Shared generated files (shader lists, search index) are the coordinator's job.
