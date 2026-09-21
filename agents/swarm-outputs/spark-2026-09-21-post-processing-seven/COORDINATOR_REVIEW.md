# Coordinator Review — Post-Processing Seven (2026-09-21)

| Shader | Card first | Ideas pointable | Keep holds | Not boilerplate | No shared idea | A matches C | Params exact | No new spring/ripple | Gates | Verdict |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---|
| `pp-sharpen` | ✅ | ✅ 2/2 | ✅ modes 0–2 kept | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS** |
| `pp-vignette` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS** |
| `pp-chromatic` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS** |
| `temporal-slit-scan` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS** |
| `optical-flow-tracer` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ raw | ✅ | ✅ | ✅ | **PASS** |
| `temporal-frequency-decomposition` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS w/ note** |
| `spatio-temporal-3d-conv` | ✅ corrected | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS w/ note** |

**7 / 7. 14 ideas, none shared.** Two near-duplicates were caught at card time and designed out
(optical-flow's occlusion check vs 3d-conv's bilateral; pp-sharpen's envelope clamp forbidden on 3d-conv).

## Notes

- **`spatio-temporal-3d-conv`** — the card was wrong about sharpen mode and was corrected in BRIEFS,
  visibly, before gating. Applying idea 1 there would have neutralised the mode's whole purpose.
- **`temporal-frequency-decomposition`** — stills glow less at mid/high frequency. Correct spectral
  behaviour, but a visible change for anyone who used it as a still-image glow.
- **Floor ≠ idea.** The history-ring fix touches the most lines in the temporal files and is *not*
  counted toward any card. Four files fixed; seven listed in NOTES as a follow-up.

## §1 test: "would a photographer still use it as X?"

- pp-sharpen → still a sharpen: less haloing, no colour noise. Yes.
- pp-vignette → still a vignette: the falloff looks like a lens. Yes.
- pp-chromatic → still CA: now both kinds real lenses have. Yes.

## GPU reviewer checklist

- **optical-flow-tracer:** 204 fetches/pixel. Check frame time at 1080p on a low-end adapter. Confirm
  trails no longer sprout from flat regions and that a fast pan is tracked.
- **Ring fix:** only visible on a 4-layer fallback device. Force it (small VRAM or the #1204 probe
  override) and compare slit-scan banding before and after.
- **pp-chromatic:** longitudinal CA needs real depth. On a flat depth map `defocus ≈ 0` and idea 1
  does nothing, by design.
- **pp-vignette:** at intensity 1 the cos⁴ term is harsh in the corners of wide frames. Check presets.
