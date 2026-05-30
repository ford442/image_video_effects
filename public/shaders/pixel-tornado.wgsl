// ═══════════════════════════════════════════════════════════════════
//  Pixel Tornado
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
//  A pixel-level tornado vortex. Each pixel is displaced by a
//  combined translational + rotational field whose eye tracks the
//  mouse. Bass energy widens the funnel; treble adds turbulent
//  jitter to individual pixels. Click ripples send shockwaves.
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=Strength, y=FunnelWidth, z=TurbulenceScale, w=InwardPull
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, vec2<f32>(269.5, 183.3))) * 17843.1234)
    ) * 2.0 - 1.0;
}

fn fbmVel(p: vec2<f32>) -> vec2<f32> {
    var v = vec2<f32>(0.0);
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 4; i++) {
        v += noise2(p * freq) * amp;
        freq *= 2.1;
        amp  *= 0.5;
    }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    // Audio
    let bass    = extraBuffer[0];
    let treble  = extraBuffer[2];

    // Params
    let strength     = mix(0.0, 0.25, u.zoom_params.x);
    let funnelWidth  = mix(0.05, 0.6, u.zoom_params.y) * (1.0 + bass * 0.8);
    let turbScale    = mix(1.0, 6.0,  u.zoom_params.z);
    let inwardPull   = mix(0.0, 1.0,  u.zoom_params.w);

    // Eye position tracks mouse
    let eye = u.zoom_config.yz;
    let delta = uv - eye;
    let dist  = length(delta);
    let angle = atan2(delta.y, delta.x);

    // Tornado profile: spiral inward more strongly near centre
    let profile  = exp(-dist * dist / (funnelWidth * funnelWidth));
    let twist    = strength * profile / (dist + 0.02);

    // Rotational displacement
    let rotAngle = twist + twist * time * 0.5; // angular step per pixel, grows over time
    let cosA = cos(rotAngle);
    let sinA = sin(rotAngle);
    let rotDelta = vec2<f32>(
        delta.x * cosA - delta.y * sinA,
        delta.x * sinA + delta.y * cosA
    );

    // Inward displacement
    let inward   = normalize(delta + vec2<f32>(0.0001)) * (-inwardPull * profile * strength * 0.5);
    let newDelta = rotDelta + inward;

    // Turbulent micro-jitter driven by treble
    let turbUV = uv * turbScale + vec2<f32>(time * 0.1, time * 0.07);
    let turb   = fbmVel(turbUV) * treble * 0.015;

    var sampleUV = eye + newDelta + turb;

    // Click ripple shockwaves
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rip  = u.ripples[i];
        let age  = time - rip.z;
        if (age >= 0.0 && age < 1.5) {
            let rDist = length(uv - rip.xy);
            let wave  = sin((rDist - age * 0.4) * 40.0) * exp(-age * 3.0) * exp(-rDist * 8.0);
            let dir   = normalize(uv - rip.xy + vec2<f32>(0.0001));
            sampleUV += dir * wave * 0.02;
        }
    }

    sampleUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Tint toward cyan/magenta near eye based on rotation direction
    let tintAngle = fract((angle + time * 0.3) / TAU);
    let tint = mix(
        vec3<f32>(0.8, 1.0, 1.1),
        vec3<f32>(1.1, 0.85, 1.0),
        tintAngle
    );
    let tintStr = profile * 0.25 * (1.0 + bass);
    var finalRGB = mix(col.rgb, col.rgb * tint, tintStr);

    // Semantic alpha
    let alpha = clamp(col.a + profile * 0.2, 0.0, 1.0);

    let outColor = vec4<f32>(finalRGB, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(profile, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(profile, dist, bass, treble));
}
