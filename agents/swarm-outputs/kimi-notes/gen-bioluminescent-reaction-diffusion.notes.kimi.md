# gen-bioluminescent-reaction-diffusion — Kimi Notes

## Changes
- Chromatic species separation: species A tinted green/cyan, species B tinted magenta/purple for visual clarity.
- Temporal mutation: feed/kill rates slowly drift with `time` and `mids`/`bass`, preventing static pattern lock.
- Depth-scaled glow: `readDepthTexture` attenuates glow intensity in background regions.
- Data persistence maintained via `dataTextureA` for stable ping-pong simulation state.

## Wow-Factor
- Two competing chemical species glow in contrasting neon colors — a living petri dish on screen.
- Depth scaling makes foreground reaction blooms feel physically present.

## Risks
- Temporal mutation can destabilize the classic Gray-Scott patterns if parameters drift too far; clamps are conservative.
- 9 texture loads per pixel for Laplacian plus depth read = 10 fetches; monitor on mobile.
