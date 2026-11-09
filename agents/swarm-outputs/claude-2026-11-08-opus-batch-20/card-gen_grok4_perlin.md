SHADER: gen_grok4_perlin / gen-grok4-perlin (2nd pass)
IDENTITY: hydraulic/aeolian erosion terrain sim in C/A (erosion, sediment, water, uplift), lit with terraces, foam, talus, rills
KEEP VERBATIM: solver, packing, all four earlier ideas, params
RESCUES: valley fog smoothstep(0,0.4,1−h) fogged everything below h=0.6 at 42% → washed grey (meanL 0.76); now only true low valleys (0.45,0.9). Clamp ≥0 before ACES.
ADD: 1. aeolian sand ripples — transverse crests across the wind (+x) on flat sediment-laden ground, drifting with the gust; wind slider deepens
     2. capillary fringe — darkened damp band just above the water table, height grows with water + mids
A PACKING: unchanged
Stats @160 defaults: before meanL 0.758 std 0.034 → after 0.529 std 0.156.
