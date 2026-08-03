// ----------------------------------------------------------------
// Quantum-Acoustic Bioluminescent Void-Urchin
// Category: generative
// Upgraded 2026-08-03 (batch b31, algorithmist):
//   - CRITICAL FIX: canonical Uniforms struct (config/zoom_config/zoom_params/ripples)
//   - Full 3D SDF library + gyroscopic torus rings + octahedron quantum cage (matIDs 3/4)
//   - 2D geometric layer: hex-tessellated membrane shimmer + kaleidoscopic void backdrop
//   - Adaptive raymarch step count, real depth, semantic alpha, dataTextureA output
// ----------------------------------------------------------------
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── 3D SDF library ───
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdOctahedron(p_in: vec3<f32>, s: f32) -> f32 {
    let p = abs(p_in);
    return (p.x + p.y + p.z - s) * 0.57735027;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ─── 2D geometric library ───
fn mod2(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return a - b * floor(a / b);
}

fn hexDist(p: vec2<f32>) -> f32 {
    let q = abs(p);
    return max(dot(q, normalize(vec2<f32>(1.0, 1.7320508))), q.x);
}

// returns vec4(local_xy, cell_id_xy) of nearest hex cell
fn hexCell(p: vec2<f32>) -> vec4<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let a = mod2(p, r) - h;
    let b = mod2(p - h, r) - h;
    let gv = select(b, a, dot(a, a) < dot(b, b));
    return vec4<f32>(gv, p - gv);
}

// kaleidoscopic symmetry fold
fn kaleido(p: vec2<f32>, folds: f32) -> vec2<f32> {
    let r = length(p);
    var a = atan2(p.y, p.x);
    let seg = TAU / folds;
    a = fract(a / seg) * seg;
    a = abs(a - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise3D(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let fs = f * f * (3.0 - 2.0 * f);
    let n = p.x + p.y * 57.0 + 113.0 * p.z;
    return mix(mix(mix(fract(sin(n) * 43758.5453), fract(sin(n + 1.0) * 43758.5453), fs.x),
                   mix(fract(sin(n + 57.0) * 43758.5453), fract(sin(n + 58.0) * 43758.5453), fs.x), fs.y),
               mix(mix(fract(sin(n + 113.0) * 43758.5453), fract(sin(n + 114.0) * 43758.5453), fs.x),
                   mix(fract(sin(n + 170.0) * 43758.5453), fract(sin(n + 171.0) * 43758.5453), fs.x), fs.y), fs.z);
}

fn map(p_in: vec3<f32>) -> vec2<f32> { // returns vec2(dist, material_id)
    var p = p_in;

    // Sliders
    let density = u.zoom_params.x * 2.0 + 0.5; // Spine Density and Length (0.5->2.5)
    let audioMult = u.zoom_params.y * 2.0;     // Audio Reactivity Multiplier
    let voidFluid = u.zoom_params.w;           // Void Fluidity / Distortion

    let time = u.config.x;
    let audioBase = plasmaBuffer[0].x * audioMult;
    let treble = plasmaBuffer[0].z * audioMult;

    // Fluid Void Distortion
    let warpTime = time * 0.2;
    p += vec3<f32>(
        noise3D(p * 0.5 + vec3<f32>(warpTime, 0.0, 0.0)),
        noise3D(p * 0.5 + vec3<f32>(0.0, warpTime, 0.0)),
        noise3D(p * 0.5 + vec3<f32>(0.0, 0.0, warpTime))
    ) * voidFluid * 0.5;

    // Mouse Interaction (Bend spines towards mouse) — mouse_uv is 0-1, y=0 top
    let mUv = u.zoom_config.yz;
    let mouse3D = vec3<f32>((mUv.x - 0.5) * 6.0, (0.5 - mUv.y) * 6.0, 0.0);
    let distToMouse = length(p - mouse3D);
    let bendForce = (1.0 - smoothstep(0.0, 3.0, distToMouse)) * 1.5;
    if (distToMouse > 1e-4 && distToMouse < 3.0) {
        let dir = (mouse3D - p) / distToMouse;
        p += dir * bendForce * 0.3;
    }

    // Core sphere
    let coreRadius = 1.0 + audioBase * 0.2 + noise3D(p * 2.0 + time) * 0.1;
    let coreSDF = sdSphere(p, coreRadius);

    // Spines (Polar repetition)
    let radius = length(p);
    let theta = acos(clamp(p.y / max(radius, 1e-4), -1.0, 1.0));
    let phi = atan2(p.z, p.x);

    let polarReps = 10.0 * density;
    let polarGridTheta = floor(theta * polarReps / PI);
    let polarGridPhi = floor(phi * polarReps / TAU);

    let noiseVal = noise3D(vec3<f32>(polarGridTheta, polarGridPhi, time * 0.1));
    let spineLength = 1.5 + noiseVal * 1.0 + audioBase * 1.5;

    // Local spine coordinates
    let localTheta = fract(theta * polarReps / PI) * PI / polarReps - PI / (2.0 * polarReps);
    let localPhi = fract(phi * polarReps / TAU) * TAU / polarReps - PI / polarReps;

    let localP = vec3<f32>(radius * sin(localTheta) * cos(localPhi),
                           radius * cos(localTheta),
                           radius * sin(localTheta) * sin(localPhi));

    // Spine SDF (Cone-like capsule tip)
    let spineRadius = 0.1 * (1.0 - smoothstep(1.0, spineLength, radius));
    let spineSDF = length(localP.xz) - spineRadius;
    var spineBound = max(spineSDF, radius - spineLength);
    // Geometric tip: tiny octahedron crowning each spine
    let tipP = localP - vec3<f32>(0.0, spineLength, 0.0);
    spineBound = smin(spineBound, sdOctahedron(tipP, 0.08 + treble * 0.05), 0.05);

    // Membrane webbing
    let memNoise = noise3D(p * 3.0 - vec3<f32>(0.0, time * 0.5, 0.0)) * 0.2;
    let membraneSDF = sdSphere(p, 1.2 + audioBase * 0.3 + memNoise);

    // Combine core, spines, and membrane
    let bodySDF = smin(coreSDF, spineBound, 0.5);
    let urchinSDF = smin(bodySDF, membraneSDF, 0.3);

    // Gyroscopic plasma torus rings orbiting the core (matID 3)
    let ringSpin = time * 0.4;
    let ringR = 2.3 + audioBase * 0.4;
    let pR1 = rotX(ringSpin) * p;
    let pR2 = rotY(ringSpin * 0.7 + 1.3) * rotX(1.1) * p;
    let ringTube = 0.03 + treble * 0.03 + voidFluid * 0.02;
    var ringSDF = sdTorus(pR1, vec2<f32>(ringR, ringTube));
    ringSDF = min(ringSDF, sdTorus(pR2, vec2<f32>(ringR * 0.82, ringTube)));

    // Octahedron quantum cage: 8 shards at cube corners, treble-driven scale (matID 4)
    let cageSpin = rotY(time * 0.25) * p;
    let corner = sign(cageSpin + vec3<f32>(1e-5)) * 1.9; // fold to one octant
    let cageP = abs(cageSpin) - abs(corner);
    let cageSDF = sdOctahedron(cageP, 0.16 + treble * 0.1);

    // Gravitational Plankton (matID 2)
    let planktonScale = 4.0;
    let plP = p * planktonScale + vec3<f32>(time, -time * 0.5, time * 0.2);
    let plID = floor(plP);
    let plLocal = fract(plP) - 0.5;
    let h = hash33(plID);
    var plSDF = sdSphere(plLocal, 0.05 * h.x);
    plSDF /= planktonScale;

    // Plankton repulsion by audio
    let distToCore = length(p);
    if (distToCore < 2.5 + audioBase) {
        plSDF += 0.2 * (2.5 + audioBase - distToCore);
    }

    // Material resolve: 1 = urchin, 2 = plankton, 3 = rings, 4 = cage
    var res = vec2<f32>(urchinSDF, 1.0);
    if (plSDF < res.x) { res = vec2<f32>(plSDF, 2.0); }
    if (ringSDF < res.x) { res = vec2<f32>(ringSDF, 3.0); }
    if (cageSDF < res.x) { res = vec2<f32>(cageSDF, 4.0); }
    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.005;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    // bounds guard — mandatory
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    var uv = (vec2<f32>(pixel) - 0.5 * res) / min(res.x, res.y);

    let time = u.config.x;
    let audioBase = plasmaBuffer[0].x * u.zoom_params.y * 2.0;
    let colorShift = u.zoom_params.z;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, 6.0 - audioBase * 0.5);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Mouse rotation (mouse_uv 0-1, y=0 top; centered for orbit control)
    let mC = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
    let rotXMat = rotX(mC.y * PI);
    let rotYMat = rotY(-mC.x * PI + time * 0.2);
    ro = rotXMat * rotYMat * ro;
    rd = rotXMat * rotYMat * rd;

    // Raymarching — adaptive step count: more steps when audio pumps the geometry
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);

    let maxSteps = 80 + min(i32(audioBase * 30.0), 40);
    let maxDist = 20.0;
    let surfDist = 0.001;

    var hit = false;
    var matID = 0.0;
    var p = vec3<f32>(0.0);

    for (var i = 0; i < maxSteps; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d.x < surfDist) { hit = true; matID = d.y; break; }
        if (t > maxDist) { break; }
        t += d.x;

        // Volumetric glow accumulation
        if (d.y == 1.0) { // Glow from urchin
            let glowCol = mix(vec3<f32>(0.1, 0.0, 0.5), vec3<f32>(0.0, 0.8, 0.8), colorShift);
            glow += glowCol * (0.01 / (1.0 + d.x * d.x * 20.0)) * (1.0 + audioBase * 2.0);
        } else if (d.y == 2.0) { // Glow from plankton
            glow += vec3<f32>(1.0, 0.8, 0.2) * (0.005 / (1.0 + d.x * d.x * 50.0));
        } else if (d.y == 3.0) { // Gyro ring glow
            glow += mix(vec3<f32>(0.2, 0.5, 1.0), vec3<f32>(1.0, 0.3, 0.8), colorShift)
                    * (0.008 / (1.0 + d.x * d.x * 60.0)) * (1.0 + audioBase);
        } else if (d.y == 4.0) { // Quantum cage sparkle
            glow += vec3<f32>(0.6, 0.9, 1.0) * (0.006 / (1.0 + d.x * d.x * 80.0));
        }
    }

    if (hit) {
        let n = calcNormal(p);
        let v = -rd;

        let lightDir = normalize(vec3<f32>(1.0, 2.0, 1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        if (matID == 1.0) { // Urchin Material
            let baseColor = mix(vec3<f32>(0.05, 0.0, 0.2), vec3<f32>(0.0, 0.3, 0.4), clamp(length(p) * 0.2, 0.0, 1.0));
            let emitColor = mix(vec3<f32>(0.1, 0.0, 0.5), vec3<f32>(0.0, 0.9, 0.7), colorShift);

            // Hex-tessellated bioluminescent membrane pattern (2D geometric layer)
            let sphUV = vec2<f32>(atan2(p.z, p.x) / PI, p.y * 0.5) * 6.0;
            let hc = hexCell(sphUV + vec2<f32>(time * 0.1, 0.0));
            let hexEdge = smoothstep(0.42, 0.5, hexDist(hc.xy));
            let hexPulse = 0.5 + 0.5 * sin(time * 2.0 + dot(hc.zw, vec2<f32>(1.7, 2.3)));

            // Bioluminescence
            let lum = smoothstep(0.5, 2.5, length(p)) * (0.5 + audioBase);
            var emit = emitColor * lum + fresnel * vec3<f32>(0.5, 1.0, 1.0);
            emit += emitColor * hexEdge * hexPulse * (0.3 + audioBase * 0.5);

            col = baseColor * (diff * 0.5 + 0.5) + emit;

        } else if (matID == 2.0) { // Plankton Material
            col = vec3<f32>(1.0, 0.9, 0.3) * (1.0 + audioBase * 2.0);
        } else if (matID == 3.0) { // Gyro ring — emissive plasma conduit
            let ringCol = mix(vec3<f32>(0.2, 0.5, 1.0), vec3<f32>(1.0, 0.3, 0.8), colorShift);
            col = ringCol * (diff * 0.3 + 0.7) * (1.2 + audioBase) + fresnel * ringCol;
        } else if (matID == 4.0) { // Quantum cage — crystalline shard
            let cageCol = mix(vec3<f32>(0.4, 0.8, 1.0), vec3<f32>(0.8, 0.4, 1.0), colorShift);
            col = cageCol * (diff * 0.6 + 0.4) + fresnel * vec3<f32>(0.9, 1.0, 1.0) * 0.8;
        }

        // Soft shadows / Subsurface faux
        let ao = clamp(map(p + n * 0.1).x / 0.1, 0.0, 1.0);
        col *= ao;
    } else {
        // Kaleidoscopic void backdrop: folded hex tessellation drifting in zero-g (2D layer)
        let kFolds = 6.0 + floor(u.zoom_params.w * 6.0); // Void Fluidity also drives fold count
        let kUV = kaleido(uv * (1.5 + 0.3 * sin(time * 0.1)), kFolds);
        let hcBg = hexCell(kUV * 5.0 + vec2<f32>(0.0, time * 0.05));
        let bgEdge = smoothstep(0.46, 0.5, hexDist(hcBg.xy));
        let bgCol = mix(vec3<f32>(0.02, 0.0, 0.06), vec3<f32>(0.0, 0.08, 0.1), colorShift);
        col += bgCol * (0.4 + bgEdge * (0.3 + audioBase * 0.4));
    }

    // Add volumetric glow
    col += glow;

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    // Real depth: near surface on hit, far void on miss
    let depth = select(0.0, clamp(1.0 - t / maxDist, 0.0, 1.0), hit);

    // Semantic alpha from luma
    let luma = dot(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + 0.2, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
