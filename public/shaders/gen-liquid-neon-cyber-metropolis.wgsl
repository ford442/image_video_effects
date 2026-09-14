// ═══════════════════════════════════════════════════════════════════
//  Liquid-Neon Cyber-Metropolis
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: liquid neon rivers flowing down tower veins; wet-street neon reflections; gravity-warp horizon ring
//  A packing: ACES display RGBA (C read back via exact textureLoad as neon persistence history)
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
    config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Neon Intensity, y=City Density, z=Audio Reactivity, w=Gravity Warp Strength
    ripples: array<vec4<f32>, 50>,
};
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}


// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

fn boxSDF(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

struct MapResult {
    d: f32,
    mat: f32, // 0.0 = concrete, 1.0 = neon
};

fn gravityMousePos() -> vec3<f32> {
    return vec3<f32>(
        (u.zoom_config.y - 0.5) * 20.0,
        0.0,
        (u.zoom_config.z - 0.5) * 20.0
    );
}

// === Gravity Warp (Mouse Interaction) ===
fn gravityWarp(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    let mousePos = gravityMousePos();
    let distToMouse = length(p.xz - mousePos.xz);
    let warpStrength = u.zoom_params.w;
    if (distToMouse < 12.0 && warpStrength > 0.0) {
        let warpAmt = (12.0 - distToMouse) / 12.0;
        let warpDir = normalize(vec3<f32>(p.x - mousePos.x, 0.0, p.z - mousePos.z));
        p.x -= warpDir.x * warpAmt * warpStrength * 6.0;
        p.z -= warpDir.z * warpAmt * warpStrength * 6.0;
    }
    return p;
}

// === City Density & Repetition === (higher slider = denser city; spans the 0-1 slider range,
// default 0.5 keeps HEAD's ~6.5 cell size)
fn cityRepSize() -> f32 {
    return mix(8.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0));
}

fn cityHash(p: vec3<f32>, repSize: f32) -> f32 {
    let cellId = floor((p.xz + repSize * 0.5) / repSize);
    return fract(sin(dot(cellId, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn map(p_in: vec3<f32>) -> MapResult {
    let p = gravityWarp(p_in);

    let repSize = cityRepSize();
    var q = p;
    q.x = (fract(p.x / repSize + 0.5) - 0.5) * repSize;
    q.z = (fract(p.z / repSize + 0.5) - 0.5) * repSize;

    // === Audio Reactivity + Height Variation ===
    let audioAmp = plasmaBuffer[0].x * u.zoom_params.z;
    let hHash = cityHash(p, repSize);
    let baseHeight = 2.5 + hHash * 9.0;
    let animHeight = baseHeight + sin(u.config.x * 2.5 + hHash * 12.0) * audioAmp * 3.5;

    // Base building
    let bSize = vec3<f32>(repSize * 0.36, animHeight, repSize * 0.36);
    var dConcrete = boxSDF(q - vec3<f32>(0.0, animHeight * 0.5, 0.0), bSize);

    // KIFS architectural detail on top
    var kifsP = q - vec3<f32>(0.0, animHeight * 1.8, 0.0);
    for (var i = 0; i < 4; i++) {
        kifsP = abs(kifsP) - vec3<f32>(0.18, 0.55, 0.18);
        let r = rot2D(0.45 + sin(u.config.x * 0.1) * 0.1);
        let kxy = r * kifsP.xy;
        kifsP.x = kxy.x; kifsP.y = kxy.y;
    }
    let dKifs = boxSDF(kifsP, vec3<f32>(0.12, 1.8, 0.12));
    dConcrete = min(dConcrete, dKifs);

    // Neon veins (slightly larger + pulsing)
    let neonSize = vec3<f32>(repSize * 0.39, animHeight * 1.15, repSize * 0.39);
    var dNeon = boxSDF(q - vec3<f32>(0.0, animHeight * 0.5, 0.0), neonSize)
                + 0.08 * sin(q.y * 14.0 - u.config.x * 6.0);

    // Ground plane
    let dFloor = p.y + 0.05;
    dConcrete = smin(dConcrete, dFloor, 0.6);

    // Final result
    var res: MapResult;
    res.d = smin(dConcrete, dNeon, 0.15);

    if (dNeon < dConcrete - 0.03) {
        res.mat = 1.0; // neon
    } else {
        res.mat = 0.0; // concrete
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord - 0.5 * res) / res.y;

    // Camera
    let time = u.config.x;
    let camTime = time * 0.15;
    var ro = vec3<f32>(
        sin(camTime) * 28.0,
        14.0 + sin(time * 0.3) * 3.0,
        cos(camTime) * 28.0 + 8.0
    );

    // Mouse influence on camera
    let mx = (u.zoom_config.y - 0.5) * 12.0;
    let my = (u.zoom_config.z - 0.5) * 8.0;
    ro.x += mx;
    ro.y += my * 0.6;

    let ta = vec3<f32>(mx * 0.6, 3.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.2 * cw);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let bloomCol = mix(vec3<f32>(0.0, 0.85, 1.1), vec3<f32>(1.0, 0.1, 0.9), sin(time * 0.8) * 0.5 + 0.5);

    // Raymarching
    var t = 0.0;
    var hit = false;
    var mat = 0.0;
    var glow = 0.0;
    let maxSteps = 160;
    let maxDist = 120.0;

    for (var i = 0; i < maxSteps; i++) {
        let p = ro + rd * t;
        let resMap = map(p);

        if (resMap.d < 0.001) {
            hit = true;
            mat = resMap.mat;
            break;
        }
        if (t > maxDist) { break; }

        t += resMap.d * 0.75;

        // Neon glow accumulation
        if (resMap.mat > 0.5) {
            glow += 0.012 / (0.08 + abs(resMap.d)) * u.zoom_params.x * (1.0 + treble * 0.3);
        }
    }

    // Shading
    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let wp = gravityWarp(p);
        let repSize = cityRepSize();
        let hHash = cityHash(wp, repSize);
        let qxz = (fract(wp.xz / repSize + 0.5) - 0.5) * repSize;

        let lig = normalize(vec3<f32>(0.6, 1.0, -0.4));
        let dif = max(dot(n, lig), 0.0);
        let amb = 0.12 + 0.88 * max(n.y, 0.0);

        if (mat < 0.5) {
            // Concrete
            col = vec3<f32>(0.045, 0.05, 0.07) * (dif * 0.7 + amb);
            
            // Subtle scanning lines
            let scan = fract(length(p.xz) * 0.08 - time * 3.0);
            if (scan < 0.04) {
                col += vec3<f32>(0.0, 0.4, 0.9) * (0.6 - scan * 15.0);
            }

            let groundMask = (1.0 - smoothstep(0.0, 0.6, p.y)) * smoothstep(0.7, 0.95, n.y);

            // Idea 1 (apron): the neon river pools where each vein meets the street.
            let veinEdge = length(max(abs(qxz) - vec2<f32>(repSize * 0.39), vec2<f32>(0.0)));
            let apronHue = fract(time * 0.25 + hHash);
            let apronCol = mix(vec3<f32>(0.0, 1.0, 1.2), vec3<f32>(1.1, 0.0, 1.1), apronHue);
            col += apronCol * exp(-veinEdge * 3.0) * groundMask * 0.9 * u.zoom_params.x * (1.0 + bass * 0.5);

            // Idea 3: gravity-warp horizon ring — the warp's 12-unit edge glows on the street.
            let mouseDist = length(p.xz - gravityMousePos().xz);
            let ringAngle = atan2(p.z - gravityMousePos().z, p.x - gravityMousePos().x);
            let ringShimmer = 0.7 + 0.3 * sin(ringAngle * 12.0 + time * 3.0) * (0.4 + mids);
            let ring = exp(-abs(mouseDist - 12.0) * 3.0) * groundMask * u.zoom_params.w * ringShimmer;
            col += bloomCol * ring * 1.4;

            // Idea 2: wet-street neon reflections — a short glossy march off the puddled
            // ground re-accumulates the same neon glow term as the primary march.
            let puddle = smoothstep(0.1, 0.6, 0.5 + 0.5 * sin(p.x * 0.43 + 1.3) * sin(p.z * 0.37 - 0.7));
            let wet = groundMask * puddle;
            if (wet > 0.01) {
                let rippleN = normalize(vec3<f32>(
                    sin(p.x * 3.1 + time * 1.7) * 0.03,
                    1.0,
                    cos(p.z * 2.7 - time * 1.3) * 0.03
                ));
                let rrd = reflect(rd, rippleN);
                var rt = 0.1;
                var rglow = 0.0;
                for (var j = 0; j < 40; j++) {
                    let rMap = map(p + vec3<f32>(0.0, 0.06, 0.0) + rrd * rt);
                    if (rMap.d < 0.002 || rt > 40.0) { break; }
                    rglow += select(0.0, 0.012 / (0.08 + abs(rMap.d)), rMap.mat > 0.5);
                    rt += max(rMap.d * 0.8, 0.05);
                }
                col += bloomCol * rglow * 0.1 * u.zoom_params.x * wet;
            }
        } else {
            // Neon
            let hue = fract(p.y * 0.04 + time * 0.25);
            let neonCol = mix(vec3<f32>(0.0, 1.0, 1.2), vec3<f32>(1.1, 0.0, 1.1), hue);
            col = neonCol * (1.8 + sin(time * 8.0 + p.y * 10.0) * 0.6) * u.zoom_params.x;

            // Idea 1: liquid neon rivers — bright packets flow down each tower's vein,
            // per-tower phase from the cell hash, speed lifted by bass.
            let flowPhase = fract(p.y * 0.25 + time * (0.6 + bass * 0.8) + hHash * 7.0);
            let packet = pow(flowPhase, 8.0);
            col += neonCol * packet * 2.5 * u.zoom_params.x;
        }

        // Fake specular reflection
        if (mat < 0.5) {
            let refl = reflect(rd, n);
            let refGlow = max(0.0, dot(refl, vec3<f32>(0.0, 1.0, 0.0))) * 0.35;
            col += vec3<f32>(0.1, 0.7, 1.0) * refGlow * u.zoom_params.x;
        }
    }

    // Global neon bloom
    col += bloomCol * glow * 0.13;

    // Fog
    col = mix(col, vec3<f32>(0.008, 0.012, 0.035), 1.0 - exp(-0.0008 * t * t));

    // Tonemapping + gamma
    col = aces(col);
    col = pow(col, vec3<f32>(0.4545));

    // Neon persistence: bright veins leave a short decaying afterglow from exact colour history.
    let coord = vec2<i32>(id.xy);
    let previous = textureLoad(dataTextureC, coord, 0);
    col = max(col, previous.rgb * 0.3);

    let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let hitMask = select(0.0, 1.0, hit);
    let neonMask = select(0.0, 1.0, hit && mat > 0.5);
    let alpha = clamp(0.15 + hitMask * 0.55 + neonMask * 0.15 + luma * 0.2 + glow * 0.02, 0.0, 1.0);
    let depth = select(1.0, clamp(t / maxDist, 0.0, 0.995), hit);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
