// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=StepSize, y=Speed, z=Specular, w=Iridescence
    ripples: array<vec4<f32>, 50>,
};

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Palette function for iridescent metallic colors
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// 3D Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Smooth minimum for blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// Hash function for pseudo-randomness
fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// --- Map Function ---
// Returns vec2: x = distance, y = material ID
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    var time = u.config.x;
    
    // Global twist/rotation around Y axis based on height
    let twist = p.y * 0.05;
    let p_xz = rot(twist) * p.xz;
    p.x = p_xz.x;
    p.z = p_xz.y;
    
    // Infinite vertical repetition (canyon segments)
    let spacingY = 4.0;
    p.y = fract(p.y / spacingY + 0.5) * spacingY - spacingY * 0.5;
    
    // Polar repetition for citadel structure (6 segments)
    let angle = atan2(p.z, p.x);
    let radius = length(p.xz);
    let segments = 6.0;
    let segmentAngle = 6.28318 / segments;
    let a = angle + 3.14159;
    let a_mod = fract(a / segmentAngle) * segmentAngle - segmentAngle * 0.5;
    
    p.x = radius * cos(a_mod);
    p.z = radius * sin(a_mod);
    
    // Bismuth stepping logic - terrace cuts
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    var pStep = p;
    pStep.x = floor(pStep.x / stepSize) * stepSize + stepSize * 0.5;
    pStep.z = floor(pStep.z / stepSize) * stepSize + stepSize * 0.5;
    pStep.y = floor(pStep.y / stepSize) * stepSize + stepSize * 0.5;
    
    // Base geometry - offset from center to create canyon walls
    let basePos = vec3<f32>(2.0, 0.0, 0.0);
    let d1 = sdBox(p - basePos, vec3<f32>(1.0, 1.5, 1.0));
    
    // Inner hollow for "hopper" crystal effect
    let innerSize = vec3<f32>(0.8, 1.6, 0.8);
    let inner_hollow = sdBox(p - basePos, innerSize);
    
    // Terraced geometry
    let terraceSize = stepSize * 0.45;
    let d2 = sdBox(p - pStep, vec3<f32>(terraceSize));
    
    // Combine: outer shell minus hollow center, intersected with terraces
    var d = max(d1, -inner_hollow);
    d = smin(d, d2 - 0.05, 0.1);
    
    // Add some smaller crystal formations
    let crystalPos = vec3<f32>(
        1.5 + sin(time * 0.5 + p.y) * 0.2,
        0.0,
        0.0
    );
    let d3 = sdBox(p - crystalPos, vec3<f32>(0.3, 0.8, 0.3));
    d = smin(d, d3, 0.2);
    
    return vec2<f32>(d, 1.0); // ID 1.0 for bismuth crystal
}

// --- Normal Calculation ---
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }
    
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    
    // Camera setup - moving upward through the crystal citadel
    var time = u.config.x * u.zoom_params.y;
    var ro = vec3<f32>(0.0, time * 2.0, -5.0);
    
    // Mouse interaction for camera orbit
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;
    
    // Apply mouse rotation
    let rotY = rot(mouseX * 3.14 + time * 0.2);
    let rotX = rot(mouseY * 1.0 + 0.2);
    
    var rd = normalize(vec3<f32>(uv, 1.0));
    
    // Apply rotations to ray direction
    rd.yz = rotX * rd.yz;
    rd.xz = rotY * rd.xz;
    
    // Camera look-at setup
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
        t += d * 0.8; // Slightly relaxed step for complex geometry
    }
    
    // Background - dark metallic canyon atmosphere
    var col = vec3<f32>(0.02, 0.02, 0.03);
    col += vec3<f32>(0.05, 0.08, 0.12) * max(0.0, rd.y); // Subtle gradient
    
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
        
        // Primary directional light
        let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let l_mouse = normalize(mouseLightPos - p);
        
        // Diffuse lighting
        let dif = max(dot(n, lig), 0.0);
        let dif_mouse = max(dot(n, l_mouse), 0.0);
        
        // Specular
        let hal = normalize(lig - rd);
        let spec = pow(max(dot(n, hal), 0.0), 32.0);
        
        // Fresnel for iridescence base
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);
        
        // Iridescent thin-film interference
        let interferenceOffset = p.y * 0.1 + p.x * 0.05 + time * 0.1;
        let iriPhase = fresnel * u.zoom_params.w + interferenceOffset;
        
        // Bismuth color palette: magenta, gold, cyan, blue
        let c_a = vec3<f32>(0.5, 0.5, 0.5);
        let c_b = vec3<f32>(0.5, 0.5, 0.5);
        let c_c = vec3<f32>(1.0, 1.0, 0.8);
        let c_d = vec3<f32>(0.0, 0.33, 0.67);
        
        let iridColor = palette(iriPhase, c_a, c_b, c_c, c_d);
        
        // Base bismuth material color (dark metallic)
        let baseColor = vec3<f32>(0.08, 0.08, 0.1);
        
        // Combine lighting
        var litColor = baseColor * (dif * 0.7 + dif_mouse * 0.5 + 0.2);
        litColor += iridColor * fresnel * 0.8;
        litColor += vec3<f32>(1.0) * spec * u.zoom_params.z;
        
        // Add edge highlights on terraces
        let terracePattern = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0);
        litColor += vec3<f32>(0.3, 0.5, 0.6) * max(0.0, terracePattern) * fresnel * 0.5;
        
        col = litColor;
        
        // Ambient occlusion approximation
        let ao = 1.0 - f32(100) / f32(maxSteps);
        col *= mix(0.5, 1.0, ao);
        
        // Distance fog for depth
        col = mix(col, vec3<f32>(0.02, 0.02, 0.03), 1.0 - exp(-0.015 * t));
    }
    
    // Vignette
    col *= 1.0 - 0.3 * length(uv);
    
    // Tone mapping
    col = col / (col + vec3<f32>(1.0));
    
    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));
    
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
