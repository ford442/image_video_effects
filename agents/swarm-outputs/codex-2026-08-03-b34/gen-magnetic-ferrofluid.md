# Changelog — gen-magnetic-ferrofluid (Batch 34)

Lines: 186 → 219.

- Corrected the double-normalized camera pointer and made Fluid Density drive
  actual mass, spike spacing, and droplet volume.
- Added sprung orbit, click magnetic shells, multiband lighting, bounded ACES
  output, explicit hit detection, temporal A history, and real hit depth.
- Preserved the four saved ferrofluid control roles.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
