// ═══════════════════════════════════════════════════════════════
//  Biomechanical Hive - Generative Shader with Chitinous Tissue Properties
//  Category: generative
//  Features: Chitinous shell, organic transparency, core bioluminescence
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
    zoom_params: vec4<f32>,  // x=Density, y=PulseSpeed, z=Biomass, w=HueShift
    ripples: array<vec4<f32>, 50>,
};

// Biomechanical Material Properties
const CHITIN_DENSITY: f32 = 4.5;          // Chitinous shell is fairly opaque
const CHITIN_TRANSPARENCY: f32 = 0.75;    // Semi-transparent like insect wings
const CORE_EMISSION_ALPHA: f32 = 0.55;    // Glowing core is more transparent
const MEMBRANE_THINNESS: f32 = 0.15;      // Thin membrane areas

fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn hash(p: vec3<f32>) -> f32 {
    let p3 = fract(p * 0.1031);
    let d = dot(p3, vec3<f32>(p3.y + 19.19, p3.z + 19.19, p3.x + 19.19));
    return fract((p3.x + p3.y) * p3.z + d);
}

fn noise(p: vec3<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(hash(i + vec3<f32>(0.0, 0.0, 0.0)), hash(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0, 1.0, 0.0)), hash(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(hash(i + vec3<f32>(0.0, 0.0, 1.0)), hash(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(hash(i + vec3<f32>(0.0, 1.0, 1.0)), hash(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        val += amp * noise(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return val;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735027);
    let p_abs = abs(p);
    let dot_k_p = dot(k.xy, p_abs.xy);
    let offset = 2.0 * min(dot_k_p, 0.0);
    var p_xy = p_abs.xy - vec2<f32>(offset * k.x, offset * k.y);

    let d = vec2<f32>(
       length(p_xy - vec2<f32>(clamp(p_xy.x, -k.z*h.x, k.z*h.x), h.x)) * sign(p_xy.y - h.x),
       p_abs.z - h.y
    );
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Calculate chitinous shell thickness
fn calculateChitinThickness(p: vec3<f32>, localP: vec3<f32>, cellSize: f32) -> f32 {
    // Ribbed structure creates varying thickness
    let rib_freq = 10.0;
    let rib_pattern = sin(localP.z * rib_freq) * 0.5 + 0.5;
    
    // Base thickness varies with ribs
    let baseThickness = mix(MEMBRANE_THINNESS, MEMBRANE_THINNESS * 2.5, rib_pattern);
    
    // Add organic variation
    let noiseThickness = fbm(p * 3.0) * 0.05;
    
    return baseThickness + noiseThickness;
}

// Chitinous subsurface scattering (similar to insect wings/exoskeletons)
fn chitinSSS(n: vec3<f32>, l: vec3<f32>, v: vec3<f32>, thickness: f32, 
             baseColor: vec3<f32>, isCore: bool) -> vec3<f32> {
    // Chitin has characteristic oily/iridescent scattering
    let rimDot = 1.0 - max(0.0, dot(n, v));
    let rimScatter = pow(rimDot, 3.0) * 1.5;
    
    // Thin film interference approximation
    let interference = sin(thickness * 50.0) * 0.5 + 0.5;
    let iridescence = vec3<f32>(
        interference * 0.3,
        interference * 0.5,
        interference * 0.7
    );
    
    var scatter = baseColor * (rimScatter + iridescence * 0.3);
    
    // Core has internal glow
    if (isCore) {
        scatter += baseColor * 0.8 * (1.0 - thickness * 2.0);
    }
    
    return scatter;
}

// Calculate alpha for biomechanical materials
fn calculateBiomechAlpha(mat: f32, thickness: f32, pulse: f32, isNearCore: bool) -> f32 {
    var alpha = 1.0;
    
    if (mat == 1.0) {  // Chitinous walls
        // Thinner areas more transparent (like insect wing membranes)
        let membraneAlpha = mix(CHITIN_TRANSPARENCY, 0.9, thickness * 4.0);
        
        // Pulse affects transparency (breathing effect)
        let breathing = sin(pulse * 3.14159) * 0.1 + 0.9;
        alpha = membraneAlpha * breathing;
        
    } else if (mat == 2.0) {  // Bioluminescent core
        // Core is semi-transparent with emission
        let baseCoreAlpha = CORE_EMISSION_ALPHA;
        // Pulse makes core flash and become more transparent
        let pulseAlpha = mix(baseCoreAlpha, 0.4, pulse * 0.5);
        alpha = pulseAlpha;
    }
    
    return clamp(alpha, 0.35, 0.95);
}

// Scene Map
fn map(p: vec3<f32>) -> vec2<f32> {
    let density = mix(4.0, 10.0, u.zoom_params.x);
    let pulseSpeed = u.zoom_params.y;
    let biomass = u.zoom_params.z;

    let cell_size = 12.0 / density;
    let q = p;

    let spacing = vec3<f32>(cell_size * 2.0, cell_size * 2.0, cell_size * 4.0);
    let id = floor((p + spacing * 0.5) / spacing);
    let local_p = (fract((p + spacing * 0.5) / spacing) - 0.5) * spacing;

    let hex_h = vec2<f32>(cell_size * 0.8, cell_size * 1.8);
    let d_hex = sdHexPrism(local_p, hex_h * 0.9);
    let d_base = -d_hex;

    // Ribs/Pipes
    let rib_freq = 10.0;
    let rib_amp = 0.05;
    let ribs = sin(local_p.z * rib_freq) * rib_amp;

    // Organic Displacement
    var time = u.config.x * pulseSpeed;
    var pulse = sin(time * 2.0) * 0.5 + 0.5;
    let noise_val = fbm(p * 2.0 + vec3<f32>(0.0, 0.0, time * 0.2));
    let displacement = noise_val * biomass * 0.5;

    let breathing = sin(time + p.z) * 0.05;

    let d_organic = d_base + ribs + displacement + breathing;

    // Core sphere
    let d_sphere_core = length(local_p) - cell_size * 0.2;

    // Combine walls and core
    let d_final = min(d_organic, d_sphere_core);

    var mat = 1.0;
    if (d_sphere_core < d_organic) {
         mat = 2.0;
    }

    return vec2<f32>(d_final, mat);
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
    var t = 0.0;
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
    var time = u.config.x;

    let yaw = (mouse.x - 0.5) * 6.28;
    let pitch = (mouse.y - 0.5) * 3.14;

    let cam_pos = vec3<f32>(0.0, 0.0, time * 2.0);
    let ro = cam_pos;

    let forward = normalize(vec3<f32>(sin(yaw), sin(pitch), cos(yaw)));
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarch
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;

    var color = vec3<f32>(0.0);
    var alpha = 1.0;
    let fogColor = vec3<f32>(0.01, 0.01, 0.02);

    if (t < 100.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));

        var pulse = sin(u.config.x * u.zoom_params.y * 5.0) * 0.5 + 0.5;

        var baseColor = vec3<f32>(0.1, 0.1, 0.15);
        var thickness = 0.2;
        var isCore = false;
        
        // Calculate cell-local position for thickness
        let cell_size = 12.0 / mix(4.0, 10.0, u.zoom_params.x);
        let spacing = vec3<f32>(cell_size * 2.0, cell_size * 2.0, cell_size * 4.0);
        let local_p = (fract((p + spacing * 0.5) / spacing) - 0.5) * spacing;
        
        if (mat == 2.0) {
            isCore = true;
            let hueShift = u.zoom_params.w;
            let hue = 0.1 + hueShift;

            let coreColor1 = vec3<f32>(1.0, 0.6, 0.1);
            let coreColor2 = vec3<f32>(0.1, 1.0, 0.2);
            let coreColor3 = vec3<f32>(1.0, 0.1, 0.2);

            var mixColor = coreColor1;
            if (hueShift > 0.3) { mixColor = mix(coreColor1, coreColor2, (hueShift - 0.3) * 3.0); }
            if (hueShift > 0.6) { mixColor = mix(coreColor2, coreColor3, (hueShift - 0.6) * 3.0); }

            baseColor = mixColor * (1.0 + pulse);
            baseColor += fbm(p * 5.0) * 0.2;
            thickness = 0.1; // Core is less dense
        } else {
            // Wall - calculate chitinous thickness
            thickness = calculateChitinThickness(p, local_p, cell_size);
            
            // Shiny, slimy
            let ref = reflect(-rd, n);
            let spec = pow(max(dot(ref, lightDir), 0.0), 16.0);
            baseColor += vec3<f32>(1.0) * spec * 0.5;

            // Rim
            let rim = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
            baseColor += vec3<f32>(0.2, 0.3, 0.4) * rim;
            
            // Apply chitinous SSS
            let sss = chitinSSS(n, lightDir, -rd, thickness, baseColor, false);
            baseColor += sss * 0.4;
        }

        // Diffuse
        let diff = max(dot(n, lightDir), 0.0);
        color = baseColor * (diff * 0.8 + 0.2);

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.05);
        color = mix(color, fogColor, fogAmount);
        
        // Calculate biomechanical alpha
        let isNearCore = length(local_p) < cell_size * 0.4;
        alpha = calculateBiomechAlpha(mat, thickness, pulse, isNearCore);

    } else {
        color = fogColor;
    }

    // Output with alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
