import re

# 4. gen-ethereal-quantum-hologram-bonsai
with open('public/shaders/gen-ethereal-quantum-hologram-bonsai.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Hologram Bonsai
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            hologram, l-system, quantum, iridescence, curl-noise, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: prune-cut seal rings at terminal branch tips; north-facing moss lichen from bark normal vs up-light; hologram scan-line glitches; falling quantum leaves
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

leaves_orig = """  // Root ripple from bass peaks
  let rootRipple = sin(uv.x * 10.0 + time * 3.0) * cos(uv.y * 8.0) * bassSmooth * audioReact * 0.1;
  col += vec3<f32>(0.0, 0.1, 0.2) * max(rootRipple, 0.0);"""
leaves_new = """  // Root ripple from bass peaks
  let rootRipple = sin(uv.x * 10.0 + time * 3.0) * cos(uv.y * 8.0) * bassSmooth * audioReact * 0.1;
  col += vec3<f32>(0.0, 0.1, 0.2) * max(rootRipple, 0.0);

  // Idea 2: Falling quantum leaves (detached particles fluttering downward)
  let leafUV = uv * vec2<f32>(10.0, 5.0) - vec2<f32>(0.0, time * 0.5);
  let leafCell = floor(leafUV);
  let leafFract = fract(leafUV);
  let leafHash = hash3(vec3<f32>(leafCell, 0.0));
  let isLeaf = step(0.98, leafHash) * smoothstep(0.2, 0.0, length(leafFract - vec2<f32>(0.5)));
  col += vec3<f32>(0.1, 0.8, 0.4) * isLeaf * (1.0 + mid * 2.0);"""
code = code.replace(leaves_orig, leaves_new)

scanline_orig = """    // Distance fade
    col *= exp(-t * 0.08);
  }"""
scanline_new = """    // Distance fade
    col *= exp(-t * 0.08);

    // Idea 1: Hologram scan-line glitches (horizontal bands of noise)
    let scanLine = step(0.98, sin(uv.y * 150.0 + time * 20.0)) * instability;
    col += vec3<f32>(0.2, 0.8, 0.6) * scanLine * (0.5 + treble);
    col.r += scanLine * 0.2;
    col.b -= scanLine * 0.2;
  }"""
code = code.replace(scanline_orig, scanline_new)

with open('public/shaders/gen-ethereal-quantum-hologram-bonsai.wgsl', 'w') as f:
    f.write(code)


# 7. gen-ethereal-anemone-bloom
with open('public/shaders/gen-ethereal-anemone-bloom.wgsl', 'r') as f:
    code = f.read()

header2 = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal Anemone Bloom
//  Category: generative
//  Features: mouse-driven, audio-reactive, click-reactive, raymarching, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: spring-eased current eddy (pointer vortex centre persists in
//         extraBuffer and lags like water); bass-envelope tentacle
//         retraction (anemones flinch shorter on hits, relax slowly);
//         peristaltic feeding pulse of light travelling up each tentacle
//         (speed from mids, bands from treble); plankton catch flashes; oral disk central glow
//  A packing: display RGB history (pre-ACES) + semantic tissue alpha;
//             read back via exact textureLoad(dataTextureC, coord, 0)
//  Engine: zoom_config.yz = mouse, zoom_config.w = mouse-down, config.y = ripple count
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header2, code, flags=re.DOTALL)

feedCol_orig = """            let feedCol = vec3<f32>(0.2, 0.95, 0.85) * (0.5 + audioMid);
            emissive += feedCol * band * u.zoom_params.z * 0.35 * (1.0 - fogAmountEarly(t, water_murkiness));
            glowIntensity = max(glowIntensity, band * u.zoom_params.z * 0.4);
        }"""
feedCol_new = """            let feedCol = vec3<f32>(0.2, 0.95, 0.85) * (0.5 + audioMid);
            emissive += feedCol * band * u.zoom_params.z * 0.35 * (1.0 - fogAmountEarly(t, water_murkiness));
            glowIntensity = max(glowIntensity, band * u.zoom_params.z * 0.4);
            
            // Idea 1: Plankton catch flashes: Tiny bright sparks where feeding pulses reach the tentacle tips.
            if (mat == 3.0) {
                let flashNoise = noise(p.xz * 50.0 + vec2<f32>(fullTime * 5.0, 0.0));
                let catchFlash = step(0.9, flashNoise) * band;
                emissive += vec3<f32>(1.0, 0.9, 0.6) * catchFlash * (2.0 + audioHigh * 5.0);
            }
        }
        
        let cell_size = mix(8.0, 2.0, u.zoom_params.y);
        let id = floor(p.xz / cell_size);
        let cell_center = (id + 0.5) * cell_size;
        let local_p = p.xz - cell_center;
        
        if (mat == 2.0) {
            // Idea 2: Oral disk central glow: A deep pulsing light source emanating from the center
            let oralDiskDist = length(local_p);
            let oralDiskGlow = smoothstep(1.0, 0.0, oralDiskDist) * smoothstep(1.0, 0.0, p.y + 4.0);
            emissive += vec3<f32>(0.8, 0.2, 0.6) * oralDiskGlow * (0.5 + audioBass * 2.0);
        }"""
code = code.replace(feedCol_orig, feedCol_new)

with open('public/shaders/gen-ethereal-anemone-bloom.wgsl', 'w') as f:
    f.write(code)

