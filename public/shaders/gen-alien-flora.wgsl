// ═══════════════════════════════════════════════════════════════
//  Alien Flora - Generative Shader with Organic Material Properties
//  Category: generative
//  Features: Subsurface scattering, bioluminescence, organic alpha
// ═══════════════════════════════════════════════════════════════

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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Density, y=SwaySpeed, z=GlowIntensity, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// Organic Material Properties
const TISSUE_DENSITY: f32 = 2.5;
const SCATTERING_COEFF: f32 = 1.8;
const ABSORPTION_BASE: f32 = 0.3;

// SDF Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Smooth Min for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 2D Rotation
fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Hash function for random values
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Calculate organic tissue thickness from SDF
fn calculateThickness(d: f32, normal: vec3<f32>, p: vec3<f32>) -> f32 {
    // Sample SDF slightly inside the surface
    let inner_d = map(p - normal * 0.1).x;
    // Thickness estimate based on surface gradient
    return max(0.05, min(1.0, abs(inner_d - d) * 5.0));
}

// Scene Map function
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Terrain
    let terrainHeight = sin(p.x * 0.2) * sin(p.z * 0.2) * 2.0 + sin(p.x * 0.5 + p.z * 0.3) * 0.5;
    let d_terrain = p.y - terrainHeight;

    // 2. Vegetation (Domain Repetition)
    let density = mix(16.0, 4.0, u.zoom_params.x);
    let cell_size = density;

    let id = floor(p.xz / cell_size);
    let q_xz = (fract(p.xz / cell_size) - 0.5) * cell_size;

    let rand = hash(id);

    let cell_center = (id + 0.5) * cell_size;
    let ground_y = sin(cell_center.x * 0.2) * sin(cell_center.y * 0.2) * 2.0 + sin(cell_center.x * 0.5 + cell_center.y * 0.3) * 0.5;

    var q = vec3<f32>(q_xz.x, p.y - ground_y, q_xz.y);

    // Swaying Motion
    var time = u.config.x;
    let swaySpeed = u.zoom_params.y;

    let swayAmount = 0.5 * (q.y * 0.1) * (q.y * 0.1);
    let sway = vec3<f32>(
        sin(time * swaySpeed + id.x) * swayAmount,
        0.0,
        cos(time * swaySpeed * 0.8 + id.y) * swayAmount
    );

    q.x -= sway.x;
    q.z -= sway.z;

    // Mushroom/Plant SDF
    let stemHeight = 2.0 + rand * 3.0;
    let stemRadius = 0.2 + rand * 0.1;
    let p_stem = q - vec3<f32>(0.0, stemHeight * 0.5, 0.0);
    let stem = sdCappedCylinder(p_stem, stemHeight * 0.5, stemRadius);

    let capRadius = 1.0 + rand * 1.5;
    let capHeight = 0.5 + rand * 0.5;
    let p_cap = q - vec3<f32>(0.0, stemHeight, 0.0);
    let d_cap_sphere = length(p_cap * vec3<f32>(1.0, 2.0, 1.0)) - capRadius;
    let d_cap_cut = max(d_cap_sphere, -p_cap.y);
    let cap = d_cap_cut;

    // Blend stem and cap
    let d_plant = smin(stem, cap, 0.3);

    var d = d_terrain;
    var mat = 1.0;

    if (d_plant < d) {
        d = d_plant;
        mat = 2.0;
    }

    return vec2<f32>(d, mat);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.1;
    var mat = 0.0;
    for(var i=0; i<128; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 100.0) { break; }
        t += d;
    }
    return vec2<f32>(t, mat);
}

// Subsurface scattering calculation for organic tissue
fn subsurfaceScattering(n: vec3<f32>, l: vec3<f32>, v: vec3<f32>, thickness: f32, baseColor: vec3<f32>) -> vec3<f32> {
    // Back-scattering (translucency)
    let backDot = max(0.0, dot(n, -l));
    let scattering = pow(backDot, 3.0) * SCATTERING_COEFF;
    
    // Beer-Lambert absorption
    let absorption = exp(-vec3<f32>(thickness * ABSORPTION_BASE * 0.8, 
                                     thickness * ABSORPTION_BASE * 1.2, 
                                     thickness * ABSORPTION_BASE * 1.5));
    
    return baseColor * scattering * absorption * 2.0;
}

// Calculate organic alpha based on tissue properties
fn calculateOrganicAlpha(mat: f32, thickness: f32, n: vec3<f32>, l: vec3<f32>) -> f32 {
    if (mat == 1.0) {
        // Terrain - mostly opaque with slight variation
        return 0.95;
    }
    
    // Plant tissue - variable translucency
    // Thicker tissue = more opaque
    let baseAlpha = min(0.95, 0.4 + thickness * TISSUE_DENSITY);
    
    // Backlit areas more translucent
    let backlitFactor = max(0.0, dot(n, -l));
    let translucency = backlitFactor * 0.35;
    
    return mix(baseAlpha, baseAlpha * 0.65, translucency);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Camera Setup
    var mouse = u.zoom_config.yz;
    var time = u.config.x * 0.1;
    let yaw = (mouse.x - 0.5) * 10.0 + time;
    let pitch = (mouse.y - 0.5) * 2.0 + 0.5;
    let dist = 10.0;

    let target_pos = vec3<f32>(0.0, 2.0, time * 10.0);

    let ro = vec3<f32>(
        target_pos.x + sin(yaw) * dist,
        target_pos.y + pitch * 5.0 + 2.0,
        target_pos.z + cos(yaw) * dist
    );

    let forward = normalize(target_pos - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarch
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;

    var color = vec3<f32>(0.0);
    var alpha = 1.0;
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));

    if (t < 100.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);
        
        // Calculate tissue thickness for subsurface effects
        let thickness = calculateThickness(res.x, n, p);

        let diff = max(dot(n, lightDir), 0.0);

        // Color Palette
        var baseColor = vec3<f32>(0.1, 0.3, 0.1);

        if (mat == 2.0) {
            // Plant bioluminescent colors
            let shift = u.zoom_params.w;
            let hue = fract(p.x * 0.1 + p.z * 0.1 + shift);

            let k = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
            let p_col = abs(fract(vec3<f32>(hue) + k) * 6.0 - 3.0);
            let hueColor = clamp(p_col - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));

            baseColor = mix(vec3<f32>(0.2, 0.8, 0.9), hueColor, 0.5);

            // Glow intensity affects emission, not alpha directly
            let glow = u.zoom_params.z;
            baseColor = baseColor * glow;
        }

        // Apply subsurface scattering for organic materials
        if (mat == 2.0) {
            let sss = subsurfaceScattering(n, lightDir, -rd, thickness, baseColor);
            baseColor += sss;
        }

        // Shading
        let ambient = vec3<f32>(0.05, 0.1, 0.1);
        color = baseColor * (diff * 0.5 + 0.5);

        // Rim light for atmosphere
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        color += vec3<f32>(0.5, 0.8, 1.0) * rim * 0.5;

        // Distance Fog
        let fogAmount = 1.0 - exp(-t * 0.05);
        color = mix(color, fogColor, fogAmount);
        
        // Calculate organic alpha
        alpha = calculateOrganicAlpha(mat, thickness, n, lightDir);
        
        // Bioluminescent areas have slightly lower alpha for glow effect
        if (mat == 2.0 && u.zoom_params.z > 0.7) {
            alpha = mix(alpha, 0.75, 0.3);
        }

    } else {
        color = fogColor;
        color = mix(fogColor, vec3<f32>(0.0, 0.0, 0.05), rd.y * 0.5 + 0.5);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
