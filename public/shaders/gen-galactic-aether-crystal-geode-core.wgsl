// ----------------------------------------------------------------
// Galactic Aether-Crystal Geode-Core
// Category: generative
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Crystal Density, y=Core Glow, z=Fractal Iterations, w=Gas Density
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Rotation matrix for 2D vectors
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Simple hash for 3D domain
fn hash31(p: vec3<f32>) -> f32 {
    let p1 = fract(p * 0.3183099 + vec3<f32>(0.1, 0.1, 0.1));
    return fract(sin(dot(p1, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453123);
}

// 3D Cellular noise
fn cellular(p: vec3<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var min_dist = 1.0;
    var min_dist2 = 1.0;
    for (var k = -1; k <= 1; k = k + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            for (var l = -1; l <= 1; l = l + 1) {
                let cell = vec3<f32>(f32(k), f32(j), f32(l));
                var h = vec3<f32>(hash31(i + cell), hash31(i + cell + 1.0), hash31(i + cell + 2.0));
                let diff = cell + h - f;
                let d = dot(diff, diff);
                if (d < min_dist) {
                    min_dist2 = min_dist;
                    min_dist = d;
                } else if (d < min_dist2) {
                    min_dist2 = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(min_dist), sqrt(min_dist2));
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// KIFS Fractal for Crystals
fn kifs(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    let iterations = i32(u.zoom_params.z); // Fractal Iterations
    let density = u.zoom_params.x; // Crystal Density
    var scale = 1.0;

    // Rotations based on time for slight dynamic crystal shifting
    let t = u.config.x * 0.1;
    let r2 = rot(t);
    let r3 = rot(t * 1.3);

    for (var i = 0; i < 10; i = i + 1) {
        if (i >= iterations) { break; }
        p = abs(p) - vec3<f32>(0.5 * density) * scale;

        // Apply rot to xy, and xz
        var pxy = p.xy;
        pxy = r2 * pxy;
        p = vec3<f32>(pxy, p.z);

        var pxz = p.xz;
        pxz = r3 * pxz;
        p = vec3<f32>(pxz.x, p.y, pxz.y);

        scale *= 0.5;
    }

    // Distance to a sort of octahedron
    return (abs(p.x) + abs(p.y) + abs(p.z)) - 0.5 * scale;
}

// Map the SDF world
fn map(p: vec3<f32>) -> vec2<f32> {
    let audio = u.config.y;

    // Outer Shell
    let outerSphere = length(p) - 3.5;

    // Cracked opening via cellular noise subtraction
    let cellNoise = cellular(p * 1.5 + vec3<f32>(u.config.x * 0.1));
    let opening = cellNoise.y - cellNoise.x - 0.3;
    let shell = max(outerSphere, -opening);

    // Inner hollow area
    let innerSphere = length(p) - 3.0;
    let crackedGeode = max(shell, -innerSphere);

    // Crystals inside
    let crystalSDF = kifs(p);

    // Core Plasma
    let coreGlowPulsation = sin(u.config.x * 2.0) * 0.2 + audio * 0.5;
    let coreSphere = length(p) - (1.2 + coreGlowPulsation);

    // Add some noise to the core
    let coreNoise = cellular(p * 3.0 - vec3<f32>(u.config.x)).x;
    let plasmaCore = coreSphere + coreNoise * 0.3;

    // We return vec2: x is distance, y is material ID
    // Mat 1: Shell, Mat 2: Crystals, Mat 3: Plasma Core

    var d = crackedGeode;
    var matId = 1.0;

    if (crystalSDF < d && innerSphere < 0.0) { // Crystals only inside
        d = smin(d, crystalSDF, 0.2); // Blend slightly with shell
        matId = 2.0;
    }

    if (plasmaCore < d) {
        d = plasmaCore;
        matId = 3.0;
    }

    return vec2<f32>(d, matId);
}

// Calculate Normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv = (fragCoord - 0.5 * res) / res.y;

    // Mouse Interaction
    let mx = (u.zoom_config.y / res.x) * 2.0 - 1.0;
    let my = (u.zoom_config.z / res.y) * 2.0 - 1.0;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -8.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Rotations based on time and mouse
    let rotX = rot(my * 3.14 + u.config.x * 0.1);
    let rotY = rot(mx * 3.14 + u.config.x * 0.2);

    // Apply rotations
    var roYZ = ro.yz; roYZ = rotX * roYZ; ro = vec3<f32>(ro.x, roYZ.x, roYZ.y);
    var roXZ = ro.xz; roXZ = rotY * roXZ; ro = vec3<f32>(roXZ.x, ro.y, roXZ.y);

    var rdYZ = rd.yz; rdYZ = rotX * rdYZ; rd = vec3<f32>(rd.x, rdYZ.x, rdYZ.y);
    var rdXZ = rd.xz; rdXZ = rotY * rdXZ; rd = vec3<f32>(rdXZ.x, rd.y, rdXZ.y);

    var t = 0.0;
    var d: vec2<f32> = vec2<f32>(0.0, 0.0);
    var p = ro;

    var volLight = 0.0; // Volumetric scattering accumulation

    // Raymarching Loop
    for (var i = 0; i < 100; i = i + 1) {
        p = ro + rd * t;
        d = map(p);

        // Volumetric accumulation for quantum gas (w = Gas Density)
        if (length(p) < 3.0) {
           volLight += (0.01 * u.zoom_params.w) / (1.0 + abs(d.x));
        }

        if (d.x < 0.001 || t > 20.0) { break; }
        t += d.x * 0.7; // slight step back for complex KIFS and cellular
    }

    var col = vec3<f32>(0.0);

    if (t < 20.0) {
        let n = calcNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(-rd);
        let refl = reflect(-lightDir, n);
        let spec = pow(max(dot(viewDir, refl), 0.0), 32.0);

        // Core Glow Param (y)
        let coreGlowIntensity = u.zoom_params.y;
        let audio = u.config.y;

        if (d.y == 1.0) {
            // Shell
            col = vec3<f32>(0.1, 0.12, 0.15) * diff + spec * 0.2;

            // Subsurface glow from inside
            let innerDist = length(p) - 3.0;
            if (innerDist < 0.5) {
                col += vec3<f32>(0.5, 0.1, 0.8) * (0.5 - innerDist) * coreGlowIntensity;
            }

        } else if (d.y == 2.0) {
            // Crystals (Chrono-glass)
            let refractDir = refract(rd, n, 0.9);
            // Fake chromatic aberration for refraction
            let chrR = max(0.0, map(p + refractDir * 0.1).x);
            let chrG = max(0.0, map(p + refractDir * 0.2).x);
            let chrB = max(0.0, map(p + refractDir * 0.3).x);

            col = vec3<f32>(chrR, chrG, chrB) * 0.5 + spec * vec3<f32>(1.0, 0.8, 1.0);

            // Crystal glowing edges
            col += vec3<f32>(0.1, 0.8, 0.9) * pow(1.0 - max(dot(n, viewDir), 0.0), 4.0) * coreGlowIntensity * 0.5;

        } else if (d.y == 3.0) {
            // Plasma Core
            let plasmaColor1 = vec3<f32>(0.9, 0.1, 0.5); // Deep Magenta
            let plasmaColor2 = vec3<f32>(0.1, 0.9, 0.9); // Cyan

            // Audio reactivity
            let mixFactor = sin(length(p) * 5.0 - u.config.x * 5.0) * 0.5 + 0.5;
            col = mix(plasmaColor1, plasmaColor2, mixFactor) * coreGlowIntensity * (1.0 + audio * 2.0);
            col += vec3<f32>(1.0) * spec; // core highlights
        }
    }

    // Add volumetric fog/gas
    let gasColor = vec3<f32>(0.2, 0.5, 0.9);
    col += gasColor * volLight * u.zoom_params.w;

    // Background starlight warp
    if (t >= 20.0) {
       let bgNoise = cellular(rd * 20.0).x;
       if(bgNoise < 0.1) {
           col = vec3<f32>(pow(1.0 - bgNoise * 10.0, 5.0));
       }
    }

    // Tone mapping and gamma
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
