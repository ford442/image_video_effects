// ----------------------------------------------------------------
// Hyperdimensional Plasma Loom
// Category: generative
// ----------------------------------------------------------------
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Weave Density, .y = Thread Thickness, .z = Plasma Intensity, .w = Time Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Basic 3D rotation functions
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 4D Simplex-like noise based on IQ's implementation
fn hash41(p: vec4<f32>) -> f32 {
    var p4 = fract(p * vec4<f32>(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.x + p4.y) * p4.z + p4.w);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp(-k * a) + exp(-k * b);
    return -log(res) / k;
}

// Map function returning (distance, material_id)
fn map(p_in: vec3<f32>, time: f32, mouse_pos: vec2<f32>, m_down: f32, bass: f32) -> vec2<f32> {
    var p = p_in;

    // Mouse Interaction: Gravity well
    // Map mouse_uv [0, 1] to world-ish coords.
    // Screen is roughly [-ratio, ratio] in x, [-1, 1] in y at z=0.
    // Mouse UV y=0 is top.
    let aspect = u.config.z / u.config.w;
    var mx = (mouse_pos.x * 2.0 - 1.0) * aspect;
    var my = -(mouse_pos.y * 2.0 - 1.0); // flip y

    let m_world = vec3<f32>(mx, my, 0.0) * 3.0; // scale to match scene

    let to_mouse = m_world - p;
    let dist_to_mouse = length(to_mouse);

    // Apply distortion if close and mouse is pressed or always slightly
    let pull_str = mix(0.2, 1.5, m_down);
    let pull = pull_str / (1.0 + dist_to_mouse * dist_to_mouse);

    p = p + to_mouse * pull * 0.5;

    // Twist domain
    let t = time * u.zoom_params.w * 0.5;

    // Apply some 3D rotation
    p = rotY(t * 0.3) * p;
    p = rotZ(t * 0.2) * p;

    // Domain repetition for weaving
    let density = u.zoom_params.x * (1.0 + bass * 0.5); // Bass increases density
    let spacing = 2.0 / density;

    var q = p;

    // Twist
    let tw = rot2D(q.z * 0.5 + t);
    let qxy = tw * q.xy;
    q.x = qxy.x;
    q.y = qxy.y;

    // Spatial repetition
    var r = q;
    r.x = (fract(q.x / spacing + 0.5) - 0.5) * spacing;
    r.y = (fract(q.y / spacing + 0.5) - 0.5) * spacing;

    // Strands (helices)
    let thickness = u.zoom_params.y * (1.0 + bass * 1.5);

    // Strand 1
    var s1_p = r;
    let r1 = rot2D(s1_p.z * 2.0 + t * 2.0);
    let s1_xy = r1 * s1_p.xy;
    s1_p.x = s1_xy.x; s1_p.y = s1_xy.y;
    s1_p.x += spacing * 0.2;
    let d1 = length(s1_p.xy) - thickness;

    // Strand 2
    var s2_p = r;
    let r2 = rot2D(s2_p.z * 2.0 - t * 2.5 + PI);
    let s2_xy = r2 * s2_p.xy;
    s2_p.x = s2_xy.x; s2_p.y = s2_xy.y;
    s2_p.x += spacing * 0.2;
    let d2 = length(s2_p.xy) - thickness * 0.8;

    // Strand 3 (perpendicular-ish cross weave)
    var s3_p = q; // Use un-repeated space for cross weave? Or repeated?
    s3_p.z = (fract(q.z / spacing + 0.5) - 0.5) * spacing;
    let r3 = rot2D(s3_p.x * 2.0 + t);
    let s3_yz = r3 * s3_p.yz;
    s3_p.y = s3_yz.x; s3_p.z = s3_yz.y; // map 2d vec to yz
    let d3 = length(s3_p.yz) - thickness * 0.5;

    var d = smin(d1, d2, 8.0);
    // Combine with cross weave if we want
    d = smin(d, d3 + 0.5, 4.0); // push it out a bit

    // Add noise bump
    let n = sin(p.x * 4.0 + t) * sin(p.y * 4.0 + t) * sin(p.z * 4.0 + t);
    d += n * 0.05;

    var mat = 0.0;
    if (d1 < d2) { mat = 1.0; }
    if (d3 < d) { mat = 2.0; }

    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>, time: f32, mouse_pos: vec2<f32>, m_down: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, mouse_pos, m_down, bass).x;
    let nx = map(p + e.xyy, time, mouse_pos, m_down, bass).x - d;
    let ny = map(p + e.yxy, time, mouse_pos, m_down, bass).x - d;
    let nz = map(p + e.yyx, time, mouse_pos, m_down, bass).x - d;
    return normalize(vec3<f32>(nx, ny, nz));
}

// Iridescent palette
fn iridescence(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= dims.x || coords.y >= dims.y) {
        return;
    }

    let aspect = f32(dims.x) / f32(dims.y);
    var uv = vec2<f32>(coords) / vec2<f32>(dims);
    let base_uv = uv; // Keep for reading previous frame
    uv = uv * 2.0 - 1.0;
    uv.y = -uv.y;
    uv.x *= aspect;

    let time = u.config.x;
    let mouse_pos = u.zoom_config.yz;
    let m_down = u.zoom_config.w;

    // Audio reactivity
    let bass = extraBuffer[0];
    let mid = extraBuffer[133]; // approx mid

    // Camera
    let ro = vec3<f32>(0.0, 0.0, 5.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 2.0 * cw);

    // Raymarching
    var t_dist = 0.0;
    let max_d = 20.0;
    var col = vec3<f32>(0.0);
    var d: vec2<f32>;
    var p = ro;

    // Glow accumulation
    var glow = 0.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t_dist;
        d = map(p, time, mouse_pos, m_down, bass);

        // Accumulate glow based on proximity to threads
        glow += 0.01 / (0.01 + abs(d.x));

        if (d.x < 0.001 || t_dist > max_d) { break; }
        t_dist += d.x * 0.7; // step slightly smaller for safety with domain warping
    }

    if (t_dist < max_d) {
        let n = calcNormal(p, time, mouse_pos, m_down, bass);
        let view_dir = normalize(ro - p);

        // Lighting
        let light_dir = normalize(vec3<f32>(sin(time), 1.0, cos(time)));
        let diff = max(dot(n, light_dir), 0.0);

        // Fresnel / Thin-film iridescence
        let fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);

        // Material color base
        let irid_color = iridescence(p.z * 0.1 + fresnel + time * 0.2 + d.y * 0.3);

        // Ambient + Diffuse
        let ambient = vec3<f32>(0.05, 0.0, 0.1);
        col = ambient + irid_color * diff;

        // Specular
        let h = normalize(light_dir + view_dir);
        let spec = pow(max(dot(n, h), 0.0), 32.0);
        col += vec3<f32>(1.0) * spec * fresnel;

        // Distance fog
        col = mix(col, vec3<f32>(0.0, 0.0, 0.02), smoothstep(10.0, max_d, t_dist));
    }

    // Add volumetric plasma glow
    let intensity = u.zoom_params.z;
    let plasma_color = iridescence(time * 0.5 + mid * 2.0);
    col += plasma_color * glow * 0.02 * intensity;

    // Temporal blending (soft glowing trails)
    let prev_color = textureSampleLevel(readTexture, non_filtering_sampler, base_uv, 0.0).rgb;
    let blend_factor = 0.85; // 0.0 means no trail, 1.0 is full persistence
    col = mix(col, prev_color, blend_factor);

    // Tone mapping
    col = col / (1.0 + col);

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
