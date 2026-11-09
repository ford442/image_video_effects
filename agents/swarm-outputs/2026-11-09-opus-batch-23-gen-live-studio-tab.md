# gen-live-studio-tab — opus/batch-23 (fork A)
Identity: broadcast control-room overlay (LIVE tally, VU, scopes, safe areas) over the video.
Rescue: (1) layout authored y-up but gid.y=0 is the top row → LIVE/timecode/VU upside down; overlay now uses ov=(x,1-y), mouse flipped to match. (2) safe-area weight `1-a-b` and status-bar `smoothstep-smoothstep` were negative → mix() drove colour < 0 (baseline meanL −0.047); clamped/rewritten; vignette floored.
Ideas:
1. Running Timecode Readout — 7-segment HH:MM:SS:FF (30 fps) inside the previously empty timecode box.
2. Lower-Third Slide-In — name strap wipes in every 8 s with glyph rows, accent bar pulses with mid.
3. Tape Dropout Tears — on bass × Glitch Amount, hashed rows tear sideways with white oxide-dropout streaks.
