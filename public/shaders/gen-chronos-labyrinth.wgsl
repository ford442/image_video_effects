// ═══════════════════════════════════════════════════════════════════
//  Chronos Labyrinth - Escher-esque Shifting Maze
//  Category: generative
//  Features: raymarching, impossible-geometry, temporal-rifts, mouse-driven, audio-reactive,
//            aces-tone-map, upgraded-rgba, depth-aware, temporal-feedback, chromatic-aberration,
//            hue-preserve-clamp, ign-dither, distance-lod
//  Complexity: High
//  Created: 2026-05-10
//  By: Claude Sonnet 4.6 (swarm optimization pass 2026-05-31; F1 flagship deep upgrade 2026-06-07)
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════
//  OPTIMIZATION LOG (2026-05-31):
//  - MAX_STEPS reduced 128→80 (~38% raymarch budget reduction)
//  - Soft shadows removed (saved 32 map() calls per lit pixel = dominant perf win)
//  - Ambient occlusion retained for contact shadow feel
//  - Reinhard replaced with ACES (hue-preserving, broadcast-safe highlights)
//  - Bass reactivity added to fog density and camera drift
//  - IGN dither added before final write
//
//  F1 FLAGSHIP DEEP UPGRADE (2026-06-07):
//  - Distance-based ray-step LOD: stride relaxes from 0.8→1.15 past 60% of MAX_DIST,
//    cutting iterations in empty space (background-heavy frames see the biggest win)
//  - Early-exit on atmosphere-faded hits: skips calcNormal (6 map() calls) + calcAO
//    (5 map() calls) + full lighting model for pixels whose predicted alpha < 0.02 —
//    those ~11 extra map() evaluations per far pixel are pure waste once fog swallows them
//  - Temporal Rift memory: dataTextureA now stores a slow-decaying rift-glow echo,
//    read back via dataTextureC next frame — rifts leave faint "afterimage" trails that
//    breathe in and out, giving the anomalies a genuine sense of bleeding through time
//  - huePreserveClamp before ACES — keeps rift cyan/turquoise saturated at peak brightness
//  - Chromatic aberration on rift glow — RGB channel offset scaled by mid-band energy

// --- STANDARD HEADER ---
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

// ---------------------------------------------------
struct Uniforms {
    config: vec4<f32>, // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>, // x=Complexity, y=ShiftSpeed, z=TemporalRifts, w=AtmosphericPerspective
    ripples: array<vec4<f32>, 50>,
};

// Parameters (accessed via u.zoom_params.x etc. inside functions)
// Constants
const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 80;  // was 128 — 38% reduction, depth coherence hides the difference
const MAX_DIST: f32 = 40.0;
const SURF_DIST: f32 = 0.001;

// 2D Rotation matrix
fn rot2D(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Rotation around X axis
fn rotX(p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

// 3D Rotation around Y axis
fn rotY(p: vec3<f32>, a: f32) -> vec3<f32> {
    var c = cos(a);
    var s = sin(a);
    return vec3<f32>(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

// 3D Rotation around Z axis
fn rotZ(p: vec3<f32>, a: f32) -> vec3<f32> {
    var c = cos(a);
    var s = sin(a);
    return vec3<f32>(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

// SDF Primitives
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Domain repetition with cell index output
fn opRepId(p: vec3<f32>, c: vec3<f32>) -> vec4<f32> {
    let cell = floor(p / c + 0.5);
    let q = p - c * cell;
    return vec4<f32>(q, cell.x + cell.y * 7.0 + cell.z * 13.0);
}

// Staircase SDF - composed of repeated steps
fn sdStaircase(p: vec3<f32>, steps: i32, width: f32, height: f32, depth: f32) -> f32 {
    var d = 1000.0;
    let step_h = height / f32(steps);
    let step_d = depth / f32(steps);
    
    for (var i = 0; i < steps; i++) {
        let fi = f32(i);
        let step_pos = p - vec3<f32>(0.0, fi * step_h, fi * step_d);
        let step_box = vec3<f32>(width, step_h * 0.5, step_d * 0.5);
        d = min(d, sdBox(step_pos, step_box));
    }
    return d;
}

// Hash function for random values
fn hash3(p: vec3<f32>) -> f32 {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q.x) * 43758.5453);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

// Smooth min for blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// The Map function - defines the labyrinth geometry
fn map(p: vec3<f32>) -> vec2<f32> {
    var time = u.config.x;
    let bass = plasmaBuffer[0].x;
    
    // Base repetition size based on complexity
    let cell_size = mix(4.0, 1.5, u.zoom_params.x);
    
    // Get cell repetition
    let rep = opRepId(p, vec3<f32>(cell_size));
    var q = rep.xyz;
    let cell_id = rep.w;
    let cell_hash = hash1(cell_id);
    
    // Time-based shifting rotation for each cell
    let shift_time = time * u.zoom_params.y * (0.5 + cell_hash);
    var rq = rotY(q, shift_time + cell_hash * 6.28);
    rq = rotX(rq, shift_time * 0.7);
    
    // Determine structure type based on cell hash
    let structure_type = floor(cell_hash * 4.0); // 0-3 different structures
    
    var d = 1000.0;
    var mat_id = 1.0; // Default wall material
    
    // Create different structures based on parity/type
    if (structure_type < 1.0) {
        // Central block with corridor
        d = sdBox(rq, vec3<f32>(1.2, 0.3, 1.2));
        let corridor = sdBox(rq, vec3<f32>(0.4, 2.0, 0.4));
        d = max(d, -corridor); // Subtract corridor
    } else if (structure_type < 2.0) {
        // Staircase structure
        let stair_steps = 6;
        // Alternate staircase orientations
        if (cell_hash > 0.5) {
            d = sdStaircase(rq, stair_steps, 0.8, 1.5, 1.5);
        } else {
            // Sideways staircase
            let rqz = rotZ(rq, PI * 0.5);
            d = sdStaircase(rqz, stair_steps, 0.6, 1.2, 1.2);
        }
    } else if (structure_type < 3.0) {
        // Platform with pillars
        let platform = sdBox(rq - vec3<f32>(0.0, -0.8, 0.0), vec3<f32>(1.5, 0.2, 1.5));
        let pillar1 = sdBox(rq - vec3<f32>(1.0, 0.0, 1.0), vec3<f32>(0.15, 1.0, 0.15));
        let pillar2 = sdBox(rq - vec3<f32>(-1.0, 0.0, -1.0), vec3<f32>(0.15, 1.0, 0.15));
        let pillar3 = sdBox(rq - vec3<f32>(1.0, 0.0, -1.0), vec3<f32>(0.15, 1.0, 0.15));
        let pillar4 = sdBox(rq - vec3<f32>(-1.0, 0.0, 1.0), vec3<f32>(0.15, 1.0, 0.15));
        d = min(platform, min(pillar1, min(pillar2, min(pillar3, pillar4))));
    } else {
        // Arched corridor
        let arch = sdBox(rq, vec3<f32>(0.8, 2.0, 0.8));
        let arch_cut = sdTorus(vec3<f32>(rq.x, rq.y - 1.5, rq.z), vec2<f32>(0.6, 0.25));
        let side_cut = sdBox(rq, vec3<f32>(0.3, 2.0, 1.0));
        d = max(arch, -arch_cut);
        d = max(d, -side_cut);
    }
    
    // Add connecting bridges between nearby cells (creates the maze effect)
    let bridge_hash = hash1(cell_id * 1.618);
    if (bridge_hash > 0.4) {
        var bridge = sdBox(q - vec3<f32>(cell_size * 0.5, 0.0, 0.0), vec3<f32>(0.8, 0.15, 0.4));
        d = min(d, bridge);
    }
    if (bridge_hash > 0.7) {
        var bridge = sdBox(q - vec3<f32>(0.0, cell_size * 0.3, 0.0), vec3<f32>(0.4, 0.6, 0.4));
        d = min(d, bridge);
    }
    
    // Temporal Rifts - glowing anomalies
    let rift_intensity = u.zoom_params.z * (1.0 + bass * 0.3);
    if (rift_intensity > 0.01) {
        let rift_hash = hash1(cell_id * 3.14159);
        let rift_time = time * (0.3 + rift_hash * 0.5);
        let rift_pulse = sin(rift_time) * 0.5 + 0.5;
        
        // Only show rift based on intensity and timing
        if (rift_pulse < rift_intensity * 0.5) {
            let rift_pos = vec3<f32>(
                sin(rift_hash * 6.28) * 0.8,
                cos(rift_hash * 4.13) * 0.5,
                sin(rift_hash * 2.71) * 0.8
            );
            let rift_size = 0.2 + rift_pulse * 0.3;
            let rift = sdSphere(q - rift_pos, rift_size);
            
            // Blend rift with geometry using smooth min
            d = smin(d, rift, 0.3);
            if (rift < d + 0.1) {
                mat_id = 2.0; // Rift material
            }
        }
    }
    
    return vec2<f32>(d, mat_id);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - map(p - vec3<f32>(e, 0.0, 0.0)).x,
        map(p + vec3<f32>(0.0, e, 0.0)).x - map(p - vec3<f32>(0.0, e, 0.0)).x,
        map(p + vec3<f32>(0.0, 0.0, e)).x - map(p - vec3<f32>(0.0, 0.0, e)).x
    ));
}

// ACES filmic tone mapping (replaces Reinhard — hue-neutral and broadcast safe)
fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp (from AGENTS.md) — keeps rift cyan saturated pre-ACES ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, maxLum / max(l, 1e-4));
}

// Soft shadows removed — was calcSoftShadow() doing 32 map() calls per pixel.
// AO provides enough contact-shadow feel at much lower cost.
// Shadow approximated as (ao * diff) which is visually comparable at these camera distances.

// Ambient occlusion
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 0; i < 5; i++) {
        var h = 0.001 + 0.15 * f32(i) / 4.0;
        var d = map(p + h * n).x;
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 1.5 * occ, 0.0, 1.0);
}

// Raymarch
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var t = 0.0;
    var mat = 0.0;
    
    for (var i = 0; i < MAX_STEPS; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        
        if (d < SURF_DIST || t > MAX_DIST) {
            mat = res.y;
            break;
        }
        // ═══ CHUNK: distance-lod-step — relax stride with distance (AGENTS.md pattern) ═══
        // Near camera: 0.8x stride preserves surface detail. Past 60% of MAX_DIST,
        // empty-space traversal dominates — widen toward 1.15x to reach the horizon
        // (or a hit) in fewer iterations. Detail loss there is masked by fog/atmosphere.
        let stepLOD = mix(0.8, 1.15, smoothstep(0.0, MAX_DIST * 0.6, t));
        t += d * stepLOD;
    }
    
    return vec3<f32>(t, mat, 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    var time = u.config.x;
    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Audio reactivity — bass swells fog, mid brightens rift glow
    let bass = plasmaBuffer[0].x;
    let mid  = plasmaBuffer[0].y;

    // Camera setup with mouse orbit
    var mouse = u.zoom_config.yz;
    let angleX = (mouse.x - 0.5) * 6.2832 + time * 0.05; // Slow auto-rotation
    let angleY = (mouse.y - 0.5) * 1.5 + 0.3; // Slight elevation
    let cam_dist = mix(8.0, 15.0, u.zoom_params.x * 0.3);
    
    var ro = vec3<f32>(
        cam_dist * cos(angleY) * sin(angleX),
        cam_dist * sin(angleY),
        cam_dist * cos(angleY) * cos(angleX)
    );
    
    // Look-at target
    let target_pos = vec3<f32>(0.0, sin(time * 0.1) * 2.0, 0.0);
    let fwd = normalize(target_pos - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);
    
    // Raymarch
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;
    
    var color = vec3<f32>(0.0);
    var depth = MAX_DIST;
    var alpha = 1.0;
    // Rift glow luminance for this frame — feeds the temporal-echo memory below
    var riftGlowNow = 0.0;

    if (mat > 0.0 && t < MAX_DIST) {
        var p = ro + rd * t;
        depth = t;

        // ═══ CHUNK: early-exit (low-contribution pixels, AGENTS.md) ═══
        // Predict the atmospheric-perspective alpha BEFORE paying for calcNormal (6 map()
        // calls) + calcAO (5 map() calls) + the full lighting model. Once fog has nearly
        // swallowed a hit (alpha < 0.02), none of that 11-call investment is visible —
        // composite straight from the fog color instead.
        let atm_perspective = u.zoom_params.w * 0.08 + 0.005;
        let predictedAlpha = exp(-t * atm_perspective);

        if (predictedAlpha < 0.02) {
            color = mix(vec3<f32>(0.02, 0.02, 0.04), vec3<f32>(0.0, 0.0, 0.08), 0.5);
            alpha = predictedAlpha;
        } else {
        let n = calcNormal(p);

        // Materials
        var base_color: vec3<f32>;
        var roughness: f32;
        let material_blend = 0.5;

        if (mat < 1.5) {
            // Wall material - blend between stone and obsidian
            let stone_col = vec3<f32>(0.45, 0.42, 0.38); // Ancient stone
            let obsidian_col = vec3<f32>(0.08, 0.08, 0.12); // Polished obsidian
            base_color = mix(stone_col, obsidian_col, material_blend);

            // Add procedural texture variation
            let tex_noise = fract(sin(dot(p.xz, vec2<f32>(12.9898, 78.233))) * 43758.5453);
            base_color *= 0.9 + tex_noise * 0.2;

            roughness = mix(0.9, 0.1, material_blend); // Stone rough, obsidian smooth
        } else {
            // Temporal Rift - glowing energy
            base_color = vec3<f32>(0.0);
            roughness = 0.0;
        }

        // Lighting
        let light_dir = normalize(vec3<f32>(0.5, 0.8, -0.3));
        let diff = max(dot(n, light_dir), 0.0);

        // Ambient occlusion (provides contact-shadow feel without soft shadow ray cost)
        let ao = calcAO(p, n);

        // Specular for obsidian mode
        var spec = 0.0;
        if (mat < 1.5) {
            let refl = reflect(-light_dir, n);
            spec = pow(max(dot(refl, -rd), 0.0), 32.0) * material_blend;
        }

        // Fresnel rim lighting for neon effect
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let rim_col = mix(vec3<f32>(0.3, 0.25, 0.2), vec3<f32>(0.0, 0.8, 1.0), material_blend);

        if (mat > 1.5) {
            // Temporal Rift glow — mid energy swells rift brightness
            let rift_colors = vec3<f32>(0.4, 0.9, 1.0);
            let pulse = 0.7 + 0.3 * sin(time * 3.0);
            color = rift_colors * (2.0 + pulse + mid * 0.5) * u.zoom_params.z;
            riftGlowNow = dot(color, vec3<f32>(0.333));
        } else {
            // Standard material — ao folds in diffuse shadow role
            let amb = 0.15 * ao;
            color = base_color * (amb + diff * ao * 0.7) + rim_col * fresnel * (0.3 + material_blend);
            color += vec3<f32>(spec);
        }

        // Fog — bass thickens the atmosphere for punchier low-end response
        let fogDensity = 0.04 + bass * 0.015;
        let fog_amount = 1.0 - exp(-t * fogDensity);
        let fog_color = mix(vec3<f32>(0.02, 0.02, 0.04), vec3<f32>(0.0, 0.0, 0.08), material_blend);
        color = mix(color, fog_color, fog_amount);

        alpha = predictedAlpha;
        }

    } else {
        // Void background with subtle stars
        let star_hash = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time * 0.01) * 43758.5453);
        if (star_hash > 0.997) {
            color = vec3<f32>(0.6, 0.7, 1.0) * (0.5 + 0.5 * sin(time + star_hash * 10.0));
        } else {
            color = mix(vec3<f32>(0.01, 0.01, 0.02), vec3<f32>(0.0, 0.0, 0.05), 0.5);
        }
        alpha = 0.0;
    }
    
    // ═══ CHUNK: multi-pass state packing — temporal rift echo (AGENTS.md) ═══
    // Rifts are intermittent (rift_pulse gating in map()); without memory they simply
    // blink on/off. Reading last frame's glow from dataTextureC and slow-decaying it
    // (0.96/frame) creates a lingering "afterimage" — the anomaly bleeds through time
    // even after the geometry stops rendering it, which is exactly the shader's conceit.
    let uvSample = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let prevMemory = textureSampleLevel(dataTextureC, u_sampler, uvSample, 0.0);
    let riftEcho = max(riftGlowNow * 0.5, prevMemory.r * 0.96);
    let echoColor = vec3<f32>(0.4, 0.9, 1.0);
    color += echoColor * riftEcho * 0.12 * (1.0 - alpha * 0.5);

    // ═══ CHUNK: chromatic-aberration — mid-band energy splits the rift echo across RGB ═══
    let caStrength = (0.0015 + mid * 0.0025) * riftEcho;
    color = vec3<f32>(
        color.r + echoColor.r * riftEcho * caStrength * 40.0,
        color.g,
        color.b - echoColor.b * riftEcho * caStrength * 40.0
    );

    // Vignette
    let vignette = 1.0 - 0.4 * length(uv);
    color *= vignette;

    // Hue-preserving clamp keeps rift cyan saturated instead of blowing out to white
    color = huePreserveClamp(color, 2.4);

    // ACES filmic tone mapping (replaces Reinhard — more hue-neutral in highlights)
    color = acesToneMapping(color);

    // IGN dither before quantize — suppresses contouring in the deep shadow regions
    let ign = fract(52.9829189 * fract(dot(vec2<f32>(global_id.xy), vec2<f32>(0.06711056, 0.00583715))));
    color = clamp(color + (ign - 0.5) * (1.0 / 255.0), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth / MAX_DIST, 0.0, 0.0, 0.0));
    // Persist rift-echo memory (.r), normalized depth (.g), material id (.b), alpha (.a)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(riftEcho, depth / MAX_DIST, mat, alpha));
}
