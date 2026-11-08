# gen-prismatic-aether-loom (fork A, 2nd pass)
Rescue: near-black at HEAD (meanL 0.09 / meanA 0.04 at JSON defaults 10,3,0.5,1). Causes: lattice spacing 100/density put threads 5-10 units off-axis; fog 1-exp(-0.05t^2) erased every hit (hits at t~8-14); r=0.1 threads sub-pixel; diff-only lighting; alpha = 0.42*|col| lie for solid cloth.
Fixes: spacing 20/density, radius max(0.1, 0.11*spacing), step 0.6, fog 0.006t^2, ambient 0.3, alpha = fogged hit coverage.
New ideas: punched-card figured lift (scrolling binary card raises warp columns); ikat resist-dye feathering (indigo/madder bands with noisy feathered edges).
After: meanL 0.171 / meanA 0.217 (defaults). All-max sliders + full audio washes to near white (0.92) — open.
Note: idle centred mouse applies a full-frame 2-rad swirl (pre-existing design, left).
