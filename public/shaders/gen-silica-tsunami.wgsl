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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Wave Height, y=Glass Refraction, z=Particle Density, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

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

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Global parameters for the map function
var<private> g_time: f32;
var<private> g_mouse: vec2<f32>;
var<private> g_audio: f32;

// Returns distance and material (x=dist, y=mat, z=accumulated interior light)
fn map(p: vec3<f32>) -> vec3<f32> {
    let waveHeight = u.zoom_params.x;
    let particleDensity = max(0.1, u.zoom_params.z);
    let audioReactivity = u.zoom_params.w;

    var bp = p;

    // Wave function
    let speed = g_time * 2.0;
    // Base wave shape
    var crest = sin(bp.x * 0.5 - speed) * cos(bp.z * 0.3 + speed * 0.5);

    // Audio driven turbulence
    let audioBump = g_audio * audioReactivity * sin(bp.x * 10.0) * cos(bp.z * 8.0);
    crest += audioBump * 0.5;

    // Mouse attraction/repulsion
    let mDist = length(bp.xz - g_mouse * 15.0);
    let mouseInfluence = exp(-mDist * 0.2) * 2.0;
    crest += mouseInfluence;

    crest *= waveHeight;

    // Create an infinite grid of particles
    let domainSpacing = particleDensity * 2.0;

    // Find the cell index
    let cell = floor((bp + domainSpacing * 0.5) / domainSpacing);

    // Apply domain repetition
    bp.x = bp.x - cell.x * domainSpacing;
    bp.z = bp.z - cell.z * domainSpacing;

    // Modify particle height based on its world position wave
    let wX = cell.x * domainSpacing;
    let wZ = cell.z * domainSpacing;
    var wCrest = sin(wX * 0.5 - speed) * cos(wZ * 0.3 + speed * 0.5) * waveHeight;
    wCrest += g_audio * audioReactivity * sin(wX * 10.0) * cos(wZ * 8.0) * 0.5;
    wCrest += exp(-length(vec2<f32>(wX, wZ) - g_mouse * 15.0) * 0.2) * 2.0 * waveHeight;

    bp.y -= wCrest;

    // Rotate particle based on cell
    let h = hash31(vec3<f32>(cell.x, 0.0, cell.z));
    bp.xz = rot(g_time * (0.5 + h) + h * 6.28) * bp.xz;
    bp.xy = rot(g_time * 0.3 + h * 6.28) * bp.xy;

    // Base shape: slightly rounded boxes
    let boxSize = particleDensity * 0.4 * (0.5 + 0.5 * h);
    let d = sdBox(bp, vec3<f32>(boxSize)) - boxSize * 0.2;

    return vec3<f32>(d, 1.0, 0.0);
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

    g_time = u.config.x;
    g_audio = u.config.y * 0.1; // scale down the audio proxy

    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    g_mouse = vec2<f32>(mX, mY);

    // Camera setup
    var ro = vec3<f32>(0.0, 5.0, -10.0);

    // Orbit camera with mouse
    ro.xz = rot(mX * 2.0) * ro.xz;
    ro.yz = rot(mY * 1.0) * ro.yz;

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var maxT = 40.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        if (d < 0.001 || t > maxT) { break; }
        t += d * 0.8;
    }

    var col = vec3<f32>(0.05, 0.1, 0.15); // Deep ocean background
    col -= uv.y * 0.1;

    if (t < maxT) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let lig = normalize(vec3<f32>(0.8, 1.0, -0.5));
        let dif = max(dot(n, lig), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Glass Refraction / Scattering
        let refrStrength = u.zoom_params.y;

        // Fake interior lighting/refraction by sampling behind the hit point
        let interiorRay = refract(rd, n, 0.65); // glass IOR
        let p2 = p + interiorRay * 0.5;
        let interiorDist = map(p2).x;
        let interiorGlow = max(0.0, interiorDist) * 0.5;

        // Coloring
        let baseGlass = vec3<f32>(0.1, 0.4, 0.8);
        let crestColor = vec3<f32>(0.7, 0.9, 1.0);

        // Mix based on height
        let hMix = smoothstep(-2.0, u.zoom_params.x * 2.0, p.y);
        var matCol = mix(baseGlass, crestColor, hMix);

        // Combine lighting
        col = matCol * (dif * 0.5 + 0.1) + fre * vec3<f32>(1.0) * refrStrength;

        // Add fake scattering
        col += vec3<f32>(0.2, 0.5, 0.9) * interiorGlow * refrStrength;

        // Distance fog
        let fog = 1.0 - exp(-t * 0.05);
        col = mix(col, vec3<f32>(0.05, 0.1, 0.15), fog);
    }

    // Add specular highlights from the sun/light source in the sky
    let sun = pow(max(dot(rd, normalize(vec3<f32>(0.8, 1.0, -0.5))), 0.0), 64.0);
    col += sun * vec3<f32>(1.0, 0.9, 0.7) * (1.0 - step(maxT - 0.1, t));

    // Tone mapping and gamma correction
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}