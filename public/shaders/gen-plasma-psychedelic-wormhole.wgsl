// ═══════════════════════════════════════════════════════════════════
//  Plasma Psychedelic Wormhole
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven
//  Complexity: High
//  Wolfram: Blackbody peak wavelength 499.6 nm (5800K) drives plasma color.
//           Bass drives temperature: higher bass = hotter = bluer.
//  Created: 2026-05-31
//  Updated: 2026-06-07
//  By: Kimi Agent
// ═══════════════════════════════════════════════════════════════════

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: blackbodyColor (Wolfram Alpha: peak 499.6nm at 5800K) ═══
fn blackbodyColor(tempK: f32) -> vec3<f32> {
    let t = clamp((tempK - 3000.0) / 7000.0, 0.0, 1.0);
    let warm = vec3<f32>(1.0, 0.65, 0.3);   // 3000K — warm orange
    let mid  = vec3<f32>(1.0, 0.95, 0.8);   // 5800K — white-yellow
    let cool = vec3<f32>(0.8, 0.9, 1.0);    // 10000K — cool blue
    let c1 = mix(warm, mid, smoothstep(0.0, 0.4, t));
    return mix(c1, cool, smoothstep(0.4, 1.0, t));
}

// Plasma palette driven by blackbody temperature and peak wavelength
fn plasmaPalette(t: f32, tempK: f32) -> vec3<f32> {
    let bb = blackbodyColor(tempK);
    // Peak wavelength shifts inversely with temperature (Wien's law)
    // Higher temp = shorter wavelength = bluer
    let waveShift = 1.0 + (tempK - 5800.0) / 10000.0;
    return vec3<f32>(
        0.5 + 0.5 * cos(TAU * (t * waveShift + 0.0)) * bb.r,
        0.5 + 0.5 * cos(TAU * (t * waveShift + 0.333)) * bb.g,
        0.5 + 0.5 * cos(TAU * (t * waveShift + 0.667)) * bb.b
    );
}

fn hotPlasmaPalette(t: f32, tempK: f32) -> vec3<f32> {
    let bb = blackbodyColor(tempK);
    return vec3<f32>(
        0.5 + 0.5 * cos(TAU * t - 0.0) * bb.r,
        0.5 + 0.5 * cos(TAU * t - 2.094) * bb.g,
        0.5 + 0.5 * cos(TAU * t - 4.189) * bb.b
    );
}

fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let q = p3 + dot(p3, p3.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
    var v: f32 = 0.0;
    var a: f32 = 0.5;
    var shift = vec2<f32>(time * 0.1, time * 0.08);
    var pp = p;
    for (var i = 0; i < 6; i++) {
        v += a * noise(pp + shift);
        pp = pp * 2.0 + vec2<f32>(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

fn stars(uv: vec2<f32>, time: f32) -> f32 {
    let starGrid = floor(uv * 80.0);
    let starHash = hash2(starGrid);
    let starCenter = (starGrid + 0.5 + vec2<f32>(hash1(starHash * 13.0), hash1(starHash * 37.0)) * 0.3) / 80.0;
    let d = length(uv - starCenter);
    let twinkle = sin(time * 3.0 + starHash * TAU) * 0.5 + 0.5;
    let brightness = smoothstep(0.003, 0.0, d) * (0.3 + 0.7 * twinkle) * step(0.97, starHash);
    return brightness;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let uvNorm = vec2<f32>(pixel) / res;

    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseNorm = (mousePos - res * 0.5) / min(res.x, res.y);
    let mouseDown = u.zoom_config.w > 0.5;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Temporal feedback
    let prev = textureSampleLevel(dataTextureC, u_sampler, uvNorm, 0.0);

    let audioSpeed = speed * (0.85 + bass * 0.8);
    let audioIntensity = intensity * (0.8 + treble * 0.7);
    let audioColor = colorShift + mids * 0.3;

    let aspect = res.x / res.y;

    // Mouse controls tunnel curvature
    var tunnelShift = vec2<f32>(0.0);
    if (mouseDown) {
        tunnelShift = mouseNorm * 0.5;
    }

    let p = uv + tunnelShift;
    let r = length(p);
    let theta = atan2(p.y, p.x);

    // Wormhole tunnel coordinates
    let tunnelDepth = 1.0 / (r + 0.05);
    let spiralTheta = theta + time * (0.3 + speed * 0.7);
    let spiralU = tunnelDepth * (0.5 + scale * 0.5) + time * (0.5 + speed);
    let spiralV = spiralTheta / TAU * 6.0 + tunnelDepth * 0.3;

    // Multi-octave swirling plasma
    var plasmaVal: f32 = 0.0;
    var pp = vec2<f32>(spiralU, spiralV);

    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let rotAngle = time * (0.2 + fi * 0.1) * (1.0 + speed);
        let cos_r = cos(rotAngle);
        let sin_r = sin(rotAngle);
        let rotMat = mat2x2<f32>(cos_r, -sin_r, sin_r, cos_r);
        pp = rotMat * pp;
        plasmaVal += noise(pp + vec2<f32>(time * 0.3, time * 0.2)) * (0.5 - fi * 0.08);
        pp *= 2.0;
    }

    // Additional swirling layer
    let swirl = fbm(
        vec2<f32>(
            r * 5.0 + time * 0.4,
            theta * 3.0 + tunnelDepth * 0.5 - time * 0.3
        ),
        time * 0.5
    );

    plasmaVal += swirl * 0.3;

    // Radial bands
    let bandFreq = 8.0 + scale * 16.0;
    let bands = sin(tunnelDepth * bandFreq + time * (1.0 + speed * 2.0)) * 0.5 + 0.5;
    plasmaVal += bands * 0.25;

    // Spiral arms
    let arms = 4.0 + floor(scale * 8.0);
    let armPattern = sin(spiralTheta * arms + tunnelDepth * 4.0 - time * (1.0 + speed)) * 0.5 + 0.5;
    plasmaVal += armPattern * 0.2;

    // Bass drives plasma temperature (3000K .. 10000K)
    let plasmaTemp = mix(3000.0, 10000.0, bass);

    // Color from plasma with blackbody temperature
    let hue1 = fract(plasmaVal * 0.8 + time * 0.06 + audioColor);
    let hue2 = fract(plasmaVal * 1.2 - time * 0.04 + audioColor + 0.33);

    let col1 = plasmaPalette(hue1, plasmaTemp);
    let col2 = hotPlasmaPalette(hue2, plasmaTemp);

    var col = mix(col1, col2, plasmaVal);

    // Center glow — hotter with bass
    let centerGlow = exp(-r * r * 12.0) * (0.5 + 0.5 * sin(time * 2.0));
    col += blackbodyColor(mix(5800.0, 10000.0, bass)) * centerGlow * intensity;

    // Tunnel edge rings
    let ringFreq = 6.0;
    let rings = sin(tunnelDepth * ringFreq - time * 3.0) * 0.5 + 0.5;
    let ringGlow = rings * exp(-r * r * 3.0) * r * 2.0;
    let ringHue = fract(tunnelDepth * 0.1 + time * 0.05 + audioColor);
    col += plasmaPalette(ringHue, plasmaTemp) * ringGlow * 0.4 * intensity;

    // Stars streaming past edges
    let starUV = vec2<f32>(
        fract(theta / PI + time * 0.1),
        fract(tunnelDepth * 0.3 - time * (0.5 + speed))
    );
    let starField = stars(starUV * vec2<f32>(1.0, 2.0), time);
    col += vec3<f32>(0.9, 0.95, 1.0) * starField * (0.3 + r * 0.5) * intensity;

    // Additional star streaks
    let streakAngle = theta + time * (0.5 + speed * 0.5);
    let streakR = fract(r * 8.0 + time * 2.0);
    let streaks = exp(-abs(streakR - 0.5) * 20.0) * smoothstep(0.3, 0.6, r);
    let streakHue = fract(theta / TAU + time * 0.1 + audioColor);
    col += plasmaPalette(streakHue, plasmaTemp) * streaks * 0.3 * intensity;

    // Vignette and radial falloff
    let vignette = smoothstep(1.2, 0.0, r);
    col *= vignette * 1.5;

    // Brightness boost
    col *= (0.7 + intensity * 0.6);

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // ACES tone mapping
    var finalColor = acesToneMap(col * 1.1);

    // Temporal feedback
    let decay = 0.96;
    let temporal = mix(prev.rgb * decay, finalColor, 0.25);
    textureStore(dataTextureA, pixel, vec4<f32>(temporal, 1.0));

    // Semantic alpha
    let presence = clamp(length(finalColor) * 1.2, 0.0, 1.0);
    let alpha = clamp(presence * 0.8, 0.2, 0.95);
    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
}
