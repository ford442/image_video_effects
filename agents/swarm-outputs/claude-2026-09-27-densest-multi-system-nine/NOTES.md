# Notes: Densest Multi-System Nine

Bug patterns found in HEAD that are new to this batch. Grep the catalog for them.
- Solid-disc "rings": `max(length(xy)-R, abs(z)-w)` inside a z-repeat is a disc, not a ring. Every ray hits it, so the tunnel never shows (collider).
- fbm gate that can never open: fbm stays within ±0.15, so `smoothstep(0.4, 0.8, f1*f2)` is always 0 (ferro-monolith aurora).
- Voronoi `neighbor` added twice, so the noise jumps at every integer face (dyson).
- Depth written by clamping centred UV into 0..1 and passing through input depth (dyson).
- A duplicate `"params"` key in the JSON. JSON.parse keeps the last one, so the first is dead weight (dyson).
- Per-sector variation inside angular domain repetition tears the SDF at sector seams unless it is blended to be continuous at the boundary (bismuth).
- An extrusion slider gated entirely on bass: the geometry does not exist at audio 0 (bismuth).
- A shader using its own C history as "audio" (accretion forge).

This session left everything uncommitted. The worktree is shared with other sessions, so public/shader-lists/generative.json also contains their entries.
