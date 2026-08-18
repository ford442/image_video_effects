// ----------------------------------------------------------------
// Abyssal Plasma Void-Medusa
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
  zoom_params: vec4<f32>,  // .x = parameter1, .y = parameter2, .z = parameter3, .w = parameter4
  ripples: array<vec4<f32>, 50>,
};

// --- SHADER START ---

const MAX_STEPS = 100;
const MAX_DIST = 100.0;
const SURF_DIST = 0.001;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn smoothNoise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n000 = dot(hash33(i + vec3<f32>(0.0, 0.0, 0.0)) - 0.5, f - vec3<f32>(0.0, 0.0, 0.0));
    let n100 = dot(hash33(i + vec3<f32>(1.0, 0.0, 0.0)) - 0.5, f - vec3<f32>(1.0, 0.0, 0.0));
    let n010 = dot(hash33(i + vec3<f32>(0.0, 1.0, 0.0)) - 0.5, f - vec3<f32>(0.0, 1.0, 0.0));
    let n110 = dot(hash33(i + vec3<f32>(1.0, 1.0, 0.0)) - 0.5, f - vec3<f32>(1.0, 1.0, 0.0));
    let n001 = dot(hash33(i + vec3<f32>(0.0, 0.0, 1.0)) - 0.5, f - vec3<f32>(0.0, 0.0, 1.0));
    let n101 = dot(hash33(i + vec3<f32>(1.0, 0.0, 1.0)) - 0.5, f - vec3<f32>(1.0, 0.0, 1.0));
    let n011 = dot(hash33(i + vec3<f32>(0.0, 1.0, 1.0)) - 0.5, f - vec3<f32>(0.0, 1.0, 1.0));
    let n111 = dot(hash33(i + vec3<f32>(1.0, 1.0, 1.0)) - 0.5, f - vec3<f32>(1.0, 1.0, 1.0));

    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);

    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);

    return mix(nxy0, nxy1, u.z);
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    let time = u.config.x;

    let fluid_distort = u.zoom_params.y;
    let tentacle_length = u.zoom_params.z;

    // Domain distortion
    p += vec3<f32>(
        smoothNoise(p * 2.0 + vec3<f32>(time * 0.5, 0.0, 0.0)),
        smoothNoise(p * 2.0 + vec3<f32>(0.0, time * 0.5, 0.0)),
        smoothNoise(p * 2.0 + vec3<f32>(0.0, 0.0, time * 0.5))
    ) * fluid_distort * 0.5;

    // Mouse drag effect
    if (u.zoom_config.w > 0.0) {
        let mousePos = u.zoom_config.yz * 2.0 - 1.0;
        let dragDist = length(p.xy - mousePos * 5.0);
        let dragForce = exp(-dragDist * 0.5);
        p = vec3<f32>(p.x + mousePos.x * dragForce, p.y - mousePos.y * dragForce, p.z);
    }

    // Medusa Bell (inverted hemisphere)
    var bellP = p;
    bellP.y -= 1.0;
    let bellRad = 1.5;
    var dBell = length(bellP) - bellRad;
    let bellInner = length(bellP + vec3<f32>(0.0, 0.5, 0.0)) - (bellRad - 0.2);
    dBell = max(dBell, -bellInner);
    dBell = max(dBell, -bellP.y); // cut off bottom

    // Tentacles
    var dTentacles = 100.0;
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        var tP = p;

        let a = fi * 6.28318 / 5.0 + time * 0.5;
        let r = 0.8;
        tP.x -= cos(a) * r;
        tP.z -= sin(a) * r;

        // Sine wave modulation along y
        tP.x += sin(tP.y * 2.0 - time * 2.0 + fi) * 0.3;
        tP.z += cos(tP.y * 2.0 - time * 2.0 + fi) * 0.3;

        // Capsule
        tP.y -= clamp(tP.y, -tentacle_length * 3.0, 1.0);
        let dTen = length(tP) - 0.1 * (1.0 - tP.y / 3.0); // Tapering

        dTentacles = smin(dTentacles, dTen, 0.3);
    }

    return smin(dBell, dTentacles, 0.5);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy),
        map(p - e.yxy),
        map(p - e.yyx)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) * 2.0 - resolution) / min(resolution.x, resolution.y);
    let time = u.config.x;

    var ro = vec3<f32>(0.0, -1.0, 5.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    // Mouse rotation
    let mouse = (u.zoom_config.yz * 2.0 - vec2<f32>(1.0)) * vec2<f32>(1.0, -1.0);
    if (u.zoom_config.w > 0.0) {
        let rx = rot2D(-mouse.x * 3.14159);
        ro = vec3<f32>(rx * ro.xz, ro.y).xzy;
        let ry = rot2D(-mouse.y * 1.5);
        ro = vec3<f32>(ro.x, ry * ro.yz).xzy;
    }

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    var p = ro;
    var dO = 0.0;
    var dS = 0.0;
    var vol = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        dS = map(p);
        if (dS < SURF_DIST) {
            break;
        }

        // Volumetric scattering accumulation
        vol += 0.05 / (1.0 + abs(dS) * 10.0);

        dO += dS;
        if (dO > MAX_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.0, 0.05, 0.1); // Deep oceanic background

    let biolum = u.zoom_params.x;
    let plasmaHue = u.zoom_params.w;

    // Audio reactivity
    let audio_freq = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(abs(uv.x), 0.5), 0.0).r;
    let audio_glow = audio_freq * 0.5;

    if (dO < MAX_DIST) {
        let n = getNormal(p);
        let lightPos = vec3<f32>(2.0, 4.0, 3.0);
        let l = normalize(lightPos - p);

        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.1;

        // Subsurface / bioluminescence
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        var baseCol = vec3<f32>(0.1, 0.3, 0.6); // Base medusa color

        // Mix hue based on parameter
        let hueShiftCol = vec3<f32>(
            0.5 + 0.5 * cos(plasmaHue * 6.28 + 0.0),
            0.5 + 0.5 * cos(plasmaHue * 6.28 + 2.1),
            0.5 + 0.5 * cos(plasmaHue * 6.28 + 4.2)
        );
        baseCol = mix(baseCol, hueShiftCol, plasmaHue);

        col = baseCol * (dif + amb);

        // Add bioluminescent glow and audio reaction
        col += hueShiftCol * fresnel * biolum * (1.0 + audio_glow * 2.0);
    }

    // Add volumetric bloom
    col += vec3<f32>(0.1, 0.4, 0.8) * vol * biolum * (0.5 + audio_glow);

    // Falloff into void
    col *= exp(-dO * 0.05);

    // Tone mapping
    col = col / (1.0 + col);
    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
