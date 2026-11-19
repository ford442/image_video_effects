# Coordinator review — sonnet/batch-41

Rescues (HEAD defects found by rendering, 7 of 10): megastructure (camera inside y-repeated towers, flat teal, upside down), bismuth (camera flew through the crystal → black from ~3 s), grok41 (orbit camera never looked at the planet; audio from plasmaBuffer[1..8]; ripple.w click scale; pow negative base), collider (extraBuffer spring never persisted → raw mouse; `sprung-magnetic-anomaly` feature tag dropped), anemone (22 identical stacked rings → washed-out disc), vent (upside down; square microbe glows), phoenix (unbounded tail stripe swallowed the bird), polar (36 unmasked shock rings → near-white). Showcase and weaver rendered fine.

Re-timing by coordinator (6 interleaved rounds, 192 px, box load 43–55 from unrelated WASM/C++ builds — still noisy): grok41 median 1.03×, anemone 1.28×, weaver 0.93×, polar 1.09×.

Gates: precommit + naga-wasm on all 10; verify:shaders:fix 11/11; verify:toolchain-foundation 13/13. test:ci 4 timeouts under load (SidebarGroups, WgslDraftSection) — pass when rerun with a 30 s timeout.

Generated files: search index = HEAD + only deep-sea-thermal-vent and gen-grok41-plasma (20 main-drift entries excluded); aliases restored; prelude pending −3 (mine only).

Open: no unanchored reviewer pass; no real-GPU look; anemone centre still saturates and sits at 1.28×; phoenix partly off-frame in landscape; megastructure over-relaxation may shimmer on grazing faces; bismuth Iridescence 0 ≡ 1 (palette period 1.0, pre-existing); comet tails / shuttle / ocelli / tubeworms are local (1–3 % of frame); megastructure + anemone have `params: []` (audit blind spot; sliders verified by hand).
