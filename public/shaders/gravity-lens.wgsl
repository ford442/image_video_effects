// ═══════════════════════════════════════════════════════════════════════════════
//  Relativistic Gravitational Lensing — Schwarzschild Geometry & Einstein Ring
//  Category: distortion
//  Features: mouse-driven, depth-aware, audio-reactive
//  Complexity: High
//  Scientific: Schwarzschild photon geodesics, Einstein ring formation,
//              gravitational redshift, accretion disk arc, dark-matter halo
//  Upgraded: Phase B — complete rewrite from halftone to real lensing
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,  // x=Time, y=ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=LensMass, y=RingWidth, z=Chromatic, w=DarkMatter
    ripples:     array<vec4<f32>, 50>,
}

// Planck blackbody temperature (1000K–20000K) → linear RGB approximation
fn blackbody(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 20000.0);
    var r: f32; var g: f32; var b: f32;
    if (t <= 6600.0) {
        r = 1.0;
        let lT = log(t / 100.0);
        g = clamp((99.47 * lT - 161.12) / 255.0, 0.0, 1.0);
        b = select(0.0, clamp((138.52 * log(t / 100.0 - 10.0) - 305.04) / 255.0, 0.0, 1.0), t > 2000.0);
    } else {
        let lt = t / 100.0 - 60.0;
        r = clamp(329.70 * pow(lt, -0.1332) / 255.0, 0.0, 1.0);
        g = clamp(288.12 * pow(lt, -0.0755) / 255.0, 0.0, 1.0);
        b = 1.0;
    }
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv      = vec2<f32>(global_id.xy) / resolution;
    let time    = u.config.x;
    let aspect  = resolution.x / resolution.y;
    let bass    = plasmaBuffer[0].x;
    let mids    = plasmaBuffer[0].y;

    // Lens positioned at mouse; default to centre
    var lensPos = u.zoom_config.yz;
    if (lensPos.x <= 0.0 && lensPos.y <= 0.0) { lensPos = vec2<f32>(0.5, 0.5); }

    // Parameters
    let lensMass  = mix(0.002, 0.09, u.zoom_params.x) * (1.0 + bass * 0.35);
    let ringWidth = mix(0.002, 0.025, u.zoom_params.y);
    let chromatic = u.zoom_params.z;
    let darkParam = u.zoom_params.w;

    // Aspect-corrected impact parameter
    var p  = vec2<f32>(uv.x * aspect, uv.y);
    var lp = vec2<f32>(lensPos.x * aspect, lensPos.y);
    let delta = p - lp;
    let b     = length(delta);
    let bDir  = select(vec2<f32>(1.0, 0.0), normalize(delta), b > 0.0001);

    // Schwarzschild quantities
    let rs          = lensMass;                   // Schwarzschild radius (normalised screen units)
    let photonSphere = rs * 1.5;                  // Photon orbit
    let einsteinR   = sqrt(rs * 0.5);             // Einstein ring radius

    // Weak-field deflection α = 2 r_s / b, clamped near photon sphere
    let bSafe      = max(b, rs * 0.02);
    let deflectMag = 2.0 * rs / (bSafe * bSafe) * min(bSafe / (photonSphere + 0.0001), 3.0);
    let deflect    = bDir * deflectMag;

    // Per-channel chromatic: red bends 2 % less, blue 4 % more
    let chromAmt   = chromatic * 0.25 * deflectMag;
    let uvR = uv - vec2<f32>(deflect.x * 0.98 / aspect, deflect.y * 0.98);
    let uvG = uv - vec2<f32>(deflect.x / aspect,        deflect.y);
    let uvB = uv - vec2<f32>(deflect.x * 1.04 / aspect, deflect.y * 1.04)
                + vec2<f32>(bDir.x * chromAmt / aspect, bDir.y * chromAmt);

    let sR = textureSampleLevel(readTexture, u_sampler, clamp(uvR, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, clamp(uvG, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, clamp(uvB, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // Gravitational redshift: deeper in potential → warmer colour temperature
    let potential = rs / max(b, rs * 0.1);
    let redshift  = clamp(potential * 2.0, 0.0, 1.0);
    let T_apparent = mix(8500.0, 2400.0, redshift);
    let bbShift    = blackbody(T_apparent);
    color = mix(color, color * bbShift, redshift * 0.65);

    // Einstein ring glow — constructive interference of all lensed light paths
    let ringDist = abs(b - einsteinR);
    let ringGlow = exp(-ringDist * ringDist / (ringWidth * ringWidth)) * (0.9 + mids * 0.6);
    color += blackbody(mix(12000.0, 5500.0, darkParam)) * ringGlow * 2.8;

    // Accretion disk arc: angular variation around ring
    let phi      = atan2(delta.y, delta.x / aspect);
    let diskMod  = 0.5 + 0.5 * cos(phi * 3.0 + time * 0.5 + bass * 2.0);
    color += blackbody(16000.0) * ringGlow * diskMod * 0.6;

    // Dark-matter / lensing halo beyond Einstein ring
    let haloR   = einsteinR * 2.5;
    let halo    = darkParam * exp(-b * b / (haloR * haloR)) * 0.18;
    color += vec3<f32>(0.25, 0.08, 0.5) * halo;

    // Black-hole shadow: photon sphere swallows light
    let shadow  = smoothstep(photonSphere * 0.8, photonSphere * 1.2, b);
    color *= shadow;

    // Depth modulation: nearby objects lens slightly more
    let depth      = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    color = mix(color * 0.6, color, depth * 0.5 + 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(b, potential, ringGlow, deflectMag));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
        vec4<f32>(clamp(1.0 - b / max(einsteinR * 2.0, 0.001), 0.0, 1.0), 0.0, 0.0, 0.0));
}
