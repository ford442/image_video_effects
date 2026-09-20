// ----------------------------------------------------------------
// Neon Plasma Chrono-Bloom
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
  zoom_params: vec4<f32>,  // .x = Intensity, .y = Distortion Speed, .z = Bloom Threshold, .w = Hue Shift
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS = 64;
const MAX_DIST = 10.0;
const SURF_DIST = 0.01;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Simplex noise
fn mod289(x: vec4<f32>) -> vec4<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: vec4<f32>) -> vec4<f32> { return mod289(((x * 34.0) + 1.0) * x); }
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * r; }

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0 / 6.0, 1.0 / 3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

    // First corner
    var i = floor(v + dot(v, C.yyy));
    let x0 = v - i + dot(i, C.xxx);

    // Other corners
    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);

    let x1 = x0 - i1 + C.xxx;
    let x2 = x0 - i2 + C.yyy;
    let x3 = x0 - D.yyy;

    // Permutations
    i = mod289(vec4<f32>(i.x, i.y, i.z, 0.0)).xyz;
    let p = permute(permute(permute(
             i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
           + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
           + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));

    // Gradients: 7x7 points over a square, mapped onto an octahedron.
    // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
    let n_ = 0.142857142857; // 1.0/7.0
    let ns = n_ * D.wyz - D.xzx;

    let j = p - 49.0 * floor(p * ns.z * ns.z); // mod(p,7*7)

    let x_ = floor(j * ns.z);
    let y_ = floor(j - 7.0 * x_); // mod(j,N)

    let x = x_ * ns.x + ns.yyyy;
    let y = y_ * ns.x + ns.yyyy;
    let h = 1.0 - abs(x) - abs(y);

    let b0 = vec4<f32>(x.xy, y.xy);
    let b1 = vec4<f32>(x.zw, y.zw);

    let s0 = floor(b0) * 2.0 + 1.0;
    let s1 = floor(b1) * 2.0 + 1.0;
    let sh = -step(h, vec4<f32>(0.0));

    let a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    let a1 = b1.xzyw + s1.xzyw * sh.zzww;

    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);

    let norm = taylorInvSqrt(vec4<f32>(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    var m = max(0.6 - vec4<f32>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m * m, vec4<f32>(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

fn map(p: vec3<f32>, t: f32) -> f32 {
    let intensity = u.zoom_params.x;
    let distortionSpeed = u.zoom_params.y;

    // Time dilation and gravity based on mouse
    var localP = p;
    var localT = t;
    if (u.zoom_config.w > 0.0) { // Mouse down
        let mouseUv = u.zoom_config.yz;
        let aspect = u.config.z / u.config.w;
        let mouseWorld = vec3<f32>((mouseUv.x * 2.0 - 1.0) * aspect, -(mouseUv.y * 2.0 - 1.0), 2.0); // Approximate ray intersection plane
        let dToMouse = length(localP - mouseWorld);

        let gravityRadius = 2.0;
        let pull = smoothstep(gravityRadius, 0.0, dToMouse);

        // Gravity pull
        localP = mix(localP, mouseWorld, pull * 0.5 * u.zoom_params.x);

        // Time dilation
        localT -= pull * 2.0 * distortionSpeed;
    }

    // Domain warp
    var q = localP;

    let baseTime = localT * 0.2 * distortionSpeed;

    var d = 0.0;

    // Multi-octave 3D noise for plasma density
    d += snoise(q * 1.0 + baseTime) * 0.5;
    q.x += d * 0.5;
    d += snoise(q * 2.0 - baseTime * 1.2) * 0.25;
    q.y += d * 0.5;
    d += snoise(q * 4.0 + baseTime * 1.5) * 0.125;

    // Create branching tendrils by absolute value and subtracting from a base density
    let tendrils = abs(d);

    // Surface is where density crosses a threshold
    let baseRadius = 0.3 * intensity;

    return tendrils - baseRadius;
}

// Palette for neon colors
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    // Oscillating between electric pink, cyan, deep purple
    // Hue shift added
    let hueOffset = u.zoom_params.w;
    let d = vec3<f32>(0.263, 0.416, 0.557) + hueOffset;
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    // Audio reactivity
    let bass = extraBuffer[0];
    let bassSmooth = extraBuffer[133];
    let audioMod = 1.0 + bassSmooth * 0.5;

    let uv = (coords - 0.5 * res) / res.y;
    let t = u.config.x;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -2.5);
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fwd = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(uv.x * right + uv.y * up + 1.0 * fwd);

    // Raymarching variables
    var p = ro;
    var totalDist = 0.0;
    var accumulatedDensity = 0.0;
    var emissiveGlow = 0.0;

    let bloomThreshold = u.zoom_params.z;

    // Volumetric raymarching
    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * totalDist;

        let d = map(p, t);

        // If inside the volume (distance is negative or very small)
        if (d < 0.05) {
            // Accumulate density
            let density = smoothstep(0.05, -0.1, d);
            accumulatedDensity += density * 0.05 * audioMod; // Boosted by audio

            // Bloom accumulation for bright parts
            if (density > bloomThreshold) {
                emissiveGlow += (density - bloomThreshold) * 0.1;
            }

            // Step forward by a small amount to march through the volume
            totalDist += 0.02;
        } else {
            // Step forward by the distance to the surface
            totalDist += d;
        }

        if (totalDist > MAX_DIST || accumulatedDensity > 0.95) {
            break;
        }
    }

    // Color mapping
    let colorT = accumulatedDensity * 2.0 - t * 0.1;
    var col = palette(colorT);

    // Apply accumulated density as opacity
    col *= accumulatedDensity;

    // Add procedural bloom
    col += col * emissiveGlow * 2.0;

    // Background fade (fog)
    let fog = 1.0 - exp(-0.1 * totalDist);
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05), fog); // Deep dark purple bg

    // Tonemapping and gamma correction
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
