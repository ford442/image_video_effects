// ═══════════════════════════════════════════════════════════════════
//  Alpha Paint Thickness
//  Category: artistic
//  Features: mouse-driven, temporal, rgba-state-machine, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: palette-knife ridge; canvas tooth in thin wash
//  A packing: raw pigment.rgb + thickness.a
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
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let prevState = loadC(coord, res);
    var pigment = prevState.rgb;
    var thickness = prevState.a;

    if (time < 0.1) {
        pigment = vec3<f32>(0.0);
        thickness = 0.0;
    }

    let brushSize = mix(0.02, 0.1, u.zoom_params.x);
    let paintColorMix = u.zoom_params.y;
    let specPower = mix(8.0, 64.0, u.zoom_params.z);
    let dryingRate = mix(0.9999, 0.997, u.zoom_params.w);
    let lightDir = normalize(vec2<f32>(0.3, -0.5));

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseBrush = smoothstep(brushSize, 0.0, mouseDist) * mouseDown;

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

    pigment = mix(pigment, brushColor, mouseBrush * paintColorMix);
    thickness += mouseBrush * 0.15 * (1.0 + bass * 0.2);

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

    let left = loadC(coord + vec2<i32>(-1, 0), res);
    let right = loadC(coord + vec2<i32>(1, 0), res);
    let down = loadC(coord + vec2<i32>(0, -1), res);
    let up = loadC(coord + vec2<i32>(0, 1), res);

    let thicknessGradX = (right.a - left.a) / (2.0 * max(ps.x, 0.0001));
    let thicknessGradY = (up.a - down.a) / (2.0 * max(ps.y, 0.0001));
    let thicknessNormal = normalize(vec2<f32>(-thicknessGradX, -thicknessGradY) + vec2<f32>(0.0, 1.0));

    let canvasColor = vec3<f32>(0.95, 0.92, 0.88);
    let washMix = smoothstep(0.0, 0.3, thickness);
    var displayColor = mix(canvasColor * pigment, pigment, washMix);

    let mediumMix = smoothstep(0.3, 0.7, thickness);
    let paintTexture = 1.0 - mediumMix * 0.05 * fract(sin(dot(uv, vec2<f32>(73.0, 37.0))) * 1000.0);
    displayColor *= paintTexture;

    let thickMix = smoothstep(0.7, 1.5, thickness);
    let specular = pow(max(0.0, dot(thicknessNormal, lightDir)), specPower);
    displayColor += vec3<f32>(1.0, 0.98, 0.95) * specular * thickMix * 0.4;

    let shadow = smoothstep(1.0, 2.0, thickness) * 0.15;
    displayColor *= 1.0 - shadow;

    let ridge = smoothstep(1.5, 2.5, thickness);
    let ridgeNoise = fract(sin(dot(uv * 50.0, vec2<f32>(12.0, 78.0))) * 43758.0);
    displayColor += vec3<f32>(1.0, 1.0, 0.9) * ridge * ridgeNoise * 0.1;

    // Idea 1 — palette-knife ridge along the thickness gradient
    let knifeLen = length(vec2<f32>(thicknessGradX, thicknessGradY));
    let knifeDir = normalize(vec2<f32>(thicknessGradX, thicknessGradY) + vec2<f32>(0.0001));
    let knifeBand = abs(sin(dot(uv, vec2<f32>(-knifeDir.y, knifeDir.x)) * 90.0));
    let knifeRidge = pow(knifeBand, 6.0) * smoothstep(0.4, 1.8, thickness) * smoothstep(0.15, 1.2, knifeLen);
    displayColor += vec3<f32>(1.0, 0.97, 0.9) * knifeRidge * 0.22 * (1.0 + mids * 0.25);

    // Idea 2 — canvas tooth through thin wash
    let weave = 0.5 + 0.5 * sin(uv.x * 140.0) * sin(uv.y * 140.0);
    let thinWash = 1.0 - smoothstep(0.05, 0.45, thickness);
    displayColor = mix(displayColor, canvasColor * (0.92 + weave * 0.12), thinWash * 0.28);

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));
    thickness *= dryingRate;

    textureStore(dataTextureA, coord, vec4<f32>(pigment, thickness));

    let sourceA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
    let outAlpha = clamp(thickness * 0.3 + knifeRidge * 0.15 + sourceA * 0.1 + treble * 0.03, 0.0, 1.0);
    displayColor = acesToneMap(displayColor);
    textureStore(writeTexture, coord, vec4<f32>(displayColor, outAlpha));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + thickness * 0.04, 0.0, 1.0), 0.0, 0.0, 0.0));
}
