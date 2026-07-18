// ----------------------------------------------------------------
// Luminescent Quantum-Glass Phoenix-Egg
// Category: generative
// Visualist upgrade: multi-source lighting, volumetric internal plasma fog,
// iridescent glass shell, Fresnel rim, god rays, ACES + hue clamp + IGN dither.
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
    zoom_params: vec4<f32>,  // x=Plasma Hue, y=Core Activity, z=Glass Refraction, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + vec3<f32>(33.33));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn snoise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let n = mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
    return n;
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p2 = p;
    for (var i = 0; i < 5; i++) {
        v += a * snoise(p2);
        p2 = p2 * vec3<f32>(2.0) + shift;
        a *= 0.5;
    }
    return v;
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + k.xyz) * vec3<f32>(6.0) - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let v = max(c.r, max(c.g, c.b));
    let minc = min(c.r, min(c.g, c.b));
    let s = select(0.0, (v - minc) / v, v > 0.0);
    let delta = v - minc;
    var h = 0.0;
    if (delta > 0.0) {
        if (v == c.r) { h = (c.g - c.b) / delta; }
        else if (v == c.g) { h = 2.0 + (c.b - c.r) / delta; }
        else { h = 4.0 + (c.r - c.g) / delta; }
    }
    h = fract(h / 6.0 + 1.0);
    return vec3<f32>(h, s, v);
}

fn hue_preserving_clamp(c: vec3<f32>, max_val: f32) -> vec3<f32> {
    let hsv = rgb2hsv(c);
    return hsv2rgb(vec3<f32>(hsv.x, hsv.y, min(hsv.z, max_val)));
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51);
    let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43);
    let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign_dither(uv: vec2<f32>) -> f32 {
    let p = floor(uv);
    return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

fn iridescent_shell(cosTheta: f32, hueBase: f32, time: f32) -> vec3<f32> {
    let t = 1.0 - cosTheta;
    let hue = fract(hueBase + 0.18 * sin(t * 8.0 + time * 0.6) + 0.12 * cos(t * 5.0 - time * 0.4));
    return hsv2rgb(vec3<f32>(hue, 0.7, 1.0));
}

// Egg outer shell SDF
fn mapEgg(p: vec3<f32>) -> f32 {
    var p2 = p;
    p2.y *= 1.0 - 0.2 * p.y;
    let base = length(p2) - 1.5;
    let noise = snoise(p * vec3<f32>(5.0)) * 0.05;
    return base + noise;
}

// Inner plasma core SDF
fn mapCore(p: vec3<f32>) -> f32 {
    let act = u.zoom_params.y;
    let t = u.config.x * act;
    let base = length(p) - 0.7 - u.config.y * 0.3;
    let noise = fbm(p * vec3<f32>(3.0) + vec3<f32>(0.0, t, 0.0)) * 0.4;
    return base + noise;
}

fn getNormalEgg(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        mapEgg(p + e.xyy) - mapEgg(p - e.xyy),
        mapEgg(p + e.yxy) - mapEgg(p - e.yxy),
        mapEgg(p + e.yyx) - mapEgg(p - e.yyx)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    if (global_id.x >= dim.x || global_id.y >= dim.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let iResolution = vec2<f32>(u.config.z, u.config.w);
    var uv = (fragCoord - 0.5 * iResolution) / iResolution.y;

    let time = u.config.x;
    let audio = u.config.y;
    let m = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / iResolution) * vec2<f32>(2.0) - vec2<f32>(1.0);

    // Read previous frame for subtle persistence
    let prevUV = fragCoord / iResolution;
    let prev = textureSampleLevel(readTexture, u_sampler, prevUV, 0.0);

    var ro = vec3<f32>(0.0, 0.0, 4.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Rotate camera based on mouse and time
    let rotX = rot(-m.y * 2.0);
    let rotY = rot(time * 0.1 + m.x * 3.0);

    ro = vec3<f32>(ro.x, ro.y * rotX[0][0] + ro.z * rotX[1][0], ro.y * rotX[0][1] + ro.z * rotX[1][1]);
    ro = vec3<f32>(ro.x * rotY[0][0] + ro.z * rotY[1][0], ro.y, ro.x * rotY[0][1] + ro.z * rotY[1][1]);

    rd = vec3<f32>(rd.x, rd.y * rotX[0][0] + rd.z * rotX[1][0], rd.y * rotX[0][1] + rd.z * rotX[1][1]);
    rd = vec3<f32>(rd.x * rotY[0][0] + rd.z * rotY[1][0], rd.y, rd.x * rotY[0][1] + rd.z * rotY[1][1]);

    let refr = u.zoom_params.z;
    let glow = u.zoom_params.w;
    let hue = u.zoom_params.x;

    // Light sources
    let keyLight = normalize(vec3<f32>(0.8, 1.0, -0.6));
    let fillLight = normalize(vec3<f32>(-0.9, 0.3, -0.4));
    let rimLightDir = normalize(vec3<f32>(0.0, -1.0, 1.0));
    let keyColor = vec3<f32>(1.3, 0.8, 0.35);
    let fillColor = vec3<f32>(0.25, 0.55, 1.35);
    let rimColor = vec3<f32>(1.2, 0.4, 1.5);

    // Raymarch outer shell
    var t = 0.0;
    var d = 0.0;
    var hitEgg = false;
    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        d = mapEgg(p);
        if (d < 0.001) {
            hitEgg = true;
            break;
        }
        if (t > 10.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var depth = 1.0;
    var emission = 0.0;
    var density = 0.0;

    if (hitEgg) {
        let p = ro + rd * t;
        let n = getNormalEgg(p);
        depth = t * 0.1;

        // Refraction into the egg
        let rdIn = refract(rd, n, 1.0 / max(refr, 0.1));

        // Volumetric inner core raymarch
        var tIn = 0.1;
        var colCore = vec3<f32>(0.0);
        density = 0.0;

        for(var i=0; i<64; i++) {
            let pIn = p + rdIn * tIn;
            let dCore = mapCore(pIn);

            if(dCore < 0.0) {
                density += 0.04 * glow;
                let coreCol = hsv2rgb(vec3<f32>(hue + fbm(pIn)*0.2, 0.85, 1.0));
                colCore += coreCol * 0.06 * glow;
            }

            // Tendril emissive surface
            let tendril = max(0.0, 0.025 - abs(dCore)) * 0.6 * glow;
            colCore += hsv2rgb(vec3<f32>(hue + 0.5, 0.9, 1.0)) * tendril;
            density += tendril;

            tIn += max(0.02, abs(dCore) * 0.5);
            if(tIn > 3.0) { break; }
        }

        // Fresnel reflection on glass shell
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
        let iris = iridescent_shell(fresnel, hue, time) * fresnel * 2.5;

        // External lighting on shell
        let diffKey = max(dot(n, keyLight), 0.0);
        let diffFill = max(dot(n, fillLight), 0.0) * 0.5;
        let rim = pow(1.0 - max(dot(n, rimLightDir), 0.0), 3.0);

        let shellLit = vec3<f32>(0.05, 0.08, 0.15) * (keyColor * diffKey + fillColor * diffFill)
                     + rimColor * rim * 1.5;

        col = colCore + shellLit + iris;
        emission = density + fresnel * 1.5;
    }

    // Background cosmic dust + god rays
    let bgDust = fbm(rd * vec3<f32>(10.0) + vec3<f32>(time * 0.1));
    var bg = vec3<f32>(bgDust * 0.05);

    // External volumetric fog / god rays
    var fogAccum = 0.0;
    for (var i = 0; i < 24; i++) {
        let fi = f32(i);
        let fp = ro + rd * (fi * 0.35);
        let fogDen = max(0.0, fbm(fp * 0.8 + vec3<f32>(time * 0.05)) - 0.3);
        fogAccum += fogDen * 0.03;
    }
    let fogColor = mix(vec3<f32>(0.15, 0.0, 0.25), vec3<f32>(0.0, 0.45, 0.65), 0.5);
    bg += fogColor * fogAccum * 1.5;

    // God ray bursts from behind egg
    let rayAngle = atan2(rd.y, rd.x);
    let rays = pow(max(0.0, sin(rayAngle * 8.0 + time * 0.2)), 12.0) * 0.6;
    bg += vec3<f32>(1.1, 0.7, 1.4) * rays;

    if (!hitEgg) {
        col = bg;
    } else {
        col = mix(bg, col, clamp(0.7 + emission * 0.2, 0.0, 1.0));
    }

    // Audio reactivity bloom
    col += vec3<f32>(1.0, 0.5, 0.2) * audio * glow * 0.4;

    // Temporal persistence
    col = mix(col, prev.rgb, 0.05);

    // HDR hue-preserving clamp
    col = hue_preserving_clamp(col, 8.0);

    // ACES tone mapping
    col = aces_tone_map(col);

    // IGN dither
    let dither = (ign_dither(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
    col = clamp(col + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: glass transparency based on Fresnel + core density + fog
    let alpha = clamp(0.2 + emission * 0.5 + fogAccum * 0.3, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(emission, density, fogAccum, alpha));
}
