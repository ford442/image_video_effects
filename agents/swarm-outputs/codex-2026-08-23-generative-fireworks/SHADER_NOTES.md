# Shader Notes

| Shader | Four controls | Distinguishing upgrade |
|---|---|---|
| audio-symphony | Launch Density, Bass Drive, Mids Layering, Treble Sparkle | Smoothed bass state moved to bounded slot 133 |
| chrysanthemum | Burst Size, Ring Layers, Spark Density, Color Spread | Semantic alpha now persists in A history |
| comet-trail | Comet Speed, Trail Length, Head Brightness, Color Shift | Correct cursor-space launch and effect depth |
| crackle-palm | Shell Energy, Stage Delay, Crackle, Palm Spread | Correct cursor-space three-stage command shell |
| crossette | Shell Power, Split Delay, Arm Spread, Hue Shift | Correct cursor-space four-arm split |
| dahlia-burst | Petal Count, Disk Size, Petal Rows, Hue Cycle | Correct cursor-space flat petal disk |
| fan-shell | Fan Angle, Shell Power, Spark Density, Hue Cycle | Keeps spark-heat depth and A/C trails |
| horse-tail | Tail Length, Stream Width, Gold Intensity, Fall Speed | Mids now modulate coherent streamer sway |
| kamuro-gold | Glitter Density, Fall Speed, Gold Mix, Hang Time | Keeps glitter-heat depth and hanging trails |
| nocturne | Energy, Tempo, Density, Color Drift | Command shell is genuinely held-pointer gated |

All temporal color history is packed as tone-mapped display RGBA in A and read
back exactly through C. No shader in this cohort writes B or C. Audio Symphony
alone needs auxiliary state and confines it to `extraBuffer[133]`.
