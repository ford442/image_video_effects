// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Fracture Spread, y=Levitation Speed, z=Glow Intensity, w=Rotation Speed
    ripples: array<vec4<f32>, 50>,
};

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Basic 3D Noise for fracture displacement
fn noise(p: vec3<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    var res = mix(
        mix(mix(hash31(i + vec3<f32>(0.0, 0.0, 0.0)), hash31(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 0.0)), hash31(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(hash31(i + vec3<f32>(0.0, 0.0, 1.0)), hash31(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 1.0)), hash31(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z
    );
    return res;
}

// --- SDFs ---

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
    return dot(p, n) + h;
}

// --- Map Function ---
// Returns vec3: x = distance, y = material ID, z = glow accumulation
fn map(p: vec3<f32>) -> vec3<f32> {
    var d = 1000.0;
    var mat = 0.0;
    var glow = 0.0;

    let time = u.config.x;
    let spread = u.zoom_params.x * 2.0;
    let levSpeed = u.zoom_params.y;
    let rotSpeed = u.zoom_params.w;

    // --- Liquid Terrain ---
    // Smooth wavy floor
    let wave = sin(p.x * 0.5 + time * 0.5) * cos(p.z * 0.5 + time * 0.3) * 0.2;
    let floorDist = sdPlane(p, vec3<f32>(0.0, 1.0, 0.0), 2.0) + wave;
    if (floorDist < d) {
        d = floorDist;
        mat = 1.0; // Floor material
    }

    // --- Monolith ---
    var bp = p;
    // Levitation bobbing
    bp.y -= sin(time * levSpeed) * 0.5 + 2.0;
    // Slow global rotation
    let temp_bp_xz = rot(time * 0.2 * rotSpeed) * bp.xz;
    bp.x = temp_bp_xz.x;
    bp.z = temp_bp_xz.y;


    // Base shape: Tall box
    let baseBox = sdBox(bp, vec3<f32>(1.5, 4.0, 1.5));

    // Fracturing using noise-displaced planes
    // We simulate fracturing by expanding space based on a cellular-like grid
    let cellSize = 1.5;
    let cellId = floor(bp / cellSize);
    let cellCenter = (cellId + 0.5) * cellSize;

    // Drift fragments away from center based on cell ID
    let drift = (hash31(cellId) - 0.5) * spread;
    var fp = bp;
    var dir = normalize(cellCenter + vec3<f32>(0.001));
    fp -= dir * drift * (1.0 + sin(time * 0.5 + hash31(cellId)*10.0) * 0.2);

    // Individual piece rotation
    let localRot = (hash31(cellId + vec3<f32>(1.0)) - 0.5) * time * rotSpeed;
    let temp_fp_xz = rot(localRot) * fp.xz;
    fp.x = temp_fp_xz.x;
    fp.z = temp_fp_xz.y;

    let temp_fp_xy = rot(localRot * 0.5) * fp.xy;
    fp.x = temp_fp_xy.x;
    fp.y = temp_fp_xy.y;


    // Carve out cracks
    let crackNoise = noise(bp * 3.0);
    let shardDist = max(baseBox, sdBox(fp - cellCenter, vec3<f32>(cellSize * 0.45)) - crackNoise * 0.1);

    // The monolith surface
    if (shardDist < d) {
        d = shardDist;
        mat = 2.0; // Monolith material
    }

    // Inner Glow accumulation in cracks
    // When inside the bounding box but outside shards
    if (baseBox < 0.5 && shardDist > 0.05) {
        glow += 0.01 / (0.01 + abs(shardDist)) * u.zoom_params.z;
    }

    return vec3<f32>(d, mat, glow);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    var uv = (fragCoord * 2.0 - dims) / dims.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, 12.0);
    // Mouse interaction for camera orbit
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;

    let temp_ro_yz = rot(mouseY * 1.0) * ro.yz;
    ro.y = temp_ro_yz.x;
    ro.z = temp_ro_yz.y;

    let temp_ro_xz = rot(mouseX * 3.14) * ro.xz;
    ro.x = temp_ro_xz.x;
    ro.z = temp_ro_xz.y;


    let ta = vec3<f32>(0.0, 2.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.2 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    var accumGlow = 0.0;

    for (var i = 0; i < 120; i++) {
        var p = ro + rd * t;
        var res = map(p);
        d = res.x;
        m = res.y;
        accumGlow += res.z;

        if (d < 0.001 || t > 30.0) { break; }
        t += d * 0.8; // Reduce step size for better glow accumulation and fracture detail
    }

    var col = vec3<f32>(0.02, 0.02, 0.03); // Dark background sky
    // Add subtle gradient to sky
    col += vec3<f32>(0.05, 0.1, 0.2) * max(0.0, rd.y);

    if (t < 30.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let dif = max(dot(n, lig), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

        if (m == 1.0) {
            // Liquid Floor
            let ref = reflect(rd, n);
            // Fake reflections by stepping once into the reflection direction
            let refRes = map(p + ref * 2.0);
            var refCol = vec3<f32>(0.02, 0.03, 0.05);
            if (refRes.y == 2.0) {
                refCol = vec3<f32>(0.1, 0.1, 0.12);
            }
            col = mix(vec3<f32>(0.0, 0.05, 0.1) * dif, refCol, fre * 0.8 + 0.2);
        } else if (m == 2.0) {
            // Monolith Material
            var matCol = vec3<f32>(0.05, 0.05, 0.06);
            col = matCol * dif + fre * vec3<f32>(0.1, 0.2, 0.3);
        }
    }

    // Add Core Glow
    let glowColor = vec3<f32>(0.1, 0.5, 1.0); // Cyan/Blue glow
    col += accumGlow * glowColor * 0.02;

    // Subtle vignette
    col *= 1.0 - 0.3 * length(uv);

    // Tone mapping and gamma correction
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
