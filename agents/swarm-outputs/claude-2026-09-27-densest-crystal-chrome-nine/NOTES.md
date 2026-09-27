# Notes: Densest Crystal/Chrome Nine

Per-shader kept-verbatim / packing / idea locations live in each card's `Final (implementer)` section.
Out of scope: gen-chrono-kinetic-fractal-engine (2026-09-15 Ideas already in body).

HEAD state: 6 of 9 were blank, black or mostly invisible at their DEFAULT sliders:
- bismuth-hyper-crystals: camera inside the fold solid (fills a cube of half-size n+1) → one flat colour.
- chromatic-singularity-loom: colour came from `plasmaBuffer[dist*10+time*10]` → black after 0.1 s; `i32(y)` = 0 folds.
- chrono-kitsune: tails ran straight back behind the body → 0 tail pixels.
- chronodynamic-automata: `i32(x)` thread count = 0 threads; thread colour from plasmaBuffer[1..] → black.
- neuro-lattice: IFS-folded box half-size 0.3 filled ~96% of space → t=0, NaN normal.
- liquid-chrome: camera inside the piston column 41-64% of the time.

New/confirmed catalog bug patterns to grep for:
- **`plasmaBuffer[<computed index>]` as a palette LUT** (loom, automata): only index 0 is written; black output.
  Joins aurora-synthesis from the organic-optical seven.
- **`i32(zoom_params.k)` on a 0..1 slider** (loom folds, automata threads): zero for the whole range except 1.0.
- **IFS/KIFS folded solids that fill space** (bismuth, neuro-lattice): after n abs-folds with offset o, the solid
  covers a cube of half-size ~n·o; a box primitive larger than the fold residue range makes the whole cell solid.
- **Camera path through repeated geometry** (chrome): a hall camera on x=0 through an x-repeated column.
- **Per-pixel terms added into the camera position** (chrome clickDrive) → image tears into rings.
- **`readTexture` treated as the previous frame in a generative shader** (automata) → user photo bleeds in.
- **Distance of a scaled lattice divided by the wrong factor** (spider thread2: p*2*wc divided by wc).
- **Float `%` for centred repetition** (neuro-lattice) → seams on the axis planes through screen centre.
- **Upside-down generative scenes** again in 7 of 9 (uv y not flipped); mouse was flipped in some, not others.
- **Step exhaustion shaded as a hit** (kitsune, spider — spider was 91-99% at high sliders).
- **JSON descriptions promising systems not in code** (spider gait/carapace/spring, kitsune "chrono-void lattice").

Slider-scaled time phase jumps remain in 5 files by design (no persistent state slot); audio was removed from every phase.
