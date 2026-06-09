// ----------------------------------------------------------------
// Luminescent Quantum-Glass Phoenix-Egg
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
    zoom_params: vec4<f32>,  // x=Plasma Hue, y=Core Activity, z=Glass Refraction, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// Utilities
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
    let u = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
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

// Egg outer shell SDF
fn mapEgg(p: vec3<f32>) -> f32 {
    // Basic sphere deformed into an egg
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
    let base = length(p) - 0.7 - u.config.y * 0.3; // audio heartbeat
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

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + k.xyz) * vec3<f32>(6.0) - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
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

    // Mouse interaction
    let m = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / iResolution) * vec2<f32>(2.0) - vec2<f32>(1.0);

    var ro = vec3<f32>(0.0, 0.0, 4.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Rotate camera based on mouse and time
    let rotX = rot(-m.y * 2.0);
    let rotY = rot(u.config.x * 0.1 + m.x * 3.0);

    ro = vec3<f32>(ro.x, ro.y * rotX[0][0] + ro.z * rotX[1][0], ro.y * rotX[0][1] + ro.z * rotX[1][1]);
    ro = vec3<f32>(ro.x * rotY[0][0] + ro.z * rotY[1][0], ro.y, ro.x * rotY[0][1] + ro.z * rotY[1][1]);

    rd = vec3<f32>(rd.x, rd.y * rotX[0][0] + rd.z * rotX[1][0], rd.y * rotX[0][1] + rd.z * rotX[1][1]);
    rd = vec3<f32>(rd.x * rotY[0][0] + rd.z * rotY[1][0], rd.y, rd.x * rotY[0][1] + rd.z * rotY[1][1]);

    var col = vec3<f32>(0.0);
    let refr = u.zoom_params.z;

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

    if (hitEgg) {
        let p = ro + rd * t;
        let n = getNormalEgg(p);

        // Refraction
        let rdIn = refract(rd, n, 1.0 / refr);

        // Raymarch inner core volumetric
        var tIn = 0.1;
        var colCore = vec3<f32>(0.0);
        var density = 0.0;

        let hue = u.zoom_params.x;
        let glow = u.zoom_params.w;

        for(var i=0; i<50; i++) {
            let pIn = p + rdIn * tIn;
            let dCore = mapCore(pIn);

            if(dCore < 0.0) {
                density += 0.05 * glow;
                // Core color mapping
                let coreCol = hsv2rgb(vec3<f32>(hue + fbm(pIn)*0.2, 0.8, 1.0));
                colCore += coreCol * 0.05 * glow;
            }

            // Add tendril artifacts
            density += max(0.0, 0.02 - abs(dCore)) * 0.5 * glow;

            tIn += max(0.02, abs(dCore) * 0.5);
            if(tIn > 3.0) { break; }
        }

        // Fresnel reflection
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);

        col = colCore + mix(vec3<f32>(0.05), vec3<f32>(0.5, 0.7, 1.0), fresnel);
    } else {
        // Background cosmic dust
        let bgDust = fbm(rd * vec3<f32>(10.0) + vec3<f32>(u.config.x * 0.1));
        col = vec3<f32>(bgDust * 0.05);
    }

    // Tonemapping and gamma
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(1.0/2.2));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
