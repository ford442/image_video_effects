// Fractal Tree Growth — recursive branching distance field
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>, // x=Branch Depth, y=Branch Spread, z=Growth Phase, w=Leaf Glow
    ripples: array<vec4<f32>, 50>,
};

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return length(pa - ba * h);
}

fn rotateVector(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle); let s = sin(angle);
    return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.08, 0.33, 0.58)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let res = vec2<f32>(dims);
    let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    let p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    let maxDepth = i32(3.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 3.0);
    let spread = mix(0.22, 0.78, clamp(u.zoom_params.y, 0.0, 1.0));
    let growth = clamp(0.28 + u.zoom_params.z * 0.72 + sin(time * 0.22) * 0.05 + audio.x * 0.08, 0.0, 1.0);
    let leafGlow = mix(0.25, 2.8, clamp(u.zoom_params.w, 0.0, 1.0));
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let wind = mouse.x * held * (0.16 + audio.y * 0.08);

    var branchField = 0.0;
    var leafField = 0.0;
    var heightDepth = 0.0;
    var hueMoment = 0.0;
    for (var leafPath = 0; leafPath < 32; leafPath++) {
        var origin = vec2<f32>(0.0, 0.86);
        var direction = vec2<f32>(0.0, -1.0);
        var segmentLength = 0.44;
        for (var level = 0; level < 6; level++) {
            if (level >= maxDepth) { break; }
            let levelGrowth = clamp(growth * f32(maxDepth + 1) - f32(level), 0.0, 1.0);
            if (levelGrowth <= 0.0) { break; }
            let bit = (u32(leafPath) >> u32(level)) & 1u;
            let side = select(-1.0, 1.0, bit == 1u);
            let bend = side * spread * (0.72 + f32(level) * 0.08) + wind * (f32(level) + 1.0);
            direction = normalize(rotateVector(direction, bend));
            let tip = origin + direction * segmentLength * levelGrowth;
            let thickness = mix(0.026, 0.006, f32(level) / 5.0) * (1.0 + audio.x * 0.2);
            let d = sdSegment(p, origin, tip);
            let branch = exp(-d * d / max(thickness * thickness, 0.000001));
            branchField += branch / 32.0;
            heightDepth = max(heightDepth, branch * (0.35 + f32(level) * 0.11));
            hueMoment += branch * f32(level);
            origin = tip;
            segmentLength *= 0.69;
            if (level == maxDepth - 1 && levelGrowth > 0.75) {
                let leafDistance = length(p - tip);
                let leaf = exp(-leafDistance * leafDistance / (0.0012 + audio.z * 0.0005));
                leafField += leaf / 5.0;
                heightDepth = max(heightDepth, leaf);
                hueMoment += leaf * 6.0;
            }
        }
    }

    var clickGrowth = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.4) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickGrowth += exp(-abs(distance(p, center) - age * 0.2) * 72.0) * exp(-age * 1.35);
        }
    }

    let hue = hueMoment / max(branchField + leafField, 0.001) * 0.07 + time * 0.015 + audio.y * 0.12;
    let bark = mix(vec3<f32>(0.18, 0.055, 0.018), vec3<f32>(0.58, 0.24, 0.045), audio.x);
    let foliage = palette(hue) * (0.55 + leafGlow + audio.z * 0.6);
    var hdrColor = vec3<f32>(0.006, 0.012, 0.012) + bark * branchField * (1.1 + audio.x * 0.5);
    hdrColor += foliage * leafField * leafGlow;
    hdrColor += vec3<f32>(0.3 + audio.x * 0.25, 0.9 + audio.y * 0.35, 0.45 + audio.z * 0.45) * clickGrowth * 0.34;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.045 + audio.x * 0.06), vec3<f32>(0.0), vec3<f32>(7.0));
    let mapped = acesToneMap(hdrColor * 1.08);
    let alpha = clamp(branchField * 0.62 + leafField * 0.32 + clickGrowth * 0.1, 0.02, 0.98);
    let depth = clamp(heightDepth, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
