// ═══════════════════════════════════════════════════════════════════
//  spec-hypercube-projection
//  Category: geometric
//  Features: 4D, hypercube, tesseract, projection, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-10
//  Ideas: W-silhouette on inner-cube edges; photo sampled at closest-edge h;
//         24 projected square faces stacked as glass; perspective vertex nodes;
//         W-parallax refraction through faces
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn project4DTo2D(p: vec4<f32>, camW: f32) -> vec2<f32> {
    let perspective = 1.5 / (camW - p.w);
    return p.xy * perspective;
}

fn cross2(a: vec2<f32>, b: vec2<f32>) -> f32 { return a.x * b.y - a.y * b.x; }

// Idea: point-in-projected-face test. Squares stay convex under the 4D
// perspective; a pixel is inside when all four edge crosses share a sign.
fn insideQuad(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> bool {
    let s0 = cross2(b - a, p - a);
    let s1 = cross2(c - b, p - b);
    let s2 = cross2(d - c, p - c);
    let s3 = cross2(a - d, p - d);
    let allPos = s0 >= 0.0 && s1 >= 0.0 && s2 >= 0.0 && s3 >= 0.0;
    let allNeg = s0 <= 0.0 && s1 <= 0.0 && s2 <= 0.0 && s3 <= 0.0;
    return allPos || allNeg;
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

    // mids breathe the 4D camera distance (inner cube swells on mids)
    let camW = 2.5 - mids * 0.35;
    var verts2D = array<vec2<f32>, 16>();
    var depths = array<f32, 16>();
    var bbMin = vec2<f32>(1e3);
    var bbMax = vec2<f32>(-1e3);
    let angXW = time * rotSpeedXW + extraRot;
    let angYZ = time * rotSpeedYZ * 0.7;
    let angXY = time * 0.15;

    for (var i = 0; i < 16; i = i + 1) {
        var v = verts4D[i];
        v = rotate4D_XW(v, angXW);
        v = rotate4D_YZ(v, angYZ);
        v = rotate4D_XY(v, angXY);
        verts2D[i] = project4DTo2D(v, camW);
        depths[i] = v.w;
        bbMin = min(bbMin, verts2D[i]);
        bbMax = max(bbMax, verts2D[i]);
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

    // Idea: 24 square faces. Vertex index bits: x=8, y=4, z=2, w=1. A face is
    // a base vertex with two clear axis bits, walked b -> b|ma -> b|ma|mb -> b|mb.
    var faceCount = 0.0;
    var faceW = 0.0;
    var faceShift = vec2<f32>(0.0);
    let axisA = array<i32, 6>(8, 8, 8, 4, 4, 2);
    let axisB = array<i32, 6>(4, 2, 1, 2, 1, 1);
    // Faces and nodes live inside the projected bounding box (+ node radius).
    let bbPad = edgeGlow * 6.0;
    let inBox = all(screenUV >= bbMin - bbPad) && all(screenUV <= bbMax + bbPad);
    for (var b = 0; b < select(0, 16, inBox); b = b + 1) {
        for (var k = 0; k < 6; k = k + 1) {
            let ma = axisA[k];
            let mb = axisB[k];
            if ((b & ma) != 0 || (b & mb) != 0) { continue; }
            let p0 = verts2D[b];
            let p1 = verts2D[b | ma];
            let p2 = verts2D[b | ma | mb];
            let p3 = verts2D[b | mb];
            if (insideQuad(screenUV, p0, p1, p2, p3)) {
                let fw = (depths[b] + depths[b | ma] + depths[b | ma | mb] + depths[b | mb]) * 0.25;
                faceCount = faceCount + 1.0;
                faceW = faceW + fw;
                // Idea: W-parallax refraction — each face bends the view toward
                // its centroid by its mean w (inner cell pulls, outer pushes).
                let centroid = (p0 + p1 + p2 + p3) * 0.25;
                faceShift = faceShift + (centroid - screenUV) * fw * 0.55;
            }
        }
    }
    let meanFaceW = faceW / max(faceCount, 1.0);
    let refractUV = clamp(uv + faceShift * 4.0 * faceOpacity / 0.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let src = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);
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

    // Faces stack as translucent glass: each covering face adds one layer.
    let layerA = faceOpacity * 0.55;
    let faceFill = (1.0 - pow(1.0 - layerA, faceCount)) * (1.0 - glow * 0.5);
    let faceHue = meanFaceW * 0.6 + time * 0.05 + 0.5;
    let faceTint = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (faceHue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (faceHue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (faceHue + 0.67))
    );
    let faceTintMix = mix(faceTint, vec3<f32>(0.35, 0.7, 1.0), smoothstep(0.0, -0.3, meanFaceW) * 0.5);

    // Idea: vertex nodes — 16 projected vertices as glints sized by 4D
    // perspective (inner w=-1 cell far, outer near), treble sparkles them.
    var nodeGlow = 0.0;
    for (var i = 0; i < select(0, 16, inBox); i = i + 1) {
        let persp = 1.5 / (camW - depths[i]);
        let r = edgeGlow * (1.6 + persp * 2.0);
        let d = length(screenUV - verts2D[i]);
        let flick = 0.8 + 0.2 * sin(time * 9.0 + f32(i) * 2.3) + treble * 0.6;
        nodeGlow = max(nodeGlow, exp(-d * d / (r * r)) * persp * flick);
    }

    var outColor = src.rgb * (1.0 - faceFill) + src.rgb * faceTintMix * 1.25 * faceFill;
    outColor = outColor + mix(edgeColor, edgePhoto, 0.55) * glow * depthFade * 2.0 * (1.0 + bass * 0.2);

    outColor = outColor + vec3<f32>(1.0, 0.97, 0.9) * nodeGlow * 1.8;

    let alpha = clamp(src.a * 0.35 + glow * depthFade + faceFill * 0.4 + nodeGlow * 0.5, 0.0, 1.0);
    let out4 = vec4<f32>(acesToneMap(outColor), alpha);

    textureStore(writeTexture, gid.xy, out4);
    textureStore(dataTextureA, gid.xy, out4);
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(clamp(depth_in + glow * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
