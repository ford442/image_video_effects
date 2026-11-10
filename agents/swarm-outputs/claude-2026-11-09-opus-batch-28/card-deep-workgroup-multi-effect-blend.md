# deep-workgroup-multi-effect-blend (1st pass)
1. **Content-arbitrated lane weights** — each lane's .a is a vote (edge strength, bright-pass energy, saturation, phosphor amt); weighted not 25% each.
2. **Phosphor afterglow** — phosphor lane decays max(now, prev·0.85·amt) from C history (A.a), green persistence tail.
3. **Held-pointer lane solo lens** — disc under pointer while held solos one lane per quadrant.
Plumbing: bass lowers bloom threshold/raises gain, mids speed hue; A written; alpha semantic.
Rescue: @workgroup_size had been flattened to (16,16,1) so lid.z==0 always → only edge lane ran, others blended as zero (¼-brightness image). Restored (16,16,4). Workgroup storage kept at exactly 16 KiB.
Verified on SwiftShader (max 256 invocations) via an (8,8,4) temp copy; real 1024-lane path unverified.
