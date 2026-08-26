# Codex Generative Fireworks Batch

Upgraded ten existing effects in place while preserving their shell identities:

- `gen-fireworks-audio-symphony`: bass-envelope launches, mids shells, and treble sparks.
- `gen-fireworks-chrysanthemum`: dense spherical rings and advected petal trails.
- `gen-fireworks-comet-trail`: brilliant moving heads with long peeling tails.
- `gen-fireworks-crackle-palm`: delayed crackle followed by palm fronds.
- `gen-fireworks-crossette`: cardinal four-arm splits and sub-bursts.
- `gen-fireworks-dahlia-burst`: layered flat-disk petal rows.
- `gen-fireworks-fan-shell`: wide hemispherical fan geometry.
- `gen-fireworks-horse-tail`: narrow falling gold brocade streamers.
- `gen-fireworks-kamuro-gold`: hanging gold/silver glitter clouds.
- `gen-fireworks-nocturne`: varied cinematic mortar field and held command shell.

Every shader has the renderer's 13 bindings, a 16×16×1 workgroup, exact
`textureLoad` feedback from `dataTextureC`, feedback writes only to
`dataTextureA`, live bass/mids/treble response, semantic alpha, generated depth,
and ACES output tone mapping. Each definition exposes four named controls mapped
to `zoom_params.x/y/z/w`.
