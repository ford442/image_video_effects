# PLAN.md — Weekly Shader Upgrade Agent Swarm

> **Mission**: Keep the image_video_effects / Pixelocity library evolving at the cutting edge of real-time WebGPU visuals.  
> This plan turns Grok, Kimi Code CLI, Jules, Claude, and other agents into a coordinated **weekly upgrade swarm** that adds new shaders, optimizes existing ones, maintains hot-swap reliability, and ships polished PRs.

**Live Demo**: https://go.1ink.us/pixelocity/index.html  
**Repo**: https://github.com/ford442/image_video_effects  
**Companion Guides**: `grok.md`, `AGENTS.md`, `README.md`

---

## 1. Swarm Philosophy & Constraints

- **Compute Shader First** — Every new effect starts as a WGSL compute pass (ping-pong or multi-pass when needed).
- **Hot-Swap Sacred** — New shaders must work by simply dropping a `.wgsl` file + one JSON entry. **Never** modify `Renderer.ts`, `WebGPUCanvas.tsx`, or core bindings unless explicitly approved in a separate architecture PR.
- **Visual Wow Factor** — Prioritize hypnotic, surprising, beautiful, or emotionally resonant results (VJ-ready, music-reactive, depth-aware, mathematical elegance).
- **Interactivity** — Mouse position, click ripples, time, audio uniforms, and AI depth maps are first-class citizens.
- **60 fps Target** — Mid-range GPUs (integrated graphics) must maintain smooth performance. Profile before shipping.
- **Modularity** — Effects should be self-contained. Hybrid effects are allowed but must stay within the standard `Uniforms` interface.
- **Agent Output Discipline**:
  - When creating **new shaders**: Output **only** the `.wgsl` file content + the exact JSON snippet for the category list.
  - For optimizations/fixes: Provide clear diffs or edit instructions.
  - Never touch package.json, tsconfig, or core infrastructure without a dedicated task.

---

## 2. Weekly Cadence (Saturday Morning Ritual)

| Phase | Agent(s) | Duration | Output |
|-------|----------|----------|--------|
| **Discovery & Ideation** | Grok (primary) + Kimi | 30–45 min | 6–10 prioritized shader concepts + category placement |
| **Implementation Wave** | Kimi Code CLI / Grok Build | 2–4 hrs | 5–8 new `.wgsl` files + JSON entries |
| **Optimization Pass** | Optimization-focused agent | 1–2 hrs | 8–12 existing shaders reviewed + improved |
| **Validation & Polish** | Testing agent + Jules | 1 hr | All new shaders pass hot-swap + FPS + interaction tests |
| **Documentation & PR** | Docs + PR agent (Jules/Grok) | 45 min | Updated README counts, new featured examples, ready-to-merge PR |

**Branch Naming**: `weekly-shader-swarm-YYYY-WW` (e.g. `weekly-shader-swarm-2026-22`)

---

## 3. Phase Details

### Phase 1: Discovery & Ideation (Grok Strengths)
Grok leads creative direction. Generate ideas that feel fresh in 2026:

**Priority Categories (rotate focus weekly)**:
- **Liquid / Fluid** (always high priority — core identity)
- **Hybrid Advanced** (Neural, Tensor, Gravitational, Quantum)
- **Audio-Reactive** (tie-ins to Hyphon DAW, spectrogram, beat-reactive)
- **Retro/Glitch + Datamosh**
- **Geometric + Tessellation** (Voronoi evolution, hyperbolic, Penrose)
- **Lighting / Volumetric** (Aurora, God rays, Neon, Plasma)
- **Depth-Aware** (parallax, occlusion, light shafts using existing DPT depth)
- **Simulation** (Physarum, Lenia, Gray-Scott variants, sand, melting)

**Idea Prompts for Grok**:
- “Give me 8 new WebGPU compute shader concepts that would look stunning with mouse interaction and music reactivity. Mix scientific visualization with VJ aesthetics.”
- “Propose hybrid effects that combine reaction-diffusion with raymarching or gravitational lensing.”
- “What would a 2026 update to classic Milkdrop / ProjectM presets look like in pure WGSL compute?”

Output a ranked list with suggested category JSON file and 1-sentence visual description + key technical hook (e.g. “3-pass tensor field advection with mouse vorticity injection”).

### Phase 2: Implementation (Hot-Swap Workflow)
1. Create shader in `public/shaders/` following naming:
   - `liquid-*.wgsl`, `hybrid-*.wgsl`, `audio-*.wgsl`, `glitch-*.wgsl`, `geometric-*.wgsl`, etc.
2. Copy the **exact standard header** from `AGENTS.md` (Uniforms struct, bindings, workgroup sizes, etc.).
3. Implement:
   - Compute shader for state update
   - Fragment shader for final display (or reuse common display logic)
   - Expose interesting uniforms for future UI (intensity, color shifts, speed, etc.)
4. Add **one line** to the correct `public/shader-lists/*.json`:
   ```json
   { "id": "liquid-tensor-vortex", "name": "Tensor Vortex Fluid", "url": "shaders/liquid-tensor-vortex.wgsl", "category": "liquid" }
   ```
5. **Stop**. Do not run build. Hot-swap means refresh browser is enough.

**Grok Build CLI Invocation Example**:
```
You are operating under PLAN.md + grok.md + AGENTS.md for image_video_effects weekly swarm.
Create a new liquid shader called "Chromatic Plasma Melt". 
Output ONLY the complete WGSL file and the JSON entry.
```

### Phase 3: Optimization & Maintenance
- Round-robin review of existing shaders (keep a simple tracking file or GitHub label).
- Common wins:
  - Tune `workgroup_size` (usually 8x8 or 16x16)
  - Reduce texture reads in inner loops
  - Use `var<workgroup>` for shared memory where applicable
  - Early-out conditions for expensive pixels
  - Precompute trig functions or use approximations
- Fix any WGSL warnings or deprecated syntax.
- If a shader is exceptionally heavy, add a “lite” variant or LOD uniform.

### Phase 4: Validation
- Open live demo or `npm start`
- Confirm new shader appears in dropdown immediately
- Test mouse drag/click behavior
- Run for 2+ minutes looking for flicker, NaNs, or memory growth
- Check Chrome + Edge
- If depth-aware: verify AI depth model still integrates cleanly
- Update local shader count in mind (target: steady growth from current 678+)

### Phase 5: Documentation & Release
Update **only** these sections in `README.md`:
- Shader count in intro
- Category table counts
- Featured Shader Examples table (add 2–4 new standout effects with short descriptions)
- Optionally add to “Adding New Shaders” examples if pattern is new

Update this `PLAN.md` only if process itself improved.

**PR Template** (Jules can use this):
```
## Weekly Shader Swarm Upgrade — Week of [DATE]

**New Shaders Added**: X  
**Shaders Optimized**: Y  
**Categories Touched**: ...

### Highlights
- [Shader Name] — [one sentence why it slaps]
- ...

### Performance Notes
All new effects maintain 60fps on [test hardware].

### Testing
- [x] Hot-swap verified
- [x] Mouse interactive
- [x] No console errors
- [x] Cross-browser (Chrome/Edge)

Ready for merge. Swarm continues next week.
```

---

## 4. Agent Role Specialization

| Role | Best Model/Tool | Focus | Constraints |
|------|------------------|-------|-------------|
| **Creative Director / Ideation** | Grok | Visual poetry, new concepts, “wow” factor | Stay within hot-swap rules |
| **Shader Engineer** | Kimi Code CLI, Grok Build | Fast, correct WGSL implementation | Output WGSL + JSON only |
| **Performance Engineer** | Claude / Grok | Profiling, workgroup tuning, memory | Conservative changes |
| **QA & Integration** | Testing agent + manual spot checks | Hot-swap, FPS, interaction, depth | Break nothing |
| **Release Engineer** | Jules (GitHub) | PR creation, description, labels | Follow PR template |

---

## 5. Metrics & Success Criteria (per week)

- **Minimum**: 5 new production-quality shaders + 5 optimizations
- **Target**: 7–10 new shaders + meaningful perf wins on 2–3 heavy effects
- **Quality Bar**: Every new shader must feel portfolio-worthy when shown with music or mouse
- **Process Health**: Hot-swap still works perfectly, no core changes needed
- **Long-term**: Balanced growth across all 15 categories + clear evolution of “signature” effects (advanced hybrids, audio-visual, depth-reactive)

---

## 6. Backlog & Strategic Directions (2026)

- Deeper **audio pipeline** integration (Hyphon sequencer → shader uniforms)
- **Video texture** input effects (datamosh, frame blending, optical flow)
- **Multi-effect chaining** / post-processing graph (future architecture task)
- **Parameter UI** generation from shader comments or JSON metadata
- **Export tools** (record shader animations, shadertoy-style sharing)
- **Cross-project pollination**: Effects reusable in Zephyr, Dog Dash, Watershed, Candy World, weather_clock
- **Educational layer**: Short “how it works” comments + simplified educational variants

---

## 7. How to Trigger a Weekly Run

**As Noah / Human**:
```
@Grok run weekly shader upgrade swarm following PLAN.md
```
or
```
Use Kimi Code CLI in swarm mode with PLAN.md context and generate this week’s batch.
```

**As Agent**:
1. Read `PLAN.md`, `grok.md`, `AGENTS.md`, `README.md`
2. Check current date → create branch `weekly-shader-swarm-2026-XX`
3. Start with Phase 1 (Ideation)
4. Execute phases in order
5. End with ready PR + summary comment

---

## 8. Grok-Specific Notes

You are uniquely positioned for the **Ideation + Creative Direction** and high-level **Grok Build CLI** roles because of your strength in generating surprising, beautiful, and conceptually rich visual ideas.

When operating in swarm mode:
- Lean into cinematic, emotional, or mathematically elegant descriptions.
- Suggest effects that would pair beautifully with the user’s other projects (pedal steel visuals, orbital rave, dog_dash, etc.).
- Always respect the hot-swap contract — it is the superpower of this codebase.
- If you see an opportunity to make the **entire library** better (new uniform, better depth handling, shared noise functions), surface it as a **separate focused PR**, not inside a weekly swarm task.

This plan turns sporadic shader additions into a reliable, compounding creative engine.

**Let’s make the shader library grow like a living organism.** 🌊🌀✨

---

*Maintained as part of the image_video_effects agentic workflow. Update this file only when the swarm process itself evolves.*
