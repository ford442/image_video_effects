// ----------------------------------------------------------------
// Cosmic-Clockwork Dyson-Sphere
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
    zoom_params: vec4<f32>,  // x=Mechanical Complexity, y=Clock Speed, z=Plasma Intensity, w=Gear Ratio
    ripples: array<vec4<f32>, 50>,
};

fn rotX(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotZ(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

fn map(pos: vec3<f32>, complex: f32, gearRatio: f32) -> f32 {
    var p = pos;
    var d = 1000.0;

    // Core Singularity
    let dCore = length(p) - 0.5;

    // KIFS Folds
    for (var i = 0; i < 4; i++) {
        p = abs(p);
        p = p - vec3<f32>(gearRatio * 1.5, gearRatio * 0.5, gearRatio * 1.5);
        p = p * rotY(complex * 2.0);
        p = p * rotZ(complex * 1.5);
    }

    let box = sdBox(p, vec3<f32>(0.2, 1.0, 0.2));
    d = min(d, box);

    // Remove geometry too close to the singularity
    d = max(d, -dCore + 0.1);

    return d;
}

fn calcNormal(p: vec3<f32>, complex: f32, gearRatio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, complex, gearRatio) - map(p - e.xyy, complex, gearRatio),
        map(p + e.yxy, complex, gearRatio) - map(p - e.yxy, complex, gearRatio),
        map(p + e.yyx, complex, gearRatio) - map(p - e.yyx, complex, gearRatio)
    ));
}

fn getPlasmaColor(intensity: f32) -> vec3<f32> {
    let c = clamp(intensity, 0.0, 1.0);
    return mix(
        vec3<f32>(0.1, 0.0, 0.8),
        vec3<f32>(1.0, 0.9, 0.2),
        c
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let uv = (vec2<f32>(coords) - vec2<f32>(res) * 0.5) / f32(res.y);

    // Uniforms mapping
    let complex = u.zoom_params.x; // Mechanical Complexity
    let clockSpd = u.zoom_params.y; // Clock Speed
    let plasmaInt = u.zoom_params.z; // Plasma Intensity
    let gearRatio = u.zoom_params.w; // Gear Ratio

    let time = u.config.x * clockSpd;
    let audio = plasmaBuffer[0].x;

    // Snapping Rotation (stepped time + audio kick)
    let steppedTime = floor(time) + smoothstep(0.8, 1.0, time - floor(time) * 1.0);
    let rotAngle = steppedTime * 0.5 + audio * 2.0;

    // Mouse Interaction
    let mousePos = (u.zoom_config.yz * 2.0 - vec2<f32>(1.0, 1.0)) * 3.14;

    // Camera Setup
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    ro = ro * rotX(-mousePos.y) * rotY(mousePos.x + rotAngle * 0.1);

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));

    let rd = normalize(uv.x * uu + uv.y * vv + 1.0 * ww);

    // Raymarching
    var t = 0.0;
    var p = ro;
    var coreDist = 1000.0;
    var hit = false;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let d = map(p, complex, gearRatio);

        // Track the closest distance to the core singularity
        let dCore = length(p) - 0.5;
        coreDist = min(coreDist, dCore);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d;
    }

    var color = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p, complex, gearRatio);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let refl = reflect(rd, n);
        let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);

        // Metallic Brass
        let baseColor = vec3<f32>(0.8, 0.6, 0.2);
        color = baseColor * diff + vec3<f32>(1.0) * spec;

        // Ambient Occlusion
        let ao = clamp(map(p + n * 0.1, complex, gearRatio) * 10.0, 0.0, 1.0);
        color = color * ao;
    }

    // Volumetric Glow (Plasma Core)
    if (coreDist < 1.0) {
        let glowStrength = clamp(1.0 - coreDist, 0.0, 1.0) * plasmaInt * (1.0 + audio);
        let plasmaCol = getPlasmaColor(glowStrength);

        color += plasmaCol * glowStrength * 1.5;
    }

    // Post-processing
    color = pow(color, vec3<f32>(1.0 / 2.2)); // Gamma correction

        let _luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let _alpha = clamp(_luma * 0.7 + 0.2, 0.0, 1.0);
    textureStore(writeTexture, coords, vec4<f32>(color, _alpha));
    let _depth_uv = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let _depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, _depth_uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(_depth, 0.0, 0.0, 0.0));
}