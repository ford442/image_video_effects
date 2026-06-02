# sonar-reveal v2 — 4-Agent Swarm Notes

- **Surprising behavior**: The 3 detuned cymatics rings (f=8.0, 8.6, 9.2 Hz with 0.015 detune) create Moiré-like interference beats at their intersection points; treble injects HDR sparkle glints exactly where the rings overlap, making the pattern feel alive and unpredictable rather than a simple repeating circle.
- **Audio reactivity**: Bass accelerates ring expansion speed (×1.0–2.2×) and deepens the echo-return decay; mids drive the temperature color shift (warm gold → cool cyan) and shadow split-tone; treble adds localized sparkle glints on ring-edge intersections.
- **Alpha semantics**: Alpha encodes scene confidence — dim background regions get α≈0.45–0.80 depending on depth (deeper = more transparent/echo-prone), while fully revealed regions and ring edges push α toward 0.85, letting downstream compositors treat the effect as a depth-augmented reveal mask rather than an opaque overlay.
