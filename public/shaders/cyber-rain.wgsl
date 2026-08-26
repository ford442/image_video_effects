// ═══════════════════════════════════════════════════════════════════
//  Cyber Rain — Batch 59
//  Neon rain on wet glass: spring wiper, capped EMP ripples, held punch,
//  exact C wetness trail, extraBuffer[133..138] spring at (0,0) only.
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

const PI: f32 = 3.14159265359;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    return mix(prev, bass, select(release, attack, bass > prev));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let len = length(v);
    return select(v / len, vec2<f32>(0.0), len < 0.0001);
}

fn empRing(uvAspect: vec2<f32>, center: vec2<f32>, age: f32) -> f32 {
    let radius = age * 0.55;
    let dRing = abs(length(uvAspect - center) - radius);
    return exp(-dRing * dRing * 180.0) * (1.0 - age * 0.75) * 1.6;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;

    let rainBase = clamp(u.zoom_params.x, 0.0, 1.0);
    let blurStrength = u.zoom_params.y * 0.1;
    let bloomThreshold = u.zoom_params.z;
    let wiperSize = u.zoom_params.w * 0.5 * select(1.0, 0.82, held);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prev = textureLoad(dataTextureC, coord, 0);
    let env = bass_env(prev.a, bass, 0.8, 0.15);

    // Spring wiper: extraBuffer[133..138], single writer at (0,0).
    var smoothMouse = mouse;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring) {
        smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = mouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 9.0;
            let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
        smoothMouse = springPos;
    }

    let rainIntensity = clamp(rainBase * (1.0 + env * 0.5), 0.0, 1.0);
    let uvAspect = uv * vec2<f32>(aspect, 1.0);
    let smoothAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);

    let distVec = uvAspect - smoothAspect;
    let dist = length(distVec);
    let wiper = smoothstep(wiperSize, wiperSize * 0.75, dist) * select(1.0, 1.25, held);

    let toMouse = smoothAspect - uvAspect;
    let gravityStrength = smoothstep(0.55, 0.0, length(toMouse)) * (0.08 + env * 0.06);
    let rainBend = safeNormalize(toMouse).x * gravityStrength;

    var blurredColor = vec3<f32>(0.0);
    for (var i = 0; i < 5; i++) {
        let t = f32(i) / 4.0;
        let offset = (t - 0.5) * blurStrength * 2.0 * (1.0 - wiper);
        let sampleUV = clamp(uv + vec2<f32>(0.0, offset), vec2<f32>(0.0), vec2<f32>(1.0));
        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let brightness = max(col.r, max(col.g, col.b));
        let bloom = smoothstep(bloomThreshold, 1.0, brightness);
        blurredColor += col * (1.0 + bloom * (2.0 + mids));
    }
    blurredColor /= 5.0;

    var color = mix(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, blurredColor, rainIntensity * 0.8);

    let band = min(u32(uv.x * 8.0), 7u);
    let bandRain = 1.0 + plasmaBuffer[band + 1u].x * 0.35;

    let rainUV = uv * vec2<f32>(24.0, 2.5) + vec2<f32>(time * (0.2 + rainBend * 4.0), time * (8.0 + env * 12.0));
    let drop = smoothstep(0.88, 0.95, hash12(floor(rainUV))) * rainIntensity * (1.0 - wiper) * bandRain;

    let streakUV = uv * vec2<f32>(8.0, 40.0) + vec2<f32>(time * 0.3 + rainBend * 2.0, time * 25.0);
    let streak = smoothstep(0.92, 0.98, hash12(floor(streakUV))) * rainIntensity * (1.0 - wiper) * 0.5;

    let rainColor = vec3<f32>(0.45, 0.75, 1.0) + vec3<f32>(0.2, 0.1, 0.0) * env;
    color += rainColor * (drop + streak);

    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.25) {
            let clickAspect = vec2<f32>(rp.x * aspect, rp.y);
            shock += empRing(uvAspect, clickAspect, age);
        }
    }
    color += rainColor * shock * (0.7 + treble);

    let flash = smoothstep(0.7, 0.9, env) * 0.25 * fract(time * 16.0);
    color += vec3<f32>(0.9, 0.95, 1.0) * flash;

    let wetTrail = mix(prev.rgb * 0.93, color, 0.08 + rainIntensity * 0.1);
    color = mix(color, wetTrail, 0.35 + rainIntensity * 0.3);

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let fog = 1.0 - exp(-depth * 2.0);
    color = mix(color, color * 0.6 + rainColor * 0.05, fog * 0.45);

    let dir = (uv - vec2<f32>(0.5)) / (length(uv - vec2<f32>(0.5)) + 0.0001);
    let caAmt = (0.002 + depth * 0.0015) * (1.0 + env);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + dir * caAmt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - dir * caAmt * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color = vec3<f32>(r, color.g, b);

    color = acesToneMap(color * (0.9 + env * 0.15));

    let alpha = clamp(0.3 + rainIntensity * 0.55 + drop * 0.4 + shock * 0.25, 0.0, 0.95);
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(wetTrail, env));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
