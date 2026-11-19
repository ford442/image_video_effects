# NOTES — fork B (gen-bismuth-hyper-crystals, gen_cyclic_automaton) — both second pass

## gen_cyclic_automaton
Ideas added (earlier four kept verbatim): spiral-rotor phase-singularity cores (3x3 holds rest+fire+early+late cooling → ember, bass gain); head-on collision annihilation seams (resting cell lit from N+S or E+W → white flash, mids gain).
Rescue (HEAD defect, confirmed by render): default frame was a uniform yellow refractory mush with a diagonal sin-hash lattice — ~1% of cells ignited per frame so no wavefront ever formed (meanL 0.69, stdL 0.03). Fixed: PCG integer hash seeded by frame index; spontaneous/treble ignition rates scaled down (spontaneity slider still sets the rate). Now discrete expanding diamond waves on a dark field (meanL 0.36, stdL 0.28). Dropped dead `time*6.5`.
Not fixed (library-wide): extraBuffer[133..138] spring mouse never persists, so directional drag weighting is inert.
Timing 256², 4 interleaved rounds at load ~40: 1.31/1.07/1.49/0.82 → median ~1.19 (noise; loop over a 9-element array of already-loaded states, no new loads).

## gen-bismuth-hyper-crystals
Ideas added (earlier two kept): stepped oxide-film thickness per coarse hopper terrace (discrete interference band per terrace); molten growth-front shell (orange band at |p| = growth*R sweeps outward with the growth cycle, bass gain). Tried and dropped: fine (10/unit) terraces + lip occlusion (aliased, washed the palette); newest-generation dN–dN1 front (gap ≈0.5 everywhere, not a signal).
No HEAD defects found. meanL 0.321 HEAD → 0.323 new at t=4.
Timing 192², rounds: 0.92/0.85/0.99/0.74 → median ~0.89.

Gates: naga-wasm 2/2, precommit 2/2. JSON: description appended, features already had the three tags.
