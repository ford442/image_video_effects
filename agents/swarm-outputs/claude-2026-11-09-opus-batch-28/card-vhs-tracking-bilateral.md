# vhs-tracking-bilateral (first pass)
Keep: YUV VHS chain, tracking band at cursor row with bilateral smoothing, AR jitter, dropouts, clicks, C smear.
Ideas:
1. lagging chroma bandwidth — U/V from a 5-tap delayed low-pass row; luma stays sharp (chroma_noise scales lag/mix).
2. dropout comet streaks — rare per-line white flashes decaying rightward (treble + tracking raise rate; freeze on hold).
3. bass tape-stretch wow — line timebase stretches about centre with slow flutter (bass, tracking).
Rescues: dead extraBuffer[133..138] spring removed (direct mouse, same behaviour); alpha was depth*0.85 → ~0 on flat depth, now 0.82 base.
