# NOTES — fork D
Baselines and after-renders all used SRC=img (minirender_img.mjs, 160px, 20 frames).

digital-crease: HEAD meanL 0.136 → 0.579 (source ≈0.5).
- RESCUE: Hable-style tonemap without exposure divide (0.5 → 0.14) → standard ACES fit.
- RESCUE: dead extraBuffer[133..138] spring pinned cursor fold to (0,0) → live mouse.
- RESCUE: C.r (|fold|) was read as the mask memory and the memory was never shown → C.g EMA, displayed as scars.
- Alpha no longer multiplied by raw depth (flat depth gave alpha 0.08) → mix(0.6,1,depth).
- Ideas: lingering crease scars, pleated-fan panel lighting, crease misregistration. JSON: dropped spring-cursor tag.
crt-scanline-damage: HEAD meanL 0.413; no HEAD bugs found.
- Ideas: burnt phosphor patch, HV arc flash (arc fires ~7% of 1/8 s slots even at treble 0; more with treble).
- Avoided catalog collisions: hum bar (crt-tv), beam-current bloom, flagging (vhs-tracking), stress-whitening (chromatic-folds).
Not committed; generate scripts not run.
