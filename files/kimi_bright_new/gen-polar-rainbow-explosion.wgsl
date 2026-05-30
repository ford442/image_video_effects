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

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// Hash functions
fn hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

// Value noise
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// Fractal Brownian Motion
fn fbm(p: vec2<f32>) -> f32 {
    var val: f32 = 0.0;
    var amp: f32 = 0.5;
    var freq: f32 = 1.0;
    for (var i: i32 = 0; i < 6; i = i + 1) {
        val += amp * vnoise(p * freq);
        freq *= 2.1;
        amp *= 0.5;
    }
    return val;
}

// Rainbow from hue
fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k.xyz) * 6.0 - 3.0);
    return clamp(p - 0.5, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Saturated neon palette
fn neonSpectrum(t: f32) -> vec3<f32> {
    let c1 = vec3<f32>(1.0, 0.08, 0.58);   // Hot magenta
    let c2 = vec3<f32>(1.0, 0.84, 0.0);    // Electric yellow
    let c3 = vec3<f32>(0.0, 1.0, 0.5);     // Neon green
    let c4 = vec3<f32>(0.0, 0.8, 1.0);     // Cyan
    let c5 = vec3<f32>(0.55, 0.0, 1.0);    // Violet

    let tt = fract(t);
    if (tt < 0.2) {
        return mix(c1, c2, tt / 0.2);
    } else if (tt < 0.4) {
        return mix(c2, c3, (tt - 0.2) / 0.2);
    } else if (tt < 0.6) {
        return mix(c3, c4, (tt - 0.4) / 0.2);
    } else if (tt < 0.8) {
        return mix(c4, c5, (tt - 0.6) / 0.2);
    } else {
        return mix(c5, c1, (tt - 0.8) / 0.2);
    }
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);
    let time = u.config.x;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouseDown = u.zoom_config.w;
    let mouseNorm = (mouse - resolution * 0.5) / min(resolution.x, resolution.y);

    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    var col = vec3<f32>(0.0);

    // Origin can be shifted by mouse
    var origin = mouseNorm * 0.5 * mouseDown;
    let centerUV = uv - origin;

    // Polar coordinates
    var radius = length(centerUV);
    var angle = atan2(centerUV.y, centerUV.x);

    // Base color - deep space
    col = vec3<f32>(0.01, 0.0, 0.03);

    // ---- RAINBOW RAYS ----
    let numRays = 36.0;
    let rayAngle = angle / TAU + 0.5;

    for (var r: f32 = 0.0; r < numRays; r = r + 1.0) {
        let rayPhase = r / numRays;
        let rayCenterAngle = rayPhase * TAU;

        // Organic wobble in ray direction
        let wobble = fbm(vec2<f32>(r * 0.3, time * 0.5 * speed)) * 0.15 * intensity;
        let wobble2 = vnoise(vec2<f32>(radius * 3.0, r + time * speed)) * 0.1 * intensity;

        let angleDiff = angle - rayCenterAngle + wobble + wobble2;
        // Wrap angle difference to [-PI, PI]
        let wrappedDiff = fract(angleDiff / TAU + 0.5) - 0.5;
        let distFromRay = abs(wrappedDiff) * TAU;

        // Ray width modulated by radius and noise
        let rayWidth = (0.03 + 0.02 * sin(radius * 8.0 + time * speed + r) * intensity) / (radius * 2.0 + 0.5) * scale;

        // Ray intensity falls off with radius
        let radialFalloff = exp(-radius * radius * 1.5) * (1.0 + 2.0 * mouseDown);
        let rayMask = smoothstep(rayWidth, 0.0, distFromRay) * radialFalloff;

        // Pulsing ray brightness
        let pulse = 0.6 + 0.4 * sin(time * 3.0 * speed + r * 0.5);

        // Color for this ray
        let hue = fract(rayPhase + time * 0.08 * speed + colorShift + radius * 0.3);
        let rayColor = neonSpectrum(hue);

        col += rayColor * rayMask * pulse * intensity * 2.5;
    }

    // ---- PARTICLE BURSTS ALONG RAYS ----
    let numBursts = 24.0;
    for (var b: f32 = 0.0; b < numBursts; b = b + 1.0) {
        let seed = hash1(b * 17.31 + 300.0);
        let seed2 = hash1(b * 43.71 + 500.0);
        let burstAngle = seed * TAU;
        let burstRadius = 0.05 + seed2 * 0.6;
        let burstSpeed = 0.3 + seed * 0.7;

        // Particles move outward along ray
        let currentRadius = fract(burstRadius + time * burstSpeed * speed * 0.08);
        let burstPos = vec2<f32>(cos(burstAngle), sin(burstAngle)) * currentRadius;

        // Multiple particles per burst
        for (var p: f32 = 0.0; p < 3.0; p = p + 1.0) {
            let pOffset = (p - 1.5) * 0.02;
            let pp = burstPos + vec2<f32>(cos(burstAngle + PI * 0.5), sin(burstAngle + PI * 0.5)) * pOffset;

            let dist = length(centerUV - pp);
            let pSize = 0.003 * scale;
            let pGlow = exp(-dist * dist / (pSize * pSize)) * (1.0 + mouseDown);

            let hue = fract(b / numBursts + time * 0.1 * speed + colorShift + p * 0.1);
            col += neonSpectrum(hue) * pGlow * intensity * 1.5;
        }
    }

    // ---- SPIRAL ARMS ----
    let numSpirals = 3.0;
    for (var s: f32 = 0.0; s < numSpirals; s = s + 1.0) {
        let spiralPhase = s / numSpirals;
        let spiralAngle = angle + radius * 4.0 * scale + spiralPhase * TAU - time * 0.8 * speed;
        let spiralDist = abs(fract(spiralAngle / TAU + 0.5) - 0.5) * TAU;
        let spiralWidth = 0.15 / (radius * 3.0 + 1.0);
        let spiralMask = smoothstep(spiralWidth, 0.0, spiralDist) * exp(-radius * 1.2) * 0.4;

        let hue = fract(spiralPhase + time * 0.06 * speed + colorShift + radius * 0.5);
        col += neonSpectrum(hue) * spiralMask * intensity;
    }

    // ---- CENTER EXPLOSION GLOW ----
    let centerGlow = exp(-radius * radius * 4.0) * (0.5 + 0.5 * sin(time * 5.0 * speed));
    let centerHue = fract(time * 0.12 * speed + colorShift);
    col += neonSpectrum(centerHue) * centerGlow * intensity * 2.0;

    // Mouse interaction - extra burst from cursor
    if (mouseDown > 0.5) {
        let mouseDist = length(uv - mouseNorm);
        let mouseBurst = exp(-mouseDist * mouseDist * 15.0);
        let mouseHue = fract(time * 0.2 * speed + colorShift);
        col += neonSpectrum(mouseHue) * mouseBurst * intensity * 3.0;
    }

    // Vignette
    let vig = 1.0 - dot(uv * 0.65, uv * 0.65);
    col *= clamp(vig, 0.0, 1.0) * 1.4;

    // Tone map
    col = col / (1.0 + col * 0.3);
    col = pow(col, vec3<f32>(0.92));

    // Brightness boost
    col = col * 2.2;

    textureStore(writeTexture, pixel, vec4<f32>(col, 1.0));
}
