# topological-acoustic-knots v2 Upgrade Notes

## Changes
- Replaced scalar angle field with nematic Q-tensor evolution (Qxx, Qxy, S)
- Added topological charge computation via discrete curl of director field
- Added trefoil-knot SDF constraint that orients the director tangentially
- Added Schlieren texture: darkness proportional to alignment with rotating polarizer
- Defect cores colored by charge type (integer=red, half-integer=blue)
- HDR bloom on +1 defects
- Bass creates defect pairs via Kibble-Zurek quench noise
- Mids drive annihilation dynamics via mobility
- Treble adds acoustic phonon waves
- Mouse homeotropic anchoring pins director radially
- Ripples array spawns new defect loops
- Alpha: order parameter S × (1.0 + defect charge density)

## Lines
- v1: 108 lines
- v2: 175 lines

## Naga
- Validation: PASS (naga 29.0.3)

## Agent Contributions
- **Algorithmist**: Q-tensor reconstruction, topological charge integral, trefoil SDF
- **Visualist**: Schlieren texture, defect core coloring, bloom on +1 defects, ACES
- **Interactivist**: Bass→Kibble-Zurek quench, mids→mobility, treble→phonons, mouse→anchoring, ripples→loops
- **Optimizer**: sin/cos averaging for periodic angle relaxation, compact SDF
