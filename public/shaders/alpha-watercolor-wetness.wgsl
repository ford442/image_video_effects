// ═══════════════════════════════════════════════════════════════════
//  Alpha Watercolor Wetness
//  Category: artistic
//  Features: mouse-driven, paint, wetness, audio-bleed, depth-paper, pigment-settle, temporal, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: cockling warp; salt bloom on leaving water
//  A packing: raw pigment.rgb + water.a
// ═══════════════════════════════════════════════════════════════════
//  RGBA Channels:
//    R = Pigment red concentration
//    G = Pigment green concentration
//    B = Pigment blue concentration
//    A = Water level (0.0 = bone dry, 1.0 = soaking wet)
//  Why f32: Water level gradients drive capillary flow via partial
//  derivatives. 8-bit would create stair-step flow artifacts and
//  prevent smooth wet-to-dry transitions.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = loadC(coord, res);
    var pigment = prevState.rgb;
    var water = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        pigment = vec3<f32>(0.0);
        water = 0.0;
        // Pre-wet some areas
        let n = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        if (n > 0.95) {
            water = 0.6;
            pigment = vec3<f32>(0.3, 0.5, 0.8);
        }
    }

    water = clamp(water, 0.0, 2.0);
    pigment = clamp(pigment, vec3<f32>(0.0), vec3<f32>(2.0));

    // === WATER GRADIENTS ===
    let left = loadC(coord + vec2<i32>(-1, 0), res);
    let right = loadC(coord + vec2<i32>(1, 0), res);
    let down = loadC(coord + vec2<i32>(0, -1), res);
    let up = loadC(coord + vec2<i32>(0, 1), res);

    let waterGradX = (right.a - left.a) * 0.5;
    let waterGradY = (up.a - down.a) * 0.5 - 0.005; // Gravity bias
    let waterFlow = vec2<f32>(waterGradX, waterGradY);

    // === PIGMENT ADVECTION ===
    // Pigment flows with water (only where wet). flowStrength is saved param w.
    let dt = mix(0.25, 0.85, u.zoom_params.w);
    let flowStrength = water * dt;
    let advectUV = clamp(uv - waterFlow * flowStrength, vec2<f32>(0.0), vec2<f32>(1.0));
    let advP = vec2<i32>(clamp(round(advectUV * res), vec2<f32>(0.0), res - 1.0));
    let advectedPigment = loadC(advP, res).rgb;

    // Mix advected pigment with current
    pigment = mix(pigment, advectedPigment, min(water * 0.3, 0.5));

    // Pigment diffusion (faster when wet)
    let pigmentDiffusion = 0.02 + water * 0.05;
    let lapPigment = left.rgb + right.rgb + down.rgb + up.rgb - 4.0 * pigment;
    pigment += lapPigment * pigmentDiffusion;

    // === PARAMETERS ===
    let dryRate = mix(0.001, 0.02, u.zoom_params.x);
    let pigmentDeposit = u.zoom_params.y;
    let waterCap = 1.0 + u.zoom_params.z;

    // === WATER DRYING ===
    water *= (1.0 - dryRate);

    // === MOUSE WATER DROPS ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseWater = smoothstep(0.06, 0.0, mouseDist) * mouseDown;
    water += mouseWater * 0.4;

    // Mouse also deposits pigment if moving (simplified: just deposits on click)
    let mousePigment = mouseWater * pigmentDeposit;
    let brushHue = fract(time * 0.03 + mousePos.x * 2.0);
    let h6 = brushHue * 6.0;
    let c = 1.0;
    let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var brushColor: vec3<f32>;
    if (h6 < 1.0) { brushColor = vec3(c, x, 0.0); }
    else if (h6 < 2.0) { brushColor = vec3(x, c, 0.0); }
    else if (h6 < 3.0) { brushColor = vec3(0.0, c, x); }
    else if (h6 < 4.0) { brushColor = vec3(0.0, x, c); }
    else if (h6 < 5.0) { brushColor = vec3(x, 0.0, c); }
    else { brushColor = vec3(c, 0.0, x); }
    pigment = mix(pigment, brushColor, mousePigment * 0.5);

    // === RIPPLE WATER DROPS ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.0 && rDist < 0.05) {
            let drop = smoothstep(0.05, 0.0, rDist) * max(0.0, 1.0 - age);
            water += drop * 0.3;
        }
    }

    water = clamp(water, 0.0, waterCap);
    pigment = clamp(pigment, vec3<f32>(0.0), vec3<f32>(1.0));

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(pigment, water));

    // === VISUALIZATION - Visual Flourish ===
    // Idea 1 — cockling: wet paper buckles the photo UVs
    let waterLap = left.a + right.a + down.a + up.a - 4.0 * water;
    let cockleUV = clamp(uv + vec2<f32>(waterLap, -waterLap) * 0.012, vec2<f32>(0.0), vec2<f32>(1.0));
    let photo = textureSampleLevel(readTexture, u_sampler, cockleUV, 0.0);

    // Paper texture (shows through where dry)
    let paperColor = vec3<f32>(0.96, 0.94, 0.90);
    let wetnessVis = smoothstep(0.0, 0.2, water);
    var displayColor = mix(paperColor * photo.rgb, pigment, wetnessVis * 0.8 + 0.2);

    // Dark edge effect (pigment concentrates at wet boundary)
    let waterEdge = abs(waterGradX) + abs(waterGradY);
    let edgeDarken = smoothstep(0.02, 0.1, waterEdge) * smoothstep(0.5, 0.0, water);
    displayColor *= 1.0 - edgeDarken * 0.2;

    // === Richer atmospheric effects ===
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Mids create beautiful backruns / blooms when very wet
    let backrun = pow(smoothstep(0.6, 1.0, water), 2.0) * mids * 0.25;
    displayColor = mix(displayColor, vec3<f32>(0.85, 0.9, 0.95), backrun);

    // Treble adds granulation / pigment clumping (classic watercolor texture)
    let granulation = hash12(uv * 80.0 + time * 0.1) * treble * 0.15 * (1.0 - water * 0.5);
    displayColor *= (1.0 - granulation);

    // Bass adds subtle atmospheric haze when the paper is soaking
    let haze = smoothstep(0.4, 1.0, water) * bass * 0.12;
    displayColor = mix(displayColor, vec3<f32>(0.7, 0.75, 0.8), haze);

    // Bloom from wetness (enhanced)
    displayColor += vec3<f32>(0.12, 0.18, 0.22) * smoothstep(0.3, 1.0, water) * 0.12;

    // Idea 2 — salt bloom where water is leaving
    let leaving = max(0.0, prevState.a - water);
    let saltSeed = hash12(uv * 220.0 + vec2<f32>(17.0, 9.0));
    let salt = leaving * step(0.82, saltSeed) * smoothstep(0.02, 0.12, leaving);
    displayColor = mix(displayColor, vec3<f32>(0.97, 0.96, 0.93), salt * 0.7);

    displayColor = acesToneMap(clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0)));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, clamp(water * 0.5 + wetnessVis * 0.3 + photo.a * 0.15, 0.0, 1.0)));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
