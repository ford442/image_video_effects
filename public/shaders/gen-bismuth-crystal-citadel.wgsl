// ═══════════════════════════════════════════════════════════════
//  Gen Bismuth Crystal Citadel - Physical Light Transmission
//  Category: generative
//  Features: raymarch, bismuth crystals, thin-film interference
//  Endless canyon with metallic transmission
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const IOR_BISMUTH: f32 = 1.8;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    var time = u.config.x;
    
    let twist = p.y * 0.05;
    let p_xz = rot(twist) * p.xz;
    p.x = p_xz.x;
    p.z = p_xz.y;
    
    let spacingY = 4.0;
    p.y = fract(p.y / spacingY + 0.5) * spacingY - spacingY * 0.5;
    
    let angle = atan2(p.z, p.x);
    let radius = length(p.xz);
    let segments = 6.0;
    let segmentAngle = 6.28318 / segments;
    let a = angle + 3.14159;
    let a_mod = fract(a / segmentAngle) * segmentAngle - segmentAngle * 0.5;
    
    p.x = radius * cos(a_mod);
    p.z = radius * sin(a_mod);
    
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    var pStep = p;
    pStep.x = floor(pStep.x / stepSize) * stepSize + stepSize * 0.5;
    pStep.z = floor(pStep.z / stepSize) * stepSize + stepSize * 0.5;
    pStep.y = floor(pStep.y / stepSize) * stepSize + stepSize * 0.5;
    
    let basePos = vec3<f32>(2.0, 0.0, 0.0);
    let d1 = sdBox(p - basePos, vec3<f32>(1.0, 1.5, 1.0));
    
    let innerSize = vec3<f32>(0.8, 1.6, 0.8);
    let inner_hollow = sdBox(p - basePos, innerSize);
    
    let terraceSize = stepSize * 0.45;
    let d2 = sdBox(p - pStep, vec3<f32>(terraceSize));
    
    var d = max(d1, -inner_hollow);
    d = smin(d, d2 - 0.05, 0.1);
    
    let crystalPos = vec3<f32>(
        1.5 + sin(u.config.x * 0.5 + p.y) * 0.2,
        0.0,
        0.0
    );
    let d3 = sdBox(p - crystalPos, vec3<f32>(0.3, 0.8, 0.3));
    d = smin(d, d3, 0.2);
    
    return vec2<f32>(d, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Fresnel for metals
fn fresnelMetal(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }
    
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    
    // Parameters
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    let speed = u.zoom_params.y;
    let metallic = u.zoom_params.z;
    let iridescence = u.zoom_params.w;
    let oxidePurity = 0.7 + u.zoom_params.x * 0.3;
    
    // Camera setup
    var time = u.config.x * speed;
    var ro = vec3<f32>(0.0, time * 2.0, -5.0);
    
    // Mouse interaction
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;
    
    let rotY = rot(mouseX * 3.14 + time * 0.2);
    let rotX = rot(mouseY * 1.0 + 0.2);
    
    var rd = normalize(vec3<f32>(uv, 1.0));
    
    rd.yz = rotX * rd.yz;
    rd.xz = rotY * rd.xz;
    
    let ta = vec3<f32>(0.0, time * 2.0 + 2.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);
    
    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    let maxSteps = 100;
    let maxDist = 50.0;
    
    for (var i = 0; i < maxSteps; i++) {
        var p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (d < 0.001 || t > maxDist) { break; }
        t += d * 0.8;
    }
    
    // Background
    var col = vec3<f32>(0.02, 0.02, 0.03);
    col += vec3<f32>(0.05, 0.08, 0.12) * max(0.0, rd.y);
    
    var alpha = 1.0; // Full opacity for background
    
    if (t < maxDist) {
        var p = ro + rd * t;
        let n = calcNormal(p);
        let v = normalize(ro - p);
        
        // Mouse-controlled secondary light
        let mouseLightPos = vec3<f32>(
            (u.zoom_config.y / dims.x - 0.5) * 10.0,
            ro.y + 2.0,
            (u.zoom_config.z / dims.y - 0.5) * 10.0 + 3.0
        );
        
        let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let l_mouse = normalize(mouseLightPos - p);
        
        let dif = max(dot(n, lig), 0.0);
        let dif_mouse = max(dot(n, l_mouse), 0.0);
        
        let hal = normalize(lig - rd);
        let spec = pow(max(dot(n, hal), 0.0), 32.0);
        
        // Fresnel for iridescence base
        let ndotv = max(dot(n, v), 0.0);
        let fresnel = pow(1.0 - ndotv, 5.0);
        
        // Thin-film interference
        let interferenceOffset = p.y * 0.1 + p.x * 0.05 + u.config.x * 0.1;
        let iriPhase = fresnel * iridescence + interferenceOffset;
        
        // Bismuth color palette
        let c_a = vec3<f32>(0.5, 0.5, 0.5);
        let c_b = vec3<f32>(0.5, 0.5, 0.5);
        let c_c = vec3<f32>(1.0, 1.0, 0.8);
        let c_d = vec3<f32>(0.0, 0.33, 0.67);
        
        let iridColor = palette(iriPhase, c_a, c_b, c_c, c_d);
        
        // Base bismuth material
        let baseColor = vec3<f32>(0.08, 0.08, 0.1);
        
        // Metallic Fresnel
        let F0_bismuth = vec3<f32>(0.75, 0.8, 0.85);
        let metalFresnel = fresnelMetal(ndotv, F0_bismuth * metallic);
        
        // Combine lighting
        var litColor = baseColor * (dif * 0.7 + dif_mouse * 0.5 + 0.2);
        litColor += iridColor * fresnel * 0.8 * oxidePurity;
        litColor += vec3<f32>(1.0) * spec * metallic;
        
        // Terrace pattern edge highlights
        let terracePattern = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0);
        litColor += vec3<f32>(0.3, 0.5, 0.6) * max(0.0, terracePattern) * fresnel * 0.5;
        
        col = litColor;
        
        // Ambient occlusion
        let ao = 1.0 - f32(100) / f32(maxSteps);
        col *= mix(0.5, 1.0, ao);
        
        // Distance fog
        col = mix(col, vec3<f32>(0.02, 0.02, 0.03), 1.0 - exp(-0.015 * t));
        
        // ═══════════════════════════════════════════════════════════════
        // Metallic Transmission Alpha
        // ═══════════════════════════════════════════════════════════════
        
        // Bismuth metal is mostly reflective, but thin oxide layers transmit slightly
        let oxideTransmission = (1.0 - metallic * 0.8) * oxidePurity;
        let transmission = oxideTransmission * (1.0 - fresnel * 0.5);
        alpha = mix(0.3, 1.0, metallic * 0.7 + fresnel * 0.3);
    } else {
        // Background is semi-transparent for layering
        alpha = 0.9;
    }
    
    // Vignette
    col *= 1.0 - 0.3 * length(uv);
    
    // Tone mapping
    col = col / (col + vec3<f32>(1.0));
    
    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));
    
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / maxDist, 0.0, 0.0, 0.0));
}
