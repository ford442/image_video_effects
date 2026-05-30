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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let h = p3 + dot(p3, p3.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * vnoise2(pp);
        pp = pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn moireFlower(uv: vec2<f32>, center: vec2<f32>, time: f32, rings: f32, speed: f32, rotSpeed: f32) -> f32 {
    let d = length(uv - center);
    let angle = atan2(uv.y - center.y, uv.x - center.x);
    let t = time * speed;

    var pattern = 0.0;

    let r1 = d * rings * 30.0;
    let a1 = angle + t * rotSpeed;
    pattern += sin(r1 + a1 * 3.0) * 0.5 + 0.5;

    let r2 = d * rings * 25.0;
    let a2 = angle - t * rotSpeed * 1.3;
    pattern += sin(r2 + a2 * 5.0 + 1.047) * 0.5 + 0.5;

    let r3 = d * rings * 35.0;
    let a3 = angle + t * rotSpeed * 0.7;
    pattern += sin(r3 - a3 * 7.0 + 2.094) * 0.5 + 0.5;

    let r4 = d * rings * 20.0;
    let a4 = angle - t * rotSpeed * 2.0;
    let fine = sin(r4 + a4 * 11.0 + t) * 0.5 + 0.5;
    pattern += fine * 0.6;

    let r5 = d * rings * 15.0;
    let spiral = sin(r5 - a4 * 3.0 + d * 50.0 - t * 2.0) * 0.5 + 0.5;
    pattern += spiral * 0.5;

    return pattern * 0.25;
}

fn neonColor(intensity: f32, hueShift: f32) -> vec3<f32> {
    let t = intensity * 6.28318530718 + hueShift;
    let phase1 = t + 0.0;
    let phase2 = t + 2.094;
    let phase3 = t + 4.189;

    let r = pow(sin(phase1) * 0.5 + 0.5, 0.7);
    let g = pow(sin(phase2) * 0.5 + 0.5, 0.7);
    let b = pow(sin(phase3) * 0.5 + 0.5, 0.7);

    let hotPink = vec3<f32>(1.0, 0.0, 0.6);
    let elecOrange = vec3<f32>(1.0, 0.5, 0.0);
    let lime = vec3<f32>(0.5, 1.0, 0.0);
    let cyan = vec3<f32>(0.0, 1.0, 1.0);
    let magenta = vec3<f32>(1.0, 0.0, 1.0);
    let gold = vec3<f32>(1.0, 0.9, 0.0);

    var col = vec3<f32>(0.0);
    col += hotPink * pow(max(sin(phase1), 0.0), 3.0);
    col += elecOrange * pow(max(sin(phase2 + 0.5), 0.0), 3.0);
    col += lime * pow(max(sin(phase3 + 1.0), 0.0), 3.0);
    col += cyan * pow(max(sin(phase1 + 2.0), 0.0), 3.0);
    col += magenta * pow(max(sin(phase2 + 3.0), 0.0), 3.0);
    col += gold * pow(max(sin(phase3 + 4.0), 0.0), 3.0);

    return col * (1.0 + intensity * 2.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;

    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let centeredUV = vec2<f32>(uv.x * aspect, uv.y);
    let center = vec2<f32>(aspect * 0.5, 0.5);

    let mouseUV = vec2<f32>(mousePos.x / res.x * aspect, mousePos.y / res.y);
    let activeCenter = mouseDown > 0.5 ? mouseUV : center;

    let t = time * (0.2 + speed * 1.5);
    let patternScale = 0.5 + scale * 2.0;
    let mouseDensity = mouseDown > 0.5 ? 2.0 : 1.0;
    let mouseSpeed = mouseDown > 0.5 ? 2.5 : 1.0;

    let p1 = moireFlower(centeredUV, activeCenter, t, patternScale * mouseDensity, mouseSpeed, 0.3);
    let p2 = moireFlower(centeredUV, activeCenter, t + 1.0, patternScale * mouseDensity * 1.2, mouseSpeed * 0.8, -0.5);
    let p3 = moireFlower(centeredUV, activeCenter, t + 2.3, patternScale * mouseDensity * 0.8, mouseSpeed * 1.2, 0.7);

    let interference = abs(p1 - p2) * abs(p2 - p3) * abs(p3 - p1) * 8.0;

    let d = length(centeredUV - activeCenter);
    let radialMoire = sin(d * 60.0 * patternScale - t * 4.0) * 0.5 + 0.5;
    let radialMoire2 = sin(d * 45.0 * patternScale + t * 3.0) * 0.5 + 0.5;

    let angle = atan2(centeredUV.y - activeCenter.y, centeredUV.x - activeCenter.x);
    let petal = sin(angle * 8.0 + t * 2.0) * 0.5 + 0.5;
    let petal2 = sin(angle * 12.0 - t * 1.5) * 0.5 + 0.5;

    var pattern = p1 * 0.25 + p2 * 0.2 + p3 * 0.15;
    pattern += interference * (0.5 + intensity);
    pattern += radialMoire * radialMoire2 * 0.2 * (1.0 - d * 0.5);
    pattern += petal * petal2 * 0.15 * exp(-d * 2.0);

    let noiseAccent = fbm(centeredUV * 8.0 + t * 0.3, 3) * 0.1;
    pattern += noiseAccent;

    let colorHue = pattern * 2.0 + colorShift * 4.0 + t * 0.15;
    var color = neonColor(pattern + interference * 0.5, colorHue);

    let glow = exp(-pattern * 3.0) * 0.5;
    color += neonColor(glow, colorHue + 1.57) * glow * intensity;

    let ringHighlight = pow(abs(sin(d * 20.0 * patternScale - t * 3.0)), 32.0) * 2.0;
    color += neonColor(ringHighlight, colorHue + 3.14) * ringHighlight * intensity;

    color *= 1.0 + intensity * 1.5;
    color = color / (1.0 + color * 0.1);

    let vignette = 1.0 - smoothstep(0.3, 1.1, d);
    color *= 0.6 + vignette * 0.4;

    textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
