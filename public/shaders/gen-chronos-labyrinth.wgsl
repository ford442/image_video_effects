// ═══════════════════════════════════════════════════════════════
// Chronos Labyrinth - Escher-esque Shifting Maze
// Category: generative
// Features: raymarching, impossible geometry, temporal rifts, mouse-driven
// ═══════════════════════════════════════════════════════════════

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
    zoom_params: vec4<f32>, // x=Complexity, y=ShiftSpeed, z=TemporalRifts, w=Material
    ripples: array<vec4<f32>, 50>,
};

// Parameters
let complexity: f32 = u.zoom_params.x;      // Labyrinth density/scale
let shift_speed: f32 = u.zoom_params.y;     // Rotation/slide speed
let rift_intensity: f32 = u.zoom_params.z;  // Temporal rift frequency
let material: f32 = u.zoom_params.w;        // 0=Stone, 1=Obsidian/Neon

// Constants
let PI: f32 = 3.14159265359;
let MAX_STEPS: i32 = 128;
let MAX_DIST: f32 = 40.0;
let SURF_DIST: f32 = 0.001;

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
    
    // Base repetition size based on complexity
    let cell_size = mix(4.0, 1.5, complexity);
    
    // Get cell repetition
    let rep = opRepId(p, vec3<f32>(cell_size));
    var q = rep.xyz;
    let cell_id = rep.w;
    let cell_hash = hash1(cell_id);
    
    // Time-based shifting rotation for each cell
    let shift_time = time * shift_speed * (0.5 + cell_hash);
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

// Soft shadow calculation
fn calcSoftShadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, k: f32) -> f32 {
    var res = 1.0;
    var t = mint;
    for (var i = 0; i < 32; i++) {
        var h = map(ro + rd * t).x;
        if (h < 0.001) {
            return 0.0;
        }
        res = min(res, k * h / t);
        t += clamp(h, 0.02, 0.5);
        if (t > maxt) {
            break;
        }
    }
    return res;
}

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
        t += d * 0.8; // Slight under-step for better detail
    }
    
    return vec3<f32>(t, mat, 0.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    var time = u.config.x;
    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    
    // Camera setup with mouse orbit
    var mouse = u.zoom_config.yz;
    let angleX = (mouse.x - 0.5) * 6.2832 + time * 0.05; // Slow auto-rotation
    let angleY = (mouse.y - 0.5) * 1.5 + 0.3; // Slight elevation
    let cam_dist = mix(8.0, 15.0, complexity * 0.3);
    
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
    
    if (mat > 0.0 && t < MAX_DIST) {
        var p = ro + rd * t;
        let n = calcNormal(p);
        depth = t;
        
        // Materials
        var base_color: vec3<f32>;
        var roughness: f32;
        
        if (mat < 1.5) {
            // Wall material - blend between stone and obsidian
            let stone_col = vec3<f32>(0.45, 0.42, 0.38); // Ancient stone
            let obsidian_col = vec3<f32>(0.08, 0.08, 0.12); // Polished obsidian
            base_color = mix(stone_col, obsidian_col, material);
            
            // Add procedural texture variation
            let tex_noise = fract(sin(dot(p.xz, vec2<f32>(12.9898, 78.233))) * 43758.5453);
            base_color *= 0.9 + tex_noise * 0.2;
            
            roughness = mix(0.9, 0.1, material); // Stone rough, obsidian smooth
        } else {
            // Temporal Rift - glowing energy
            base_color = vec3<f32>(0.0);
            roughness = 0.0;
        }
        
        // Lighting
        let light_dir = normalize(vec3<f32>(0.5, 0.8, -0.3));
        let diff = max(dot(n, light_dir), 0.0);
        
        // Ambient occlusion
        let ao = calcAO(p, n);
        
        // Soft shadows
        let shadow = calcSoftShadow(p, light_dir, 0.02, 5.0, 8.0);
        
        // Specular for obsidian mode
        var spec = 0.0;
        if (material > 0.1 && mat < 1.5) {
            let ref = reflect(-light_dir, n);
            spec = pow(max(dot(ref, -rd), 0.0), 32.0) * material;
        }
        
        // Fresnel rim lighting for neon effect
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let rim_col = mix(vec3<f32>(0.3, 0.25, 0.2), vec3<f32>(0.0, 0.8, 1.0), material);
        
        if (mat > 1.5) {
            // Temporal Rift glow
            let rift_colors = vec3<f32>(0.4, 0.9, 1.0);
            let pulse = 0.7 + 0.3 * sin(time * 3.0);
            color = rift_colors * (2.0 + pulse) * rift_intensity;
        } else {
            // Standard material
            let amb = 0.15 * ao;
            color = base_color * (amb + diff * shadow * 0.7) + rim_col * fresnel * (0.3 + material);
            color += vec3<f32>(spec);
        }
        
        // Fog
        let fog_amount = 1.0 - exp(-t * 0.04);
        let fog_color = mix(vec3<f32>(0.02, 0.02, 0.04), vec3<f32>(0.0, 0.0, 0.08), material);
        color = mix(color, fog_color, fog_amount);
        
    } else {
        // Void background with subtle stars
        let star_hash = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time * 0.01) * 43758.5453);
        if (star_hash > 0.997) {
            color = vec3<f32>(0.6, 0.7, 1.0) * (0.5 + 0.5 * sin(time + star_hash * 10.0));
        } else {
            color = mix(vec3<f32>(0.01, 0.01, 0.02), vec3<f32>(0.0, 0.0, 0.05), material);
        }
    }
    
    // Vignette
    let vignette = 1.0 - 0.4 * length(uv);
    color *= vignette;
    
    // Tone mapping
    color = color / (1.0 + color);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth / MAX_DIST, 0.0, 0.0, 0.0));
}
