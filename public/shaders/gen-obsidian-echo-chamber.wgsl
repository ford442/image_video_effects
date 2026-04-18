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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Monolith Spacing, y=Ripple Intensity, z=Specular Gloss, w=Forward Speed
    ripples: array<vec4<f32>, 50>,
};

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
    var pos = p;
    // Domain repetition
    let spacing = u.zoom_params.x * 5.0 + 5.0; // Slider mapped spacing

    // Calculate cell ID for dynamic gravity shifts
    let id_x = floor((pos.x + spacing * 0.5) / spacing);
    let id_z = floor((pos.z + spacing * 0.5) / spacing);

    pos.x = (pos.x + spacing * 0.5) % spacing - spacing * 0.5;
    pos.z = (pos.z + spacing * 0.5) % spacing - spacing * 0.5;

    // Vertical shift based on position
    let hash = fract(sin(id_x * 12.9898 + id_z * 78.233) * 43758.5453);
    pos.y += sin(p.x * 0.1 + u.config.x + hash * 6.28) * 2.0;

    // Monolith SDF
    let box = sdBox(pos, vec3<f32>(1.0, 10.0, 1.0));

    // Add subtle structural cuts to the monolith
    var q = pos;
    q.y = (q.y + 1.0) % 2.0 - 1.0;
    let cuts = sdBox(q, vec3<f32>(1.2, 0.1, 1.2));

    return max(box, -cuts);
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
        dO += dS;
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

    // Camera setup with mouse interaction
    var ro = vec3<f32>(0.0, 2.0, -u.config.x * u.zoom_params.w * 5.0); // Moving forward
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Mouse rotation
    let mouseX = (u.zoom_config.y / res.x) * 6.2831 - 3.1415;
    let mouseY = (u.zoom_config.z / res.y) * 3.1415 - 1.5707;

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

        // Audio reactive sonar ripples
        let distFromCam = length(p - ro);

        // The ripple maps to fractional part of distance minus time
        let ripplePhase = fract(distFromCam * 0.1 - u.config.x * 3.0);

        // Intensity driven by u.config.y (Audio/ClickCount)
        let baseIntensity = smoothstep(0.9, 1.0, ripplePhase);
        let audioIntensity = u.config.y * u.zoom_params.y;

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

        // Secondary raymarching for real reflection (simplified)
        let refDist = rayMarch(p + n * 0.01, refDir);
        var refEnv = bgCol;
        if (refDist < MAX_DIST) {
            let pRef = p + n * 0.01 + refDir * refDist;
            let refDistCam = length(pRef - ro);
            let refRipplePhase = fract(refDistCam * 0.1 - u.config.x * 3.0);
            let refBaseInt = smoothstep(0.9, 1.0, refRipplePhase);
            let refRippleCol = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(refDistCam * 0.2) * 0.5 + 0.5);
            refEnv = refRippleCol * refBaseInt * audioIntensity * 5.0;
        }

        // Combine material
        col = albedo * diff + caSpec + fresnelColor * refEnv * u.zoom_params.z + rippleEmission;

        // Volumetric fog blending
        let fogDensity = 0.04;
        let fogFactor = exp(-distFromCam * fogDensity);
        col = mix(bgCol, col, fogFactor);

    } else {
        col = bgCol;
    }

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    let finalColor = vec4<f32>(col, 1.0);
    textureStore(writeTexture, vec2<i32>(id.xy), finalColor);
}
