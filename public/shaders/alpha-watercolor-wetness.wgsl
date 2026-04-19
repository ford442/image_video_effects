// ═══════════════════════════════════════════════════════════════════
//  Alpha Watercolor Wetness
//  Category: artistic
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = textureLoad(dataTextureC, coord, 0);
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
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let waterGradX = (right.a - left.a) * 0.5;
    let waterGradY = (up.a - down.a) * 0.5 - 0.005; // Gravity bias
    let waterFlow = vec2<f32>(waterGradX, waterGradY);

    // === PIGMENT ADVECTION ===
    // Pigment flows with water (only where wet)
    let dt = 0.5;
    let flowStrength = water * dt;
    let advectUV = clamp(uv - waterFlow * flowStrength, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectedPigment = textureSampleLevel(dataTextureC, u_sampler, advectUV, 0.0).rgb;

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

    // === VISUALIZATION ===
    // Paper texture (shows through where dry)
    let paperColor = vec3<f32>(0.96, 0.94, 0.90);
    let wetnessVis = smoothstep(0.0, 0.2, water);
    var displayColor = mix(paperColor, pigment, wetnessVis * 0.8 + 0.2);

    // Dark edge effect (pigment concentrates at wet boundary)
    let waterEdge = abs(waterGradX) + abs(waterGradY);
    let edgeDarken = smoothstep(0.02, 0.1, waterEdge) * smoothstep(0.5, 0.0, water);
    displayColor *= 1.0 - edgeDarken * 0.2;

    // Bloom from wetness
    displayColor += vec3<f32>(0.1, 0.15, 0.2) * smoothstep(0.3, 1.0, water) * 0.1;

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, water));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
