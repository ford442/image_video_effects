// ----------------------------------------------------------------
// Quantum Liquid-Gold Cymatic-Vortex
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Vortex Speed, .y = Viscosity, .z = Cymatic Intensity, .w = Gold Purity
  ripples: array<vec4<f32>, 50>,
};

// --- CONSTANTS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 15.0;
const SURF_DIST: f32 = 0.005;
const TAU: f32 = 6.28318530718;

// --- UTILS ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash31(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    p = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

fn hash33(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    p = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn valueNoise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            mix(hash31(i + vec3<f32>(0.0, 0.0, 0.0)), hash31(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 0.0)), hash31(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y
        ),
        mix(
            mix(hash31(i + vec3<f32>(0.0, 0.0, 1.0)), hash31(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 1.0)), hash31(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y
        ), u.z
    );
}

fn fbm(p_in: vec3<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var p = p_in;
    var shift = vec3<f32>(100.0);
    for (var i = 0; i < octaves; i++) {
        v += a * valueNoise3D(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// --- CORE ---
fn getDist(p_in: vec3<f32>, bass: f32, cymatic: f32) -> f32 {
    var p = p_in;

    // Base plane
    var d = p.y + 1.0;

    // Vortex distortion
    let dist = length(p.xz);
    let angle = atan2(p.z, p.x);
    let vortexTwist = u.zoom_params.x * 2.0 / (dist + 0.1); // u.zoom_params.x is Vortex Speed
    let twistedAngle = angle + vortexTwist * u.config.x;

    // Magnetic mouse interaction
    var mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    mousePos.x *= u.config.z / u.config.w;

    var localMouse = mousePos;
    if (u.zoom_config.w > 0.0) {
      // increase pull
    } else {
        localMouse = vec2<f32>(sin(u.config.x*0.5)*0.5, cos(u.config.x*0.7)*0.5);
    }

    let distToMouse = length(p.xz - localMouse * 4.0);
    let mousePull = exp(-distToMouse * distToMouse * 0.5);
    p.y += mousePull * 0.5;

    // Viscosity / Noise Scale
    let viscosity = u.zoom_params.y; // 0 to 1
    let noiseScale = mix(1.0, 0.2, viscosity) + mousePull * 0.5;

    // Cymatic patterns
    let cymaticFreq = 10.0 + bass * 20.0;
    let cymaticWave = sin(dist * cymaticFreq - u.config.x * 5.0) * cos(twistedAngle * 8.0);
    let cymaticDisp = cymaticWave * cymatic * 0.1 * exp(-dist * 0.5);

    // Fluid noise
    let noiseDisp = fbm(vec3<f32>(p.x * noiseScale, p.y + u.config.x, p.z * noiseScale), 4) * 0.5;

    d += noiseDisp + cymaticDisp;

    // Add central singularity
    let sphereDist = length(p - vec3<f32>(0.0, -1.0, 0.0)) - 0.5;

    return min(d, sphereDist);
}

fn getNormal(p: vec3<f32>, bass: f32, cymatic: f32) -> vec3<f32> {
    let e = vec2<f32>(0.005, 0.0);
    let n = vec3<f32>(
        getDist(p + e.xyy, bass, cymatic) - getDist(p - e.xyy, bass, cymatic),
        getDist(p + e.yxy, bass, cymatic) - getDist(p - e.yxy, bass, cymatic),
        getDist(p + e.yyx, bass, cymatic) - getDist(p - e.yyx, bass, cymatic)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(dimensions.x) || coord.y >= i32(dimensions.y)) {
        return;
    }

    let res = vec2<f32>(dimensions);
    let uv = (vec2<f32>(coord) + 0.5) / res;
    let base_uv = uv;
    var pt = uv * 2.0 - 1.0;
    pt.x *= res.x / res.y;

    // Audio Reactivity
    var bass = 0.0;
    var treble = 0.0;
    if (arrayLength(&extraBuffer) > 133u) {
        bass = extraBuffer[133] * 0.5; // Smoothed bass
        treble = extraBuffer[136] * 0.5;
    }

    let cymatic = u.zoom_params.z; // Cymatic Intensity
    let goldPurity = u.zoom_params.w;

    // Camera Setup
    let ro = vec3<f32>(0.0, 2.0, -5.0);
    var rd = normalize(vec3<f32>(pt.x, pt.y - 0.5, 1.5));

    // Raymarching
    var dO = 0.0;
    var dS = 0.0;
    var p = vec3<f32>(0.0);

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        dS = getDist(p, bass, cymatic);
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.05, 0.02, 0.01); // Background deep space

    if (dO < MAX_DIST) {
        let n = getNormal(p, bass, cymatic);

        // Lighting
        let lightPos = vec3<f32>(2.0, 5.0, -2.0);
        let l = normalize(lightPos - p);
        let viewDir = normalize(ro - p);
        let halfVector = normalize(l + viewDir);

        // Gold Colors
        let pureGold = vec3<f32>(1.0, 0.84, 0.0);
        let darkBronze = vec3<f32>(0.4, 0.2, 0.05);
        let baseColor = mix(darkBronze, pureGold, goldPurity);

        let dif = clamp(dot(n, l), 0.0, 1.0);

        // Specular highlight (sharp for liquid metal)
        let spec = pow(max(dot(n, halfVector), 0.0), 64.0) * 1.5;

        // Fake Environment Reflection
        let refl = reflect(-viewDir, n);
        let envVal = smoothstep(0.5, 1.0, fbm(refl * 2.0, 3));
        let envReflection = mix(vec3<f32>(0.1), vec3<f32>(1.0, 0.9, 0.5), envVal);

        // Subsurface / Ambient scattering approximation
        let ao = clamp(p.y * 0.5 + 0.5, 0.0, 1.0);

        col = baseColor * dif * ao;
        col += envReflection * 0.5 * goldPurity;
        col += vec3<f32>(spec) * pureGold;

        // Add emission for cymatic peaks
        let cymaticPeak = smoothstep(0.8, 1.0, sin(length(p.xz) * (10.0 + bass*20.0) - u.config.x * 5.0));
        col += pureGold * cymaticPeak * cymatic * bass * 2.0;

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.02, 0.01), 1.0 - exp(-0.02 * dO * dO));
    }

    // Tonemapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
