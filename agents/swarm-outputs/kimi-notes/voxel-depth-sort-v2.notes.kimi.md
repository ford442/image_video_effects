# voxel-depth-sort v2 Upgrade Notes

## Changes
- Added isometric voxel projection with mouse-driven rotation (`isoRot`/`isoTilt`)
- Added depth-buffered Z-sorting approximation via sourceDepth + column height
- Added ambient occlusion (`ao`) and soft shadows
- Added chromatic subsurface scattering (`sss`) on translucent blocks
- Added ACES tone mapping for HDR voxel tops
- Bass drives voxel vertical explosion/disassembly
- Mouse rotates the isometric view
- Depth controls voxel size perspective via `perspective` scaling

## Alpha Semantics
`alpha = depth_confidence * (1.0 - occlusion) * occupancy_term`
- Depth confidence from sourceDepth + column height
- Occlusion from shadowMask and AO attenuation
- Voxel occupancy from topMask blending

## Params
1. Block Size — grid cell pixel size
2. Extrusion — height multiplier
3. BG Darken — background shadow intensity
4. Block Gap — inset gap between blocks

## Line Count
~145 lines
