// ----------------------------------------------------------------
// Luminescent Nebula-Silk Weaver
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
  zoom_params: vec4<f32>,  // .x = Flow Complexity, .y = Ribbon Width, .z = Iridescence, .w = Audio Pulse
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Simplex 3D Noise
fn mod289(x: vec3<f32>) -> vec3<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn mod289_4(x: vec4<f32>) -> vec4<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: vec4<f32>) -> vec4<f32> { return mod289_4(((x*34.0)+1.0)*x); }
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * r; }

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0/6.0, 1.0/3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

    var i = floor(v + dot(v, C.yyy));
    var x0 = v - i + dot(i, C.xxx);

    var g = step(x0.yzx, x0.xyz);
    var l = 1.0 - g;
    var i1 = min(g.xyz, l.zxy);
    var i2 = max(g.xyz, l.zxy);

    var x1 = x0 - i1 + C.xxx;
    var x2 = x0 - i2 + C.yyy;
    var x3 = x0 - D.yyy;

    i = mod289(i);
    var p = permute(permute(permute(
        i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
      + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
      + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));

    var n_ = 0.142857142857;
    var ns = n_ * D.wyz - D.xzx;

    var j = p - 49.0 * floor(p * ns.z * ns.z);

    var x_ = floor(j * ns.z);
    var y_ = floor(j - 7.0 * x_);

    var x = x_ *ns.x + ns.yyyy;
    var y = y_ *ns.x + ns.yyyy;
    var h = 1.0 - abs(x) - abs(y);

    var b0 = vec4<f32>(x.xy, y.xy);
    var b1 = vec4<f32>(x.zw, y.zw);

    var s0 = floor(b0)*2.0 + 1.0;
    var s1 = floor(b1)*2.0 + 1.0;
    var sh = -step(h, vec4<f32>(0.0));

    var a0 = b0.xzyw + s0.xzyw*sh.xxyy;
    var a1 = b1.xzyw + s1.xzyw*sh.zzww;

    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);

    var norm = taylorInvSqrt(vec4<f32>(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
    p0 = p0 * norm.x;
    p1 = p1 * norm.y;
    p2 = p2 * norm.z;
    p3 = p3 * norm.w;

    var m = max(0.6 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m*m, vec4<f32>(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

// Curl noise
fn snoiseVec3(x: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        snoise(x),
        snoise(x + vec3<f32>(43.2, 17.5, 93.1)),
        snoise(x + vec3<f32>(-21.7, 52.8, -43.5))
    );
}

fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    let e = 0.01;
    let dx = vec3<f32>(e, 0.0, 0.0);
    let dy = vec3<f32>(0.0, e, 0.0);
    let dz = vec3<f32>(0.0, 0.0, e);

    let p_x0 = snoiseVec3(p - dx);
    let p_x1 = snoiseVec3(p + dx);
    let p_y0 = snoiseVec3(p - dy);
    let p_y1 = snoiseVec3(p + dy);
    let p_z0 = snoiseVec3(p - dz);
    let p_z1 = snoiseVec3(p + dz);

    let x = p_y1.z - p_y0.z - p_z1.y + p_z0.y;
    let y = p_z1.x - p_z0.x - p_x1.z + p_x0.z;
    let z = p_x1.y - p_x0.y - p_y1.x + p_y0.x;

    return normalize(vec3<f32>(x, y, z) / (2.0 * e));
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let t = u.config.x;

    // Mouse Interaction
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let mouseWorld = vec3<f32>(mouse.x * 3.0, -mouse.y * 3.0, 0.0); // Simple projection
    let dMouse = distance(p, mouseWorld);

    let pull = smoothstep(2.0, 0.0, dMouse) * u.zoom_config.w;
    if (pull > 0.0) {
        // Vortex effect
        let pullDir = normalize(p - mouseWorld);
        var r = p.xy;
        let vAngle = pull * 2.0;
        let s = sin(vAngle);
        let c = cos(vAngle);
        let rot = mat2x2<f32>(c, -s, s, c);
        r = rot * r;
        p = vec3<f32>(r.x, r.y, p.z) - pullDir * pull * 0.5;
    }

    let complexity = u.zoom_params.x; // 0.5 - 4.0
    let width = u.zoom_params.y; // 0.01 - 0.2

    var flow = p * complexity + t * 0.2;
    var curl = curlNoise(flow);

    // Add fBM turbulence
    curl += snoiseVec3(flow * 2.5) * 0.5;
    curl += snoiseVec3(flow * 5.0) * 0.25;
    curl = normalize(curl);

    // SDF to "ribbons" or "tubes" along the curl noise
    // We approximate this by finding the distance to a grid of lines that have been perturbed by the curl noise.
    // A simpler volumetric approach is to evaluate density directly.
    // For SDF map, we can evaluate distance to the closest flow path.

    // Distance to the curl field itself (creating tubes)
    // Project position onto the flow direction
    let proj = dot(p, curl) * curl;
    let dLine = length(p - proj);

    // We use a periodic structure perturbed by the noise to create multiple ribbons
    var q = p + curl * 0.5;
    let spacing = 1.5;
    q = (fract(q / spacing + 0.5) - 0.5) * spacing;

    // Distance to ribbon surface
    let dRibbon = length(q.xz) - width;

    // Material ID based on noise
    let matID = snoise(p * 0.5) * 0.5 + 0.5;

    return vec2<f32>(dRibbon * 0.6, matID); // 0.6 is a safe under-estimator for raymarching with heavy noise
}

// Get normal for lighting
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// ACES Tone Mapping
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, audioPulse: f32) -> vec4<f32> {
    var dO = 0.0;
    var dS: vec2<f32>;
    var col = vec3<f32>(0.0);
    var accumDens = 0.0;

    let iridescence = u.zoom_params.z; // 0.0 - 3.0

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * dO;
        dS = map(p);

        // Volumetric accumulation
        if (dS.x < 0.05) {
            let dens = (0.05 - dS.x) * 10.0; // Density
            accumDens += dens * 0.05;

            // Color based on material ID and time
            let t = u.config.x;
            var baseCol = 0.5 + 0.5 * cos(t + dS.y * 6.28 + vec3<f32>(0.0, 2.0, 4.0));

            // Audio Pulse emission
            let emission = audioPulse * (0.5 + 0.5 * sin(dO * 5.0 - t * 10.0));
            baseCol += vec3<f32>(1.0, 0.2, 0.8) * emission * dens; // Magenta/gold flare

            // Pseudo-Iridescence / Fresnel
            let n = getNormal(p);
            let fre = pow(1.0 + dot(n, rd), 3.0);
            let iriCol = 0.5 + 0.5 * cos(fre * 10.0 + vec3<f32>(0.0, 2.0, 4.0));
            baseCol += iriCol * iridescence * fre;

            col += baseCol * dens * 0.1 * exp(-dO * 0.2); // Attenuation
        }

        if (accumDens > 0.95 || dO > 20.0) { break; }

        // Push forward, minimum step size to avoid getting stuck in negative space
        dO += max(abs(dS.x), 0.02);
    }

    return vec4<f32>(col, accumDens);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) {
        return;
    }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = vec2<f32>(coords) / resolution;
    let base_uv = uv; // Keep for data textures
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);

    // Simple pan based on time
    let t = u.config.x * 0.1;
    ro.x += sin(t);
    ro.y += cos(t);

    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);

    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Audio sampling
    // Read from dataTextureC (frequency data)
    let audioSample = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(base_uv.x, 0.5), 0.0).r;
    let audioPulse = u.zoom_params.w * audioSample; // 0.0 - 2.0

    // Raymarch
    let result = raymarch(ro, rd, audioPulse);

    // Background color (dark blue/purple void)
    var bg = vec3<f32>(0.01, 0.0, 0.03) - length(uv) * 0.01;

    // Composite
    var color = mix(bg, result.rgb, min(result.a, 1.0));

    // Bloom approximation
    color += result.rgb * 0.5;

    // Tone mapping
    color = aces(color);

    textureStore(writeTexture, coords, vec4<f32>(color, 1.0));
}
