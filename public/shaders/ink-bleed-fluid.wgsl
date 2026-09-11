// ═══════════════════════════════════════════════════════════════════
//  Ink Bleed Fluid
//  Category: advanced-hybrid
//  Features: fluid-simulation, ink-diffusion, physical-media, temporal,
//            mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-09
//  Ideas: paper capillary; wet-edge darkening
//  A packing: raw vel.xy, pressure, ink density
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

fn paperTexture(uv: vec2<f32>) -> f32 {
    let noise = fract(sin(dot(uv * 100.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    return 0.9 + 0.1 * noise;
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let h = hsv.x * 6.0;
    let s = hsv.y;
    let v = hsv.z;
    let c = v * s;
    let x = c * (1.0 - abs(h - floor(h / 2.0) * 2.0 - 1.0));
    let m = v - c;
    var rgb: vec3<f32>;
    if (h < 1.0) { rgb = vec3(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3(x, 0.0, c); }
    else { rgb = vec3(c, 0.0, x); }
    return rgb + vec3(m);
}

fn loadC(p: vec2<i32>, res: vec2<f32>) -> vec4<f32> {
    let hi = vec2<i32>(res) - vec2<i32>(1);
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let dt = 0.016;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let inkHue = u.zoom_params.x;
    let viscosity = u.zoom_params.y * 0.001 + 0.0001;
    let spreadSpeed = u.zoom_params.z;
    let density = u.zoom_params.w;
    let fadeSpeed = 0.005;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = res.x / max(res.y, 1.0);

    let prevState = loadC(coord, res);
    var vel = prevState.rg;
    var pressure = prevState.b;
    var inkDensity = prevState.a;

    let maxVel = 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    let backtraceUV = clamp(uv - vel * dt, vec2<f32>(0.0), vec2<f32>(1.0));
    let backP = vec2<i32>(clamp(round(backtraceUV * res), vec2<f32>(0.0), res - 1.0));
    let advected = loadC(backP, res);
    vel = advected.rg;
    inkDensity = advected.a;

    let left = loadC(coord + vec2<i32>(-1, 0), res);
    let right = loadC(coord + vec2<i32>(1, 0), res);
    let down = loadC(coord + vec2<i32>(0, -1), res);
    let up = loadC(coord + vec2<i32>(0, 1), res);

    vel += viscosity * (left.rg + right.rg + down.rg + up.rg - 4.0 * vel);

    let divergence = ((right.b - left.b) / (2.0 * max(ps.x, 0.0001)) + (up.b - down.b) / (2.0 * max(ps.y, 0.0001)));
    pressure = (left.b + right.b + down.b + up.b - divergence * ps.x * ps.x * 4.0) * 0.25;
    pressure = clamp(pressure, -2.0, 2.0);
    vel -= vec2<f32>((right.b - left.b) / (2.0 * max(ps.x, 0.0001)), (up.b - down.b) / (2.0 * max(ps.y, 0.0001))) * 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    let curl = (right.rg.y - left.rg.y) - (up.rg.x - down.rg.x);
    let vorticityStrength = spreadSpeed * 0.005;
    vel += vec2<f32>(abs(curl) * sign(curl) * vorticityStrength) * vec2<f32>(1.0, -1.0);
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    let d = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let brushSize = 0.05;
    var newInk = 0.0;
    if (mouseDown > 0.5 && d < brushSize) {
        newInk = smoothstep(brushSize, 0.0, d);
        let mouseForce = normalize(uv - mouse + vec2<f32>(0.0001)) * smoothstep(0.15, 0.0, d) * -0.3;
        vel += mouseForce * dt * 15.0;
    }

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rippleDist < 0.08) {
            let inject = smoothstep(0.08, 0.0, rippleDist) * max(0.0, 1.0 - age * 0.5);
            inkDensity += inject * 0.5;
            let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
            vel += dir * inject * 0.1;
        }
    }

    inkDensity = min(inkDensity + newInk, 1.0);

    let paperTex = paperTexture(uv);
    // Idea 1 — paper capillary: valleys spread, peaks damp velocity
    let valley = 1.0 - paperTex;
    let avgInk = (left.a + right.a + down.a + up.a) * 0.25;
    inkDensity = mix(inkDensity, avgInk, spreadSpeed * (0.08 + valley * 0.12));
    vel *= mix(0.92, 1.0, paperTex);

    inkDensity *= (1.0 - fadeSpeed);
    if (inkDensity < 0.001) { inkDensity = 0.0; }
    inkDensity = clamp(inkDensity, 0.0, 5.0);

    textureStore(dataTextureA, coord, vec4<f32>(vel, pressure, inkDensity));

    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inkColorRGB = hsv2rgb(vec3<f32>(inkHue, 0.8, 0.25));

    let inkThickness = inkDensity * density;
    let dilution = 1.0 - density * 0.5;
    var inkAlpha = inkThickness * (0.9 - dilution * 0.4) + 0.1;
    let absorption = mix(0.7, 1.0, paperTex);
    inkAlpha *= absorption;
    let feather = smoothstep(0.0, 0.3, inkThickness);
    inkAlpha *= feather;

    var finalRGB = mix(videoColor.rgb, inkColorRGB * videoColor.rgb, inkThickness);
    let paperColor = vec3<f32>(0.98, 0.97, 0.95) * paperTex;
    finalRGB = mix(paperColor, finalRGB, inkAlpha);

    let speed = length(vel);
    let velHue = atan2(vel.y, vel.x) / 6.283185307 + 0.5;
    let velColor = hsv2rgb(vec3<f32>(velHue, smoothstep(0.0, 0.02, speed) * 0.3, 0.1));
    finalRGB += velColor * speed * 2.0;

    // Idea 2 — wet-edge darkening from density gradient
    let inkGrad = abs(right.a - left.a) + abs(up.a - down.a);
    let wetRim = smoothstep(0.04, 0.22, inkGrad) * smoothstep(0.02, 0.35, inkDensity);
    finalRGB *= 1.0 - wetRim * 0.18 * (1.0 + mids * 0.2);

    finalRGB = acesToneMap(finalRGB * (1.0 + bass * 0.08));
    inkAlpha = clamp(inkAlpha + wetRim * 0.12 + videoColor.a * 0.08 + treble * 0.03, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, inkAlpha));
    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
