// ----------------------------------------------------------------
// Obsidian Echo-Chamber
// Category: generative
// ----------------------------------------------------------------
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Mouse Influence
    ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}


const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 150.0;
const SURF_DIST: f32 = 0.001;

fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn map(p: vec3<f32>) -> f32 {
    let objectScale = mix(0.72, 1.45, clamp(u.zoom_params.z, 0.0, 1.0));
    let motionTime = u.config.x * mix(0.45, 2.4, clamp(u.zoom_params.y, 0.0, 1.0));
    var pos = p / objectScale;
    // Domain repetition
    let spacing = 7.5;

    // Calculate cell ID for dynamic gravity shifts
    let id_x = floor((pos.x + spacing * 0.5) / spacing);
    let id_z = floor((pos.z + spacing * 0.5) / spacing);

    pos.x = (pos.x + spacing * 0.5) % spacing - spacing * 0.5;
    pos.z = (pos.z + spacing * 0.5) % spacing - spacing * 0.5;

    // Vertical shift based on position
    let hash = fract(sin(id_x * 12.9898 + id_z * 78.233) * 43758.5453);
    pos.y += sin(p.x * 0.1 + motionTime + hash * 6.28) * 2.0;

    // Monolith SDF
    let box = sdBox(pos, vec3<f32>(1.0, 10.0, 1.0));

    // Add subtle structural cuts to the monolith
    var q = pos;
    q.y = (q.y + 1.0) % 2.0 - 1.0;
    let cuts = sdBox(q, vec3<f32>(1.2, 0.1, 1.2));

    return max(box, -cuts) * objectScale;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

fn rayMarch(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    var dO: f32 = 0.0;
    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += max(abs(dS), 0.002);
        if(dO > MAX_DIST || abs(dS) < SURF_DIST) { break; }
    }
    return dO;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    var uv = (fragCoord - 0.5 * res) / res.y;

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let mouseInfluence = clamp(u.zoom_params.w, 0.0, 1.0);
    let motionTime = u.config.x * mix(0.45, 2.4, speed);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Wrapped fly-through keeps the corridor moving quickly without precision
    // loss at long run times.
    let cameraTravel = motionTime * (3.5 + speed * 5.5 + bass * 2.0);
    var ro = vec3<f32>(0.0, 2.0, -6.0 + (cameraTravel - 7.5 * floor(cameraTravel / 7.5)));
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Mouse is already normalized canvas UV; do not divide it by resolution.
    let mouseX = (u.zoom_config.y - 0.5) * 1.8 * mouseInfluence;
    let mouseY = (u.zoom_config.z - 0.5) * 1.15 * mouseInfluence;

    let rotY = rot2D(-mouseX);
    let rotX = rot2D(mouseY);

    // Apply rotations (avoid sequential scalar assignment)
    let rdYZ = rotX * vec2<f32>(rd.y, rd.z);
    rd.y = rdYZ.x; rd.z = rdYZ.y;

    let rdXZ = rotY * vec2<f32>(rd.x, rd.z);
    rd.x = rdXZ.x; rd.z = rdXZ.y;

    let roYZ = rotX * vec2<f32>(ro.y, ro.z);
    ro.y = roYZ.x; ro.z = roYZ.y;

    let roXZ = rotY * vec2<f32>(ro.x, ro.z);
    ro.x = roXZ.x; ro.z = roXZ.y;

    // Primary Raymarching
    let d = rayMarch(ro, rd);

    var col = vec3<f32>(0.0);

    // Background / Fog color
    let bgCol = vec3<f32>(0.01, 0.01, 0.02); // Pitch-black void

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = getNormal(p);
        let viewDir = normalize(ro - p);

        // Base obsidian material
        let albedo = vec3<f32>(0.005, 0.005, 0.01);

        // Fast sonar wavefronts race down the chamber on real audio bands.
        let distFromCam = length(p - ro);

        // The ripple maps to fractional part of distance minus time
        let ripplePhase = fract(distFromCam * 0.12 - motionTime * (1.8 + speed * 2.2));

        let baseIntensity = smoothstep(0.9, 1.0, ripplePhase);
        let audioIntensity = (0.22 + bass * 0.9 + mids * 0.35) * (0.55 + intensity * 1.25);

        // Vibrant neon gradient (cyan to magenta)
        let rippleColor = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(distFromCam * 0.2) * 0.5 + 0.5);
        let rippleEmission = rippleColor * baseIntensity * audioIntensity * 10.0;

        // Basic lighting
        let lightDir = normalize(vec3<f32>(0.5, 1.0, -0.5));
        let diff = max(dot(n, lightDir), 0.0);

        // Glossy Reflections & Fresnel
        let refDir = reflect(-viewDir, n);

        // Specular highlight
        let specPower = pow(max(dot(refDir, lightDir), 0.0), u.zoom_params.z * 100.0 + 10.0);
        let specColor = vec3<f32>(1.0) * specPower * (0.5 + u.zoom_params.z * 0.5);

        // Fresnel
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);
        let fresnelColor = mix(albedo, vec3<f32>(1.0), fresnel * u.zoom_params.z);

        // Chromatic Aberration on reflections (simulated)
        let caShift = 0.03;
        let rRefDir = reflect(-viewDir, normalize(n + vec3<f32>(caShift, 0.0, 0.0)));
        let bRefDir = reflect(-viewDir, normalize(n - vec3<f32>(caShift, 0.0, 0.0)));

        let rSpec = pow(max(dot(rRefDir, lightDir), 0.0), u.zoom_params.z * 100.0 + 10.0);
        let bSpec = pow(max(dot(bRefDir, lightDir), 0.0), u.zoom_params.z * 100.0 + 10.0);

        let caSpec = vec3<f32>(rSpec, specPower, bSpec) * (0.5 + u.zoom_params.z * 0.5);

        // Analytic reflected corridor replaces a second 120-step raymarch.
        let reflectedBand = pow(max(0.0, 1.0 - abs(fract(refDir.z * 3.0 - motionTime * 2.0) - 0.5) * 2.0), 14.0);
        let refEnv = mix(vec3<f32>(0.015, 0.025, 0.055), vec3<f32>(0.15, 0.9, 1.5), reflectedBand) *
                     (0.45 + fresnel + treble * 0.35);

        // Combine material
        col = albedo * diff + caSpec + fresnelColor * refEnv * u.zoom_params.z + rippleEmission;

        // Volumetric fog blending
        let fogDensity = 0.04;
        let fogFactor = exp(-distFromCam * fogDensity);
        col = mix(bgCol, col, fogFactor);

    } else {
        col = bgCol;
    }

    // Click echoes add fast radial reflection shocks without persistent state.
    var clickEcho = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let screenUv = fragCoord / res;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age >= 0.0 && age < 1.6) {
            let delta = (screenUv - ripple.xy) * vec2<f32>(res.x / res.y, 1.0);
            clickEcho = max(clickEcho, exp(-abs(length(delta) - age * 0.52) * 64.0) * exp(-age * 1.6));
        }
    }
    col += vec3<f32>(0.18, 0.8, 1.4) * clickEcho * (0.65 + treble * 0.7);

    // Forward-advected, bounded reflection history forms corridor speed trails.
    let historyVelocity = vec2<f32>(mouseX * 2.0, -(2.0 + speed * 5.0 + bass * 2.0));
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let historyCoord = clamp(vec2<i32>(id.xy) - vec2<i32>(historyVelocity), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let hdrColor = clamp(col * (0.72 + intensity * 0.75) + history * (0.24 + speed * 0.16), vec3<f32>(0.0), vec3<f32>(5.0));
    let hit = d < MAX_DIST;
    let alpha = clamp(select(0.025, 0.28 + length(hdrColor) * 0.22, hit) + clickEcho * 0.22, 0.02, 0.96);
    let depth = select(0.0, clamp(1.0 - d / MAX_DIST, 0.0, 1.0), hit);
    let coord = vec2<i32>(id.xy);
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(hdrColor), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
