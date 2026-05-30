# gen-minimal-surface-soap-iridescence v1 Notes

## Concept
Parametric minimal surfaces (catenoid ↔ helicoid) morphing via Bonnet rotation.
Thin-film interference on soap film surface creates rainbow iridescence.
Mean curvature approximates film thickness for optical path length.

## Algorithm
- Parametric evaluation of catenoid and helicoid at each pixel (u,v)
- Bonnet rotation blends between surfaces: S_blend = S_cat × cos(θ) + S_hel × sin(θ)
- Treble adds bubble nucleation perturbation
- Mouse poke creates local dimple in surface
- 3D rotation for perspective, then project to 2D
- Thin-film interference: hue = fract(optical_path_length × constant)

## Visual Design
- Rainbow soap-film colors from thin-film interference
- HDR caustics where curvature is high
- Subsurface scattering on thickness gradients
- ACES tone mapping

## Audio Reactivity
- Bass: drives Bonnet rotation speed
- Mids: controls surface tension (film thickness)
- Treble: adds bubble nucleation/bursting perturbation

## Interactivity
- Mouse click pokes the film, creating a dimple depression
- Zoom params control Bonnet angle and Y-rotation

## Alpha Semantics
Alpha = film_thickness × curvature_magnitude × depth
Thicker, more curved, closer regions are more opaque.

## Params
1. bonnet (p1): Bonnet rotation angle offset
2. tension (p2): Surface tension / film thickness
3. yRotation (p3): Y-axis rotation speed offset
4. caustics (p4): Caustic glow strength (not currently wired — future)

## Validation
- naga: PASS
