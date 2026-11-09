# nano-repair (2nd pass)
Existing: healing front on |∇health|; weld flash.
1. Rot contagion — decay rate scales with neighbour damage (0.6–1.4×), rot creeps as fronts.
2. Nanite swarm specks — hashed specks orbiting the cursor inside radius, only while health < 0.995 (idle cursor goes quiet once healed).
3. Weld-scar lattice — A.g holds repair memory (×0.985/frame), drawn as faint cyan seam grid on healed pixels.
Rescues: grain was 0..+glitch (white wash on damage) → zero-mean; alpha ≈0 on healed image → coverage alpha floor 0.4.
