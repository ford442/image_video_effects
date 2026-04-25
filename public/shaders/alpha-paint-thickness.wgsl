// ═══════════════════════════════════════════════════════════════════
//  Alpha Paint Thickness
//  Category: artistic
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Paint pigment red
//    G = Paint pigment green
//    B = Paint pigment blue
//    A = Paint thickness (0.0 = bare canvas, 1.0+ = thick impasto)
//  Why f32: Thickness accumulates from many brush strokes and must
//  track sub-pixel changes. Specular highlight depends on thickness
//  gradient which requires f32 precision.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous paint state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var pigment = prevState.rgb;
    var thickness = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        pigment = vec3<f32>(0.0);
        thickness = 0.0;
    }

    // === PARAMETERS ===
    let brushSize = mix(0.02, 0.1, u.zoom_params.x);
    let paintColorMix = u.zoom_params.y;
    let lightDir = normalize(vec2<f32>(0.3, -0.5));

    // === MOUSE PAINTING ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseBrush = smoothstep(brushSize, 0.0, mouseDist) * mouseDown;

    // Paint color cycles with time
    let hue = fract(time * 0.05 + mousePos.x);
    let h6 = hue * 6.0;
    let c = 1.0;
    let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var brushColor: vec3<f32>;
    if (h6 < 1.0) { brushColor = vec3(c, x, 0.0); }
    else if (h6 < 2.0) { brushColor = vec3(x, c, 0.0); }
    else if (h6 < 3.0) { brushColor = vec3(0.0, c, x); }
    else if (h6 < 4.0) { brushColor = vec3(0.0, x, c); }
    else if (h6 < 5.0) { brushColor = vec3(x, 0.0, c); }
    else { brushColor = vec3(c, 0.0, x); }

    // Mix paint
    pigment = mix(pigment, brushColor, mouseBrush * paintColorMix);
    thickness += mouseBrush * 0.15;

    // === RIPPLE SPLATTERS ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.0 && rDist < 0.06) {
            let splatter = smoothstep(0.06, 0.0, rDist) * max(0.0, 1.0 - age);
            let rHue = fract(f32(i) * 0.618);
            let rh6 = rHue * 6.0;
            var rColor: vec3<f32>;
            let rc = 1.0;
            let rx = rc * (1.0 - abs(rh6 - floor(rh6 / 2.0) * 2.0 - 1.0));
            if (rh6 < 1.0) { rColor = vec3(rc, rx, 0.0); }
            else if (rh6 < 2.0) { rColor = vec3(rx, rc, 0.0); }
            else if (rh6 < 3.0) { rColor = vec3(0.0, rc, rx); }
            else if (rh6 < 4.0) { rColor = vec3(0.0, rx, rc); }
            else if (rh6 < 5.0) { rColor = vec3(rx, 0.0, rc); }
            else { rColor = vec3(rc, 0.0, rx); }
            pigment = mix(pigment, rColor, splatter * 0.5);
            thickness += splatter * 0.2;
        }
    }

    thickness = clamp(thickness, 0.0, 3.0);

    // === THICKNESS DIFFUSION (paint settles) ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Thickness gradient for normal estimation
    let thicknessGradX = (right.a - left.a) / (2.0 * ps.x);
    let thicknessGradY = (up.a - down.a) / (2.0 * ps.y);
    let thicknessNormal = normalize(vec2<f32>(-thicknessGradX, -thicknessGradY) + vec2<f32>(0.0, 1.0));

    // === VISUAL APPEARANCE BASED ON THICKNESS ===
    // Canvas color
    let canvasColor = vec3<f32>(0.95, 0.92, 0.88);

    // Thin: wash (canvas shows through)
    let washMix = smoothstep(0.0, 0.3, thickness);
    var displayColor = mix(canvasColor * pigment, pigment, washMix);

    // Medium: full color with slight texture
    let mediumMix = smoothstep(0.3, 0.7, thickness);
    let paintTexture = 1.0 - mediumMix * 0.05 * fract(sin(dot(uv, vec2<f32>(73.0, 37.0))) * 1000.0);
    displayColor *= paintTexture;

    // Thick: specular highlight from impasto
    let thickMix = smoothstep(0.7, 1.5, thickness);
    let specular = pow(max(0.0, dot(thicknessNormal, lightDir)), 32.0);
    displayColor += vec3<f32>(1.0, 0.98, 0.95) * specular * thickMix * 0.4;

    // Micro-shadow from thick paint edges
    let shadow = smoothstep(1.0, 2.0, thickness) * 0.15;
    displayColor *= 1.0 - shadow;

    // Very thick: add ridge highlights
    let ridge = smoothstep(1.5, 2.5, thickness);
    let ridgeNoise = fract(sin(dot(uv * 50.0, vec2<f32>(12.0, 78.0))) * 43758.0);
    displayColor += vec3<f32>(1.0, 1.0, 0.9) * ridge * ridgeNoise * 0.1;

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // === DECAY (paint dries over time) ===
    thickness *= 0.9995;

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(pigment, thickness));

    // === WRITE DISPLAY ===
    textureStore(writeTexture, coord, vec4<f32>(displayColor, thickness * 0.3));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
