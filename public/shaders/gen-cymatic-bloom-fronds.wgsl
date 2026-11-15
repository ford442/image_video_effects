// ═══════════════════════════════════════════════════════════════════
//  Cymatic Bloom Fronds
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: 2D Chladni (m,n) nodal plate & wind-swaying 3-frond Barnsley rosette; IFS organ differentiation (rachis veins & pinna spore sori)
//  A packing: linear HDR frond/cymatic trail RGB + semantic alpha (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU_CYM: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) {
        s += a * valueNoise(p * f); f *= 2.0; a *= 0.5;
    }
    return s;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let bassEnv = bass;
    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 1.6;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let cymFreq = 2.0 + mids * 4.0 + p2 * 3.0;
    let growthDrive = clamp(0.32 + p1 * 0.50 + bassEnv * (0.24 + p1 * 0.34), 0.0, 1.0);
    let growth = i32(mix(56.0, 120.0, growthDrive));

    var q = uv * (1.55 - p3 * 0.55) - mouse * (0.18 + held * 0.14);
    q += vec2<f32>(sin(time * 0.22 + bassEnv * 1.4), cos(time * 0.17)) * (0.015 + treble * 0.03);
    let warp = (fbm(q * cymFreq + time * 0.12, 4) - 0.5) * (0.06 + treble * 0.09);
    q += vec2<f32>(warp, warp * 0.7);

    // ── Idea 1: 2D Chladni (m, n) nodal plate & coherent 3-frond rosette ──
    // Folds warped space into a graceful 3-frond cymatic rosette swaying in continuous wind
    // (eliminating frame-hash strobing) over a radial-angular Chladni standing-wave plate.
    let rad = length(uv);
    let theta = atan2(uv.y, uv.x);
    let mMode = floor(2.0 + p2 * 4.0);
    let nMode = mMode + 2.0;
    let chladni = cos(theta * mMode + time * 0.25) * sin(rad * cymFreq * 6.2 - time * 1.6)
                - cos(theta * nMode - time * 0.18) * sin(rad * cymFreq * 3.9 + time * 1.1);
    let nodalLine = exp(-abs(chladni) * 13.5) * exp(-rad * 1.15);

    let qLen = length(q);
    let qAng = atan2(q.y, q.x) - 1.5707963;
    let sector = TAU_CYM / 3.0;
    let foldedAng = (fract((qAng + sector * 0.5) / sector) - 0.5) * sector;
    let rosetteQ = vec2<f32>(-sin(foldedAng), cos(foldedAng)) * qLen;

    var clickWave = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ev = u.ripples[ri];
        let age = time - ev.z;
        let liveMask = f32(age >= 0.0 && age < 2.6);
        let safeAge = max(age, 0.0);
        let evCenter = (ev.xy - vec2<f32>(0.5)) * vec2<f32>(res.x / max(res.y, 1.0), 1.0);
        clickWave += liveMask * exp(-abs(length(uv - evCenter) - safeAge * 0.26) * 52.0) * exp(-safeAge * 1.3);
    }

    var col = vec3<f32>(0.01, 0.015, 0.022);
    var density = 0.0;
    var soriDensity = 0.0;
    var z = vec2<f32>(0.0, 0.0);
    let fernScale = 0.095 + p3 * 0.055;

    for (var i = 0; i < growth; i++) {
        let fi = f32(i);
        // Deterministic Barnsley sequence so fronds hold coherent botanical shape across frames
        let r = hash21(vec2<f32>(fi * 1.37, 17.31));
        let zStem  = vec2<f32>(0.0, 0.16 * z.y);
        let curl   = 0.04 + 0.018 * sin(time * 0.85 + z.y * 0.35 + mids * 0.8);
        let zApex  = vec2<f32>(0.85 * z.x + curl * z.y, -curl * z.x + 0.85 * z.y + 1.6);
        let zLeft  = vec2<f32>(0.20 * z.x - 0.26 * z.y, 0.23 * z.x + 0.22 * z.y + 1.6);
        let zRight = vec2<f32>(-0.15 * z.x + 0.28 * z.y, 0.26 * z.x + 0.24 * z.y + 0.44);

        let isStem  = r < 0.01;
        let isApex  = r >= 0.01 && r < 0.86;
        let isLeft  = r >= 0.86 && r < 0.93;
        z = select(zRight, zLeft, isLeft);
        z = select(z, zApex, isApex);
        z = select(z, zStem, isStem);

        let sway = sin(time * (0.9 + mids * 0.4) + z.y * 0.45) * 0.035 * z.y * fernScale;
        let fpPrimary = vec2<f32>(z.x * fernScale + sway, z.y * fernScale - 0.46);
        let fpRosette = vec2<f32>(z.x * fernScale * 0.82 + sway, z.y * fernScale * 0.82 - 0.06);

        let dPrimary = length(q - fpPrimary);
        let dRosette = length(rosetteQ - fpRosette);
        let sigma = 0.00095 + bassEnv * 0.00055;
        let leaf = exp(-dPrimary * dPrimary / sigma) + 0.72 * exp(-dRosette * dRosette / (sigma * 1.15));

        // ── Idea 2: botanical IFS organ differentiation (rachis veins & pinna sori) ──
        let stemMask = f32(isStem);
        let pinnaMask = f32(!isStem && !isApex);
        let hue = fract(fi * 0.004 + mids * 0.2 + z.y * 0.08);
        let bladeCol = mix(vec3<f32>(0.18, 0.86, 0.54), vec3<f32>(0.88, 0.42, 1.0), hue);
        let rachisCol = vec3<f32>(0.32, 0.96, 0.92);
        let soriCol = vec3<f32>(1.15, 0.84, 0.24);
        let organCol = mix(mix(bladeCol, rachisCol, stemMask * 0.75), soriCol, pinnaMask * 0.68);

        let soriPulse = 1.0 + pinnaMask * (0.45 + treble * 0.65 + clickWave * 1.2);
        col += organCol * leaf * (0.58 + treble * 0.35) * soriPulse;
        density += leaf;
        soriDensity += leaf * pinnaMask;
    }

    // Cymatic standing-wave rim + Chladni nodal spore sand
    let rim = abs(sin(rad * cymFreq * 8.0 - time * 2.0)) * exp(-rad * 1.2);
    col += vec3<f32>(0.35, 0.75, 1.0) * rim * (0.14 + mids * 0.24);
    col += mix(vec3<f32>(0.28, 0.88, 0.78), vec3<f32>(1.05, 0.78, 0.36), clamp(treble, 0.0, 1.0))
         * nodalLine * (0.18 + p2 * 0.26 + mids * 0.22 + clickWave * 0.55);
    col += vec3<f32>(0.55, 0.95, 0.82) * clickWave * 0.32;

    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailCol = clamp(mix(prev.rgb * (0.90 - p4 * 0.14), col, 0.26 + p4 * 0.24), vec3<f32>(0.0), vec3<f32>(6.0));
    let alpha = clamp((density * 0.65 + nodalLine * 0.28 + soriDensity * 0.25 + clickWave * 0.22) * (1.0 + bassEnv * 0.35) * (1.0 - depth * 0.38), 0.1, 0.95);
    textureStore(dataTextureA, pixel, vec4<f32>(trailCol, alpha));

    var disp = trailCol * mix(1.0, 0.55, depth);
    disp = hue_preserve_clamp(disp, 1.35);
    disp = aces(max(disp, vec3<f32>(0.0)) * (0.95 + bassEnv * 0.25));
    disp = clamp(disp + vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0), vec3<f32>(0.0), vec3<f32>(1.0));

    let outDepth = clamp(mix(depth, 1.0 - clamp(density * 0.55 + nodalLine * 0.25, 0.0, 0.85), 0.45), 0.0, 1.0);
    textureStore(writeTexture, pixel, vec4<f32>(disp * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
