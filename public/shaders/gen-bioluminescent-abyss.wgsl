// ═══════════════════════════════════════════════════════════════
//  Bioluminescent Abyss - Generative Shader with Deep Sea Organism Properties
//  Category: generative
//  Features: Tube worm tissue, bioluminescent emission, organic transparency
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
    zoom_params: vec4<f32>,  // x=Density, y=Current/Sway, z=GlowIntensity, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// Deep Sea Organism Properties
const WORM_TISSUE_DENSITY: f32 = 3.2;      // Tube worms are relatively dense
const WORM_SCATTERING: f32 = 1.5;          // Moderate scattering
const VENT_MINERAL_DENSITY: f32 = 8.0;     // Mineral deposits are opaque
const GLOW_TRANSPARENCY: f32 = 0.65;       // Bioluminescent areas are translucent

// --- Noise Functions ---

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)),
                   hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)),
                   hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pos = p;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// --- SDF Primitives ---

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdCappedCone(p: vec3<f32>, h: f32, r1: f32, r2: f32) -> f32 {
    var q = vec2<f32>(length(p.xz), p.y);
    let k1 = vec2<f32>(r2, h);
    let k2 = vec2<f32>(r2 - r1, 2.0 * h);
    let ca = vec2<f32>(q.x - min(q.x, select(r2, r1, q.y < 0.0)), abs(q.y) - h);
    let cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    let s = select(1.0, -1.0, cb.x < 0.0 && ca.y < 0.0);
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    var h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Calculate tube worm tissue thickness
fn calculateWormThickness(p: vec3<f32>, n: vec3<f32>, radius: f32, relHeight: f32) -> f32 {
    // Tube worms have thicker walls at base, thinner at glowing tips
    let baseThickness = radius * 0.4;  // Wall is 40% of radius at base
    let tipThickness = radius * 0.15;  // 15% at tip
    return mix(baseThickness, tipThickness, relHeight);
}

// Subsurface scattering for marine organisms
fn marineOrganismSSS(n: vec3<f32>, l: vec3<f32>, thickness: f32, 
                     baseColor: vec3<f32>, isGlowing: bool) -> vec3<f32> {
    // Marine organisms often show rim scattering
    let rimDot = 1.0 - max(0.0, dot(n, -l));
    let rimScatter = pow(rimDot, 3.0) * WORM_SCATTERING;
    
    // Absorption through tissue
    let absorption = exp(-thickness * 1.5);
    
    // Glowing tips have internal scattering
    var internalGlow = vec3<f32>(0.0);
    if (isGlowing {
        internalGlow = baseColor * absorption * 0.5;
    }
    
    return baseColor * rimScatter * absorption + internalGlow;
}

// Calculate alpha for deep sea organisms
fn calculateMarineAlpha(mat: f32, thickness: f32, n: vec3<f32>, l: vec3<f32>, 
                        isGlowing: bool, glowIntensity: f32) -> f32 {
    var alpha = 1.0;
    
    if (mat == 2.0) {  // Worm body
        // Tube worm tissue absorption
        let absorption = exp(-thickness * WORM_TISSUE_DENSITY);
        alpha = 0.35 + absorption * 0.6;
        
        // Backlit rim glow reduces alpha
        let rimLight = pow(1.0 - max(0.0, dot(n, l)), 2.0);
        alpha = mix(alpha, alpha * 0.8, rimLight * 0.5);
        
    } else if (mat == 3.0) {  // Glowing tip
        // Bioluminescent emission creates transparency
        let baseAlpha = GLOW_TRANSPARENCY;
        alpha = mix(baseAlpha, 0.5, glowIntensity * 0.4);
        
    } else if (mat == 4.0) {  // Vent body
        // Mineral deposits are nearly opaque
        alpha = 0.92;
        
    } else {  // Floor
        alpha = 0.95;
    }
    
    return clamp(alpha, 0.3, 0.98);
}

// --- Map Function ---

fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Terrain
    let d_floor = p.y + 4.0 + fbm(p.xz * 0.2) * 2.0;

    // 2. Tube Worms (Domain Repetition)
    let density = mix(10.0, 4.0, u.zoom_params.x);
    let cell_size = density;

    let id = floor(p.xz / cell_size);
    let q_xz = (fract(p.xz / cell_size) - 0.5) * cell_size;

    var h = hash(id);

    let cell_center = (id + 0.5) * cell_size;
    let ground_y = -4.0 - fbm(cell_center * 0.2) * 2.0;

    var q = vec3<f32>(q_xz.x, p.y - ground_y, q_xz.y);

    // Swaying Logic
    var time = u.config.x;
    let current_strength = u.zoom_params.y;
    let sway_amount = (q.y * 0.15) * current_strength;
    let sway = vec3<f32>(
        sin(time * 0.5 + h * 10.0) * sway_amount,
        0.0,
        cos(time * 0.3 + h * 10.0) * sway_amount
    );
    q.x -= sway.x;
    q.z -= sway.z;

    // Tube Worm geometry
    let worm_height = 2.0 + h * 3.0;
    let worm_radius = 0.15 + h * 0.1;
    let p_worm = q - vec3<f32>(0.0, worm_height * 0.5, 0.0);
    let d_worm = sdCappedCylinder(p_worm, worm_height * 0.5, worm_radius);

    // 3. Thermal Vents (sparser)
    let vent_cell_size = 30.0;
    let vent_id = floor(p.xz / vent_cell_size);
    let vent_q_xz = (fract(p.xz / vent_cell_size) - 0.5) * vent_cell_size;
    let vent_h = hash(vent_id + vec2<f32>(12.34, 56.78));

    var d_vent = 1000.0;

    if (vent_h > 0.7) {
        let vent_center = (vent_id + 0.5) * vent_cell_size;
        let vent_ground_y = -4.0 - fbm(vent_center * 0.2) * 2.0;
        let q_vent = vec3<f32>(vent_q_xz.x, p.y - vent_ground_y, vent_q_xz.y);

        let vent_height = 3.0 + vent_h * 2.0;
        let vent_r1 = 1.5;
        let vent_r2 = 0.5;
        let p_vent = q_vent - vec3<f32>(0.0, vent_height * 0.5, 0.0);
        d_vent = sdCappedCone(p_vent, vent_height * 0.5, vent_r1, vent_r2);
    }

    // Material logic
    var d = d_floor;
    var mat = 1.0;

    if (d_worm < d) {
        d = d_worm;
        mat = 2.0;
        let rel_h = q.y;
        if (rel_h > worm_height - 0.5) {
            mat = 3.0;
        }
    }

    if (d_vent < d) {
        d = d_vent;
        mat = 4.0;
    }

    return vec2<f32>(d, mat);
}

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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Camera
    var mouse = u.zoom_config.yz;
    var time = u.config.x * 0.1;

    let yaw = (mouse.x - 0.5) * 10.0 + time * 0.5;
    let pitch = (mouse.y - 0.5) * 2.0;
    let dist = 10.0;

    let target_pos = vec3<f32>(0.0, -2.0, time * 5.0);

    let ro = vec3<f32>(
        target_pos.x + sin(yaw) * dist,
        target_pos.y + pitch * 5.0 + 5.0,
        target_pos.z + cos(yaw) * dist
    );

    let forward = normalize(target_pos - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    let rd = normalize(forward + right * uv.x + up * uv.y);

    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;

    var color = vec3<f32>(0.0);
    var alpha = 1.0;
    let fogColor = vec3<f32>(0.0, 0.02, 0.05);
    let lightDir = normalize(vec3<f32>(0.2, 1.0, 0.2));

    if (t < 100.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        let diff = max(dot(n, lightDir), 0.0);

        // Caustics projection
        let caustic_time = u.config.x * 2.0;
        let caustic_noise = noise(p.xz * 0.5 + caustic_time * 0.1);
        let caustic = smoothstep(0.4, 0.8, caustic_noise) * 0.5;

        var baseColor = vec3<f32>(0.05, 0.05, 0.07);
        var thickness = 0.2;
        var isGlowing = false;
        var glowIntensity = 0.0;

        if (mat == 2.0) { // Worm Body
            baseColor = vec3<f32>(0.1, 0.05, 0.05);
            thickness = 0.12;
            
            // Add marine organism SSS
            let sss = marineOrganismSSS(n, lightDir, thickness, baseColor, false);
            baseColor += sss * 0.3;
            
        } else if (mat == 3.0) { // Worm Tip
            isGlowing = true;
            glowIntensity = u.zoom_params.z;
            let color_shift = u.zoom_params.w;

            let hue = color_shift + p.y * 0.1;
            let k = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
            let p_col = abs(fract(vec3<f32>(hue) + k) * 6.0 - 3.0);
            let glowColor = clamp(p_col - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));

            baseColor = glowColor * 2.0 * glowIntensity;
            baseColor *= (0.8 + 0.2 * sin(u.config.x * 2.0));
            thickness = 0.05; // Very thin at glowing tip
            
        } else if (mat == 4.0) { // Vent Body
            baseColor = vec3<f32>(0.02, 0.02, 0.02);
        }

        // Apply lighting
        var lighting = baseColor * (diff * 0.5 + 0.5);

        // Add Caustics to non-emissive parts
        if (mat != 3.0) {
            lighting += vec3<f32>(0.1, 0.2, 0.3) * caustic * diff;
        } else {
            lighting = baseColor;
        }

        color = lighting;

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.03);
        color = mix(color, fogColor, fogAmount);
        
        // Calculate marine organism alpha
        alpha = calculateMarineAlpha(mat, thickness, n, lightDir, isGlowing, glowIntensity);

    } else {
        color = fogColor;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
