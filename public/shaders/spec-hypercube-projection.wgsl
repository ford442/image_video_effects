// ═══════════════════════════════════════════════════════════════════
//  spec-hypercube-projection
//  Category: geometric
//  Features: 4D, hypercube, tesseract, projection, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-10
//  Ideas: W-silhouette on inner-cube edges; photo sampled at closest-edge h
//  A packing: ACES display RGBA
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotate4D_XW(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(c*p.x + s*p.w, p.y, p.z, -s*p.x + c*p.w);
}

fn rotate4D_YZ(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(p.x, c*p.y + s*p.z, -s*p.y + c*p.z, p.w);
}

fn rotate4D_XY(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(c*p.x - s*p.y, s*p.x + c*p.y, p.z, p.w);
}

fn project4DTo2D(p: vec4<f32>) -> vec2<f32> {
    let perspective = 1.5 / (2.5 - p.w);
    return p.xy * perspective;
}

fn lineSDF(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return vec2<f32>(length(pa - ba * h), h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let rotSpeedXW = mix(0.1, 1.0, u.zoom_params.x);
    let rotSpeedYZ = mix(0.05, 0.8, u.zoom_params.y);
    let edgeGlow = mix(0.002, 0.015, u.zoom_params.z);
    let faceOpacity = mix(0.0, 0.6, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    var extraRot = 0.0;
    if (isMouseDown) {
        extraRot = (mousePos.x - 0.5) * 2.0;
    }

    var verts4D = array<vec4<f32>, 16>();
    var idx = 0;
    for (var x = -1; x <= 1; x = x + 2) {
        for (var y = -1; y <= 1; y = y + 2) {
            for (var z = -1; z <= 1; z = z + 2) {
                for (var w = -1; w <= 1; w = w + 2) {
                    verts4D[idx] = vec4<f32>(f32(x), f32(y), f32(z), f32(w)) * 0.35;
                    idx = idx + 1;
                }
            }
        }
    }

    var verts2D = array<vec2<f32>, 16>();
    var depths = array<f32, 16>();
    let angXW = time * rotSpeedXW + extraRot;
    let angYZ = time * rotSpeedYZ * 0.7;
    let angXY = time * 0.15;

    for (var i = 0; i < 16; i = i + 1) {
        var v = verts4D[i];
        v = rotate4D_XW(v, angXW);
        v = rotate4D_YZ(v, angYZ);
        v = rotate4D_XY(v, angXY);
        verts2D[i] = project4DTo2D(v);
        depths[i] = v.w;
    }

    let screenUV = (uv - 0.5) * 2.0;

    var minEdgeDist = 1000.0;
    var edgeDepth = 0.0;
    var edgeH = 0.0;
    var wEdge = 0.0;
    var edgeA = vec2<f32>(0.0);
    var edgeB = vec2<f32>(0.0);

    for (var i = 0; i < 16; i = i + 1) {
        for (var j = i + 1; j < 16; j = j + 1) {
            let diff = abs(verts4D[i] - verts4D[j]);
            var diffs = 0;
            if (diff.x > 0.1) { diffs = diffs + 1; }
            if (diff.y > 0.1) { diffs = diffs + 1; }
            if (diff.z > 0.1) { diffs = diffs + 1; }
            if (diff.w > 0.1) { diffs = diffs + 1; }

            if (diffs == 1) {
                let hit = lineSDF(screenUV, verts2D[i], verts2D[j]);
                if (hit.x < minEdgeDist) {
                    minEdgeDist = hit.x;
                    edgeDepth = (depths[i] + depths[j]) * 0.5;
                    edgeH = hit.y;
                    wEdge = step(0.1, diff.w);
                    edgeA = verts2D[i];
                    edgeB = verts2D[j];
                }
            }
        }
    }

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let wireUV = clamp(mix(edgeA, edgeB, edgeH) * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let edgePhoto = textureSampleLevel(readTexture, u_sampler, wireUV, 0.0).rgb;

    let wBoost = mix(1.0, 1.85 + treble * 0.35, wEdge);
    let glow = exp(-minEdgeDist * minEdgeDist / max(edgeGlow * edgeGlow / wBoost, 1e-8));
    let depthFade = 1.0 - smoothstep(-0.5, 0.5, edgeDepth);

    let edgeHue = edgeDepth * 0.3 + time * 0.05 + wEdge * 0.18;
    var edgeColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (edgeHue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (edgeHue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (edgeHue + 0.67))
    );
    edgeColor = mix(edgeColor, vec3<f32>(0.35, 0.7, 1.0), wEdge * 0.55);

    let center2D = project4DTo2D(vec4<f32>(0.0));
    let distFromCenter = length(screenUV - center2D);
    let faceFill = smoothstep(0.7, 0.3, distFromCenter) * faceOpacity * (1.0 - glow * 0.5);

    var outColor = src.rgb * (1.0 - faceFill) + src.rgb * edgeColor * faceFill;
    outColor = outColor + mix(edgeColor, edgePhoto, 0.55) * glow * depthFade * 2.0 * (1.0 + bass * 0.2);

    let alpha = clamp(src.a * 0.35 + glow * depthFade + faceFill * 0.4, 0.0, 1.0);
    let out4 = vec4<f32>(acesToneMap(outColor), alpha);

    textureStore(writeTexture, gid.xy, out4);
    textureStore(dataTextureA, gid.xy, out4);
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(clamp(depth_in + glow * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
