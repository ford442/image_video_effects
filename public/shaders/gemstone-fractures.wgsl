// ═══════════════════════════════════════════════════════════════
//  Gemstone Fractures - Physical Light Transmission with Alpha
//  Category: distortion
//  Features: voronoi shards, rotation, internal fractures, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: rutile silk needles; pointer-lit star asterism; rotation pleochroism
//  A packing: ACES display RGBA (rgb = shaded shard colour, a = transmission alpha)
// ═══════════════════════════════════════════════════════════════
// Simulates fractured gemstone with variable purity/transmission. Each
// Voronoi shard shows the image rotated about its OWN cell centre (HEAD
// pivoted on the screen centre, sending far shards into repeat-sampler
// seams) by a static angle plus a bounded sin oscillation (HEAD's
// time*angle spin grew without limit).
// Audio (plasmaBuffer[0].xyz only): bass -> asterism star intensity,
// treble -> silk needle sparkle. Mouse (zoom_config.yz) is the light
// position: needle glint and star offset follow it; held brightens stars.

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;
const PI: f32 = 3.14159265;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1 — rutile silk needles. pc is the pixel in the shard's crystal frame
// (st units, cell ~1). Three needle families 60° apart; each family tiles its
// own (along, across) frame and hash-places at most one short segment per tile,
// fully inside the tile so no neighbour search is needed. Lines are ~1.5 px
// (AA band is pixel-sized, never sub-pixel). Glint = sheen when the light
// direction Lc (crystal frame) is perpendicular to the needle; twinkle phase is
// per needle and treble sharpens it into sparkle.
// Returns (needle coverage, glinting light).
fn rutileSilk(pc: vec2<f32>, cellId: vec2<f32>, Lc: vec2<f32>, px: f32,
              density: f32, time: f32, treble: f32) -> vec2<f32> {
    let sB = max(0.09, 7.0 * px);   // across-needle spacing
    let sA = sB * 3.3;              // along-needle tile length
    var cover = 0.0;
    var light = 0.0;
    for (var k = 0; k < 3; k++) {
        let phi = f32(k) * PI / 3.0;
        let dir = vec2<f32>(cos(phi), sin(phi));
        let nrm = vec2<f32>(-dir.y, dir.x);
        let fk = f32(k);
        let a = dot(pc, dir) + fk * 1.37;
        let b = dot(pc, nrm) + fk * 2.11;
        let tile = floor(vec2<f32>(a / sA, b / sB));
        let fr = fract(vec2<f32>(a / sA, b / sB));
        let n = hash22(tile + cellId * 17.0 + vec2<f32>(fk * 31.7, fk * 13.3));
        if (n.x < density) {
            let halfLen = sA * (0.18 + 0.27 * n.y);
            let acrossPos = (0.3 + 0.4 * fract(n.x * 7.13 + n.y * 3.7)) * sB;
            let over = max(abs(fr.x * sA - 0.5 * sA) - halfLen, 0.0);
            let dB = abs(fr.y * sB - acrossPos);
            let dist = length(vec2<f32>(over, dB));
            let line = 1.0 - smoothstep(0.5 * px, 1.5 * px, dist);
            let sheen = pow(abs(dot(Lc, nrm)), 6.0);
            let tw = 0.5 + 0.5 * sin(time * (1.5 + 3.0 * n.y) + n.x * 40.0);
            let sparkle = 0.45 + 0.55 * tw + treble * 2.0 * tw * tw * tw;
            cover = max(cover, line);
            light += line * (0.25 + 0.75 * sheen) * sparkle;
        }
    }
    return vec2<f32>(cover, light);
}

// Idea 2 — star asterism. Silk needles scatter light into bands perpendicular
// to themselves, so the six rays run along the three needle NORMALS (crystal
// frame, rotating with the shard). q is the pixel relative to the star centre
// in crystal frame; rays are ~1–3 px wide (width floored at 1.2 px).
fn asterism(qc: vec2<f32>, px: f32) -> f32 {
    let w = max(1.2 * px, 0.012);
    var rays = 0.0;
    for (var k = 0; k < 3; k++) {
        let phi = f32(k) * PI / 3.0;
        let dir = vec2<f32>(cos(phi), sin(phi));
        let nrm = vec2<f32>(-dir.y, dir.x);
        let along = dot(qc, nrm);
        let across = dot(qc, dir);
        rays += exp(-abs(across) / w) * exp(-abs(along) * 3.5);
    }
    let core = exp(-dot(qc, qc) * 60.0);
    return rays * 0.6 + core * 0.8;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: scale (facet size)
    // y: refraction + IOR
    // z: rotationBase
    // w: fractureDensity (affects transmission)
    // ═══════════════════════════════════════════════════════════════
    
    let scale = u.zoom_params.x * 20.0 + 2.0;
    let iorMix = u.zoom_params.y;
    let refraction = u.zoom_params.y * 0.05;
    let rotationBase = u.zoom_params.z;
    let fractureDensity = u.zoom_params.w; // 0 = pure, 1 = heavily fractured

    let audio = plasmaBuffer[0].xyz;
    let bass = clamp(audio.x, 0.0, 1.5);
    let treble = clamp(audio.z, 0.0, 1.5);
    let mouse = u.zoom_config.yz;           // 0..1, y=0 top (same as uv)
    let held = u.zoom_config.w > 0.5;
    
    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

    let aspectVec = vec2<f32>(aspect, 1.0);
    let st = uv * aspectVec * scale;
    let i_st = floor(st);
    let f_st = fract(st);
    let px = scale / resolution.y;          // one pixel in st units

    // Voronoi / Cellular logic
    var m_dist = 1.0;
    var second_dist = 1.0;
    var m_point = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);
    var m_rel = vec2<f32>(0.0);             // pixel minus cell centre (st)

    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);
            // Animate point
            let animPoint = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);
            let diff = neighbor + animPoint - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                second_dist = m_dist;
                m_dist = dist;
                m_point = point;
                cell_id = i_st + neighbor;
                m_rel = -diff;
            } else if (dist < second_dist) {
                second_dist = dist;
            }
        }
    }

    // Refraction based on cell ID. HEAD FIX: static tilt kept (±5z rad),
    // but the spin is now a bounded oscillation (±1.5z rad) instead of the
    // unbounded time * angle ramp.
    let cellHash = m_point; // == hash22(cell_id)
    let spin = (cellHash.y - 0.5) * rotationBase * 3.0 * sin(time * 0.35 + 6.2831 * cellHash.x);
    let rotAngle = (cellHash.x - 0.5) * rotationBase * 10.0 + spin;
    let c = cos(rotAngle);
    let s = sin(rotAngle);

    // HEAD FIX: rotate the UV space locally around the SHARD's own centre
    // (aspect-corrected), so every shard stays on its own patch of image.
    let centerSt = st - m_rel;
    let centerUV = centerSt / (scale * aspectVec);
    let fromCenter = (uv - centerUV) * aspectVec;
    let rotFromCenter = vec2<f32>(
        fromCenter.x * c - fromCenter.y * s,
        fromCenter.x * s + fromCenter.y * c
    );
    let sampleUV = centerUV + rotFromCenter / aspectVec;

    // Chromatic aberration with dispersion
    let dispersion = (ior - 1.0) * 0.3;
    let uvR = clamp(sampleUV + vec2<f32>(refraction * (1.0 + dispersion), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(sampleUV - vec2<f32>(refraction * (1.0 - dispersion), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // ═══════════════════════════════════════════════════════════════
    // Idea 3 — pleochroism: the shard's crystal c-axis is a per-cell hash
    // plus its rotation angle; body tint swings between two hues (iolite:
    // violet-blue vs honey) by cos(2θ). Strength follows IOR (zoomParam2).
    // ═══════════════════════════════════════════════════════════════
    let axisAngle = hash21(cell_id + vec2<f32>(19.1, 7.3)) * PI + rotAngle;
    let pleoMix = 0.5 + 0.5 * cos(2.0 * axisAngle);
    let pleoHue = mix(vec3<f32>(0.80, 0.84, 1.10), vec3<f32>(1.08, 0.97, 0.78), pleoMix);
    let pleoStrength = 0.3 + 0.45 * iorMix;
    color *= mix(vec3<f32>(1.0), pleoHue, pleoStrength);

    // ═══════════════════════════════════════════════════════════════
    // Physical Transmission & Fracture Effects
    // ═══════════════════════════════════════════════════════════════
    
    // Per-cell fracture amount
    let cellFracture = hash21(cell_id);
    let effectiveFracture = fractureDensity * (0.5 + 0.5 * cellFracture);
    
    // Purity: inverse of fracture
    let purity = 1.0 - effectiveFracture;
    
    // Distance from cell center affects angle
    let cosTheta = 1.0 - m_dist; // Approximate
    let fresnel = fresnelSchlick(clamp(cosTheta, 0.0, 1.0), F0);
    
    // Path length (longer near edges)
    let pathLength = mix(0.05, 0.4, m_dist) / max(purity, 0.1);
    
    // Absorption increases with fractures
    let absorptionCoeff = mix(0.2, 4.0, effectiveFracture);
    let absorption = exp(-absorptionCoeff * pathLength);
    
    // Edge distance for highlighting
    let edgeDist = second_dist - m_dist;
    let edgeFactor = smoothstep(0.02, 0.0, edgeDist);
    
    // Transmission coefficient
    let transmission = absorption * (1.0 - fresnel) * purity;
    
    // Add fracture lines (reduce transmission at cell boundaries)
    let fractureLine = smoothstep(0.01, 0.0, edgeDist) * effectiveFracture;

    // Pointer-as-light: direction from this shard's centre to the mouse,
    // expressed in the shard's crystal frame (rotates with the shard).
    let mouseSt = mouse * aspectVec * scale;
    let md = mouseSt - centerSt;
    let L = md / max(length(md), 1e-3);
    let crystal = rot2(rotAngle);
    let Lc = crystal * L;
    let pc = crystal * m_rel;

    // Idea 1 — rutile silk needles (density rises with fractureDensity).
    let needleDensity = 0.25 + 0.6 * fractureDensity;
    let silk = rutileSilk(pc, cell_id, Lc, px, needleDensity, time, treble);
    let silkCol = vec3<f32>(1.0, 0.86, 0.55); // golden rutile
    color = color * (1.0 - 0.12 * silk.x) + silkCol * silk.y * 0.35;

    // Idea 2 — star asterism: centre offset toward the light (bounded to
    // 0.35 cell), so each shard's star glides with the mouse. Bass and a
    // held pointer brighten it; fades before the fracture line.
    let starOff = md / (1.0 + length(md)) * 0.35;
    let qc = crystal * (m_rel - starOff);
    var starGain = (0.2 + 0.6 * needleDensity) * (0.7 + 0.9 * bass) * (0.6 + 0.4 * cellHash.y);
    if (held) { starGain *= 1.35; }
    let star = asterism(qc, px) * starGain * smoothstep(0.0, 0.08, edgeDist);
    color += vec3<f32>(1.0, 0.95, 0.85) * star;
    
    // Specular on edges
    let specular = edgeFactor * fresnel * 0.5;
    color += vec3<f32>(specular);
    
    // Fracture tint (internal scattering)
    let fractureTint = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.85, 0.8), effectiveFracture);
    color = color * fractureTint;

    color = acesToneMap(max(color, vec3<f32>(0.0)));

    // Alpha based on transmission
    let alpha = clamp(transmission * (1.0 - fractureLine), 0.3, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    // A: display RGBA (nothing reads it back; this effect has no feedback)
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
    
    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
