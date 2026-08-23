# Codex (c) liquid shader ownership notes

- **Liquid Smear:** A/C is final tone-mapped display RGBA.
- **Liquid Tensor Vortex:** A/C is final tone-mapped display RGBA. The invalid
  generic clock-ring appendix was replaced by tensor-directed optics.
- **Liquid Rainbow Prismatic:** A/C is final tone-mapped display RGBA; the old
  diagnostic B write was removed.
- **Liquid Perspective:** A/C is final tone-mapped display RGBA.
- **Liquid RGB:** A/C is final tone-mapped display RGBA.
- **Liquid Viscous:** A/C is raw `velocity.xy / dye / pressure`. Display color
  is written only to `writeTexture` and never fed back as simulation state.
- **Liquid Viscous Simple:** A/C is final tone-mapped display RGBA.
- **Liquid Zoom:** A/C is final tone-mapped display RGBA.
- **Luma Melt Interactive:** A/C is final tone-mapped display RGBA.
- **Viscous Drag:** A/C is raw `offset.xy / thickness / drag energy`. Thickness
  and energy diffuse and recover with the offset field.

All C reads are bounded exact loads. No cohort shader stores B or accesses
`extraBuffer`; no global state is required.
