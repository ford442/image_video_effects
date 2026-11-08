SHADER: boids (2nd pass)
IDENTITY: 256 GPU boids flocking on a torus, hue = heading, soft alpha splats
KEEP VERBATIM: flocking rules, blind-spot cone, predator cursor, row-0 state packing, params
RESCUES: near-invisible flock — coverage scaled density by 0.1 (lone boid ~7%) and colour was the alpha-weighted sum tone-mapped (pre-darkened twice); now un-premultiplied + density*1.2. Added plasmaBuffer[0] audio (had none).
ADD: 1. wingbeat flicker — per-boid flap phase pulses splat width across heading (bass = faster)
     2. murmuration ink — dense overlaps darken to a starling-black core
     3. fading wakes — rows >=1 of A keep a decaying splat trail (mids lengthen)
FORBID: ripples overlay, palette swap, spring cursor
A PACKING: row 0 boid state; rows >=1 wake RGB(premult)+coverage
