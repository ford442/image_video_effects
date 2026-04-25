// ═══════════════════════════════════════════════════════════════════════════════
//  Audiovisual Mandelbulb Raymarcher
//  Category: generative
//  Description: 3D Mandelbulb fractal raymarched with video texture mapping
//               and audio-reactive geometry mutation.
//  Features: raymarched, audio-reactive, mouse-driven, depth-aware
// ═══════════════════════════════════════════════════════════════════════════════

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

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

// Mandelbulb distance estimator
fn mandelbulbDE(p: vec3<f32>, power: f32, iterations: i32) -> f32 {
    var z = p;
    var dr = 1.0;
    var r = 0.0;
    for (var i: i32 = 0; i < iterations; i = i + 1) {
        r = length(z);
        if (r > 2.0) { break; }
        let theta = acos(clamp(z.y / r, -1.0, 1.0));
        let phi = atan2(z.z, z.x);
        let zr = pow(r, power);
        dr = pow(r, power - 1.0) * power * dr + 1.0;
        let st = sin(theta * power);
        let ct = cos(theta * power);
        let sp = sin(phi * power);
        let cp = cos(phi * power);
        z = zr * vec3<f32>(st * cp, ct, st * sp) + p;
    }
    return 0.5 * log(r) * r / dr;
}

fn calcNormal(p: vec3<f32>, power: f32, iterations: i32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        mandelbulbDE(p + e.xyy, power, iterations) - mandelbulbDE(p - e.xyy, power, iterations),
        mandelbulbDE(p + e.yxy, power, iterations) - mandelbulbDE(p - e.yxy, power, iterations),
        mandelbulbDE(p + e.yyx, power, iterations) - mandelbulbDE(p - e.yyx, power, iterations)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = (vec2<f32>(id.xy) / res - 0.5) * vec2<f32>(res.x / res.y, 1.0);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let iterations = i32(mix(4.0, 12.0, u.zoom_params.x));
    let escapeRadius = u.zoom_params.y * 2.0 + 6.0;
    let glowStrength = u.zoom_params.z * 2.0;
    let textureBlend = u.zoom_params.w;

    // Camera rotation from mouse
    let mouseRotY = (u.zoom_config.y - 0.5) * 3.14159;
    let mouseRotX = (u.zoom_config.z - 0.5) * 1.5708;

    // Ray setup
    var ro = vec3<f32>(0.0, 0.0, -2.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    ro = rotY(mouseRotY) * rotX(mouseRotX) * ro;
    rd = rotY(mouseRotY) * rotX(mouseRotX) * rd;

    // Audio-reactive power
    let power = 8.0 + bass * 4.0 + sin(time * 0.5) * 2.0;

    // Raymarch
    var t = 0.0;
    var hit = false;
    for (var i: i32 = 0; i < 80; i = i + 1) {
        let p = ro + rd * t;
        let d = mandelbulbDE(p, power, iterations);
        if (d < 0.001) {
            hit = true;
            break;
        }
        t += d;
        if (t > escapeRadius) { break; }
    }

    var col = vec3<f32>(0.0);
    var depth = 0.0;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, power, iterations);

        // Orbit trap coloring
        let orbit = fract(length(p) * 0.5 + time * 0.1);
        let fractalCol = vec3<f32>(
            0.5 + 0.5 * cos(orbit * 6.28318 + 0.0),
            0.5 + 0.5 * cos(orbit * 6.28318 + 2.094),
            0.5 + 0.5 * cos(orbit * 6.28318 + 4.189)
        );

        // Video texture mapping (spherical projection)
        let texUV = vec2<f32>(
            atan2(n.z, n.x) / 6.28318 + 0.5,
            n.y * 0.5 + 0.5
        );
        let videoCol = textureSampleLevel(readTexture, u_sampler, texUV, 0.0).rgb;

        // Blend fractal color with video
        col = mix(fractalCol, videoCol, textureBlend);

        // Lighting
        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = max(dot(n, lig), 0.0);
        let amb = 0.3;
        col = col * (amb + dif * 0.7);

        depth = 1.0 - t / escapeRadius;
    } else {
        // Background with video
        let bgUV = uv * 0.5 + vec2<f32>(0.5);
        col = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb * 0.3;

        // Glow from near misses
        let glow = glowStrength * 0.02 / (t * t + 0.1);
        let glowCol = vec3<f32>(0.2, 0.4, 0.8) * glow * (1.0 + bass);
        col = col + glowCol;
        depth = 0.0;
    }

    // Treble sparkle
    if (treble > 0.5) {
        let sparkle = hash(vec2<f32>(f32(id.x), f32(id.y)) + time);
        if (sparkle > 0.995) {
            col = col + vec3<f32>(1.0, 0.9, 0.7) * treble;
        }
    }

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(2.0));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
