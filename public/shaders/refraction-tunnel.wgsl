// ═══════════════════════════════════════════════════════════════════
//  Refraction Tunnel
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            hoop-rails, liquid-rainbow-caustics
//  Complexity: High
//  Chunks From: refraction-tunnel
//  Upgraded: 2026-08-21
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

const TAU: f32 = 6.28318530718;

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let held = f32(u.zoom_config.w > 0.5);
    let aspect = resolution.x / resolution.y;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    let tunnelDepth = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.4);
    let twistAmount = (u.zoom_params.y - 0.5) * (8.0 + mids * 4.0);
    let aberration = u.zoom_params.z * 0.12 * (1.0 + treble * 0.3);
    let curvature = mix(-0.8, 0.8, u.zoom_params.w);

    let mouseOffset = (mousePos - 0.5) * curvature * (1.0 + held * 0.35);
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5) + mouseOffset;
    let dist = length(centeredUV);
    let safeDist = max(dist, 0.0001);
    let angle = atan2(centeredUV.y, centeredUV.x);

    let rotSpeed = 1.0 + bass * 2.5;
    let twistEnvelope = 1.0 - smoothstep(0.0, 1.2, safeDist);
    let newAngle = angle + twistAmount * twistEnvelope + time * rotSpeed * 0.3 * twistEnvelope
                 + held * (mousePos.x - 0.5) * 1.2 * twistEnvelope;

    let n1 = 1.0;
    let iorR = 1.15 + aberration * 0.5;
    let iorG = 1.12 + aberration * 0.3;
    let iorB = 1.09 + aberration * 0.1;

    let wallProximity = 1.0 - smoothstep(0.1, 0.9, safeDist);
    let tunnelRadius = mix(0.3, 1.0, tunnelDepth);
    let insideWall = step(safeDist, tunnelRadius);

    let sinTheta1 = sin(newAngle);
    let refractR = asin(clamp(sinTheta1 * n1 / iorR, -1.0, 1.0));
    let refractG = asin(clamp(sinTheta1 * n1 / iorG, -1.0, 1.0));
    let refractB = asin(clamp(sinTheta1 * n1 / iorB, -1.0, 1.0));

    let dispersionStrength = aberration * wallProximity * insideWall * 0.08;
    let rOffset = vec2<f32>(cos(refractR), sin(refractR)) * dispersionStrength;
    let gOffset = vec2<f32>(cos(refractG), sin(refractG)) * dispersionStrength * 0.7;
    let bOffset = vec2<f32>(cos(refractB), sin(refractB)) * dispersionStrength * 0.4;

    let baseUV = clamp(uv + centeredUV * (1.0 - pow(safeDist / max(tunnelRadius, 0.001), 0.5)), vec2<f32>(0.001), vec2<f32>(0.999));

    let rUV = clamp(baseUV + vec2<f32>(rOffset.x / aspect, rOffset.y), vec2<f32>(0.001), vec2<f32>(0.999));
    let gUV = clamp(baseUV + vec2<f32>(gOffset.x / aspect, gOffset.y), vec2<f32>(0.001), vec2<f32>(0.999));
    let bUV = clamp(baseUV + vec2<f32>(bOffset.x / aspect, bOffset.y), vec2<f32>(0.001), vec2<f32>(0.999));

    let rCol = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let gCol = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let bCol = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var rgb = vec3<f32>(rCol, gCol, bCol);

    let hoop = smoothstep(0.07, 0.0, abs(fract(safeDist * 8.0 - time * (2.2 + bass * 1.8)) - 0.5));
    let ribs = smoothstep(0.05, 0.0, abs(fract(newAngle / TAU * 18.0) - 0.5));
    let helix = smoothstep(0.08, 0.0, abs(fract(newAngle / TAU * 7.0 + safeDist * 4.0 - time * 2.5) - 0.5));
    let axial = smoothstep(0.07, 0.0, abs(fract(safeDist * 3.5 + newAngle * 0.3 - time * (3.0 + mids)) - 0.5));

    var clickRing = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
            clickRing = max(clickRing, exp(-abs(safeDist - age * 0.5) * 56.0) * (1.0 - age / 1.5));
        }
    }

    let filmPhase = newAngle * 1.4 + safeDist * 22.0 - time * 3.4;
    let liquidRainbow = 0.5 + 0.5 * cos(TAU * (vec3<f32>(filmPhase * 0.08) + vec3<f32>(0.0, 0.33, 0.67)));
    let mobiusCaustic = pow(max(0.0, sin(safeDist * 18.0 - newAngle * 4.0 - time * 4.2)), 6.0) * wallProximity;
    rgb += liquidRainbow * (mobiusCaustic * 0.45 + hoop * 0.28 + helix * 0.2 + clickRing * 0.5) * insideWall;
    rgb += liquidRainbow * ribs * 0.16 * insideWall;
    rgb += vec3<f32>(0.85, 0.95, 1.0) * axial * 0.18 * insideWall * treble;

    let fogDensity = wallProximity * (1.0 - depth * 0.6) * tunnelDepth;
    let fogColor = vec3<f32>(0.05, 0.08, 0.15) * (1.0 + mids * 0.5);
    rgb = mix(rgb, fogColor, fogDensity * 0.35);

    let streakDir = vec2<f32>(cos(newAngle + 1.57), sin(newAngle + 1.57));
    let streakUV = uv + streakDir * vec2<f32>(0.002 / aspect, 0.002);
    let streak = textureSampleLevel(readTexture, u_sampler, clamp(streakUV, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
    rgb += streak * wallProximity * aberration * 0.25;

    rgb = aces_tonemap(rgb * (1.0 + bass * 0.15 + held * 0.08));
    rgb = mix(rgb, prev.rgb * 0.88, 0.16 * insideWall);

    let alpha = clamp(wallProximity * aberration * 3.0 + insideWall * 0.25 + bass * 0.08 + clickRing * 0.3, 0.0, 1.0);
    let finalDepth = clamp(depth + wallProximity * 0.08 + ribs * 0.05 + hoop * 0.04, 0.0, 1.0);
    let finalPixel = vec4<f32>(rgb, alpha);

    textureStore(writeTexture, pixel, finalPixel);
    textureStore(writeDepthTexture, pixel, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, finalPixel);
}
