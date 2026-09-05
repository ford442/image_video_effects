// Ferrofluid Monolith — magnetic liquid-metal obelisk
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
    zoom_params: vec4<f32>, // x=Monolith Height, y=Spike Strength, z=Field Speed, w=Core Glow
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn hash31(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn mapScene(pIn: vec3<f32>, time: f32, audio: vec3<f32>, height: f32, spikes: f32) -> vec2<f32> {
    var p = pIn;
    let twist = time * 0.18 + p.y * (0.14 + audio.y * 0.08);
    let twistedXZ = rot(twist) * p.xz;
    p.x = twistedXZ.x; p.z = twistedXZ.y;
    let obelisk = sdBox(p, vec3<f32>(0.72, height, 0.72));
    let angle = atan2(p.z, p.x);
    let radial = length(p.xz);
    let field = pow(max(sin(angle * (8.0 + floor(audio.z * 4.0)) + p.y * 4.5 - time * 2.0), 0.0), 5.0);
    let taper = smoothstep(height + 0.25, 0.0, abs(p.y));
    let spikeShell = radial - (0.72 + field * spikes * taper * (0.45 + audio.x));
    let cap = abs(p.y) - height;
    let ferro = max(spikeShell, cap);
    let core = length(p.xz) - 0.25 + abs(p.y) * 0.025;
    let d = min(obelisk, min(ferro, core));
    let material = select(1.0, 2.0, core < min(obelisk, ferro));
    return vec2<f32>(d, material);
}

fn normalAt(p: vec3<f32>, time: f32, audio: vec3<f32>, height: f32, spikes: f32) -> vec3<f32> {
    let e = vec2<f32>(0.0015, 0.0);
    return normalize(vec3<f32>(
        mapScene(p + e.xyy, time, audio, height, spikes).x - mapScene(p - e.xyy, time, audio, height, spikes).x,
        mapScene(p + e.yxy, time, audio, height, spikes).x - mapScene(p - e.yxy, time, audio, height, spikes).x,
        mapScene(p + e.yyx, time, audio, height, spikes).x - mapScene(p - e.yyx, time, audio, height, spikes).x
    ));
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
    let uv01 = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let uv = (vec2<f32>(gid.xy) - res * 0.5) / res.y;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let height = mix(1.25, 2.5, clamp(u.zoom_params.x, 0.0, 1.0));
    let spikes = mix(0.05, 0.75, clamp(u.zoom_params.y, 0.0, 1.0));
    let fieldSpeed = mix(0.2, 2.2, clamp(u.zoom_params.z, 0.0, 1.0));
    let coreGlow = mix(0.25, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));

    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let yaw = mouse.x * mix(0.18, 1.1, held);
    let pitch = mouse.y * mix(0.12, 0.65, held);
    var ro = vec3<f32>(0.0, 0.1, -6.0);
    let orbitXZ = rot(yaw + time * 0.06 * fieldSpeed) * ro.xz;
    ro.x = orbitXZ.x; ro.z = orbitXZ.y;
    let orbitYZ = rot(-pitch) * ro.yz;
    ro.y = orbitYZ.x; ro.z = orbitYZ.y;
    let lookAt = vec3<f32>(0.0);
    let forward = normalize(lookAt - ro);
    let right = normalize(cross(forward, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(right, forward);
    let rd = normalize(uv.x * right + uv.y * up + 1.35 * forward);

    var travel = 0.0;
    var material = 0.0;
    var glow = 0.0;
    var hit = false;
    var hitPos = ro;
    for (var i = 0; i < 84; i++) {
        hitPos = ro + rd * travel;
        let scene = mapScene(hitPos, time * fieldSpeed, audio, height, spikes);
        material = scene.y;
        glow += 0.006 / (0.025 + abs(scene.x)) * (0.3 + audio.x * 0.7);
        if (scene.x < 0.0015) { hit = true; break; }
        if (travel > 14.0) { break; }
        travel += max(scene.x * 0.65, 0.002);
    }

    var hdrColor = vec3<f32>(0.008, 0.012, 0.025) + vec3<f32>(0.03, 0.02, 0.05) * (1.0 - length(uv));
    if (hit) {
        let n = normalAt(hitPos, time * fieldSpeed, audio, height, spikes);
        let view = -rd;
        let light = normalize(vec3<f32>(0.7, 0.9, -0.5));
        let diffuse = max(dot(n, light), 0.0);
        let fresnel = pow(1.0 - max(dot(n, view), 0.0), 4.0);
        let spec = pow(max(dot(reflect(-light, n), view), 0.0), 64.0);
        let chrome = vec3<f32>(0.035) + vec3<f32>(0.2, 0.32, 0.45) * diffuse + vec3<f32>(0.8, 0.9, 1.0) * (fresnel + spec);
        let core = vec3<f32>(0.12 + audio.x * 0.5, 0.45 + audio.y * 0.5, 1.2 + audio.z * 0.6) * coreGlow;
        hdrColor = select(chrome, core, material > 1.5);
    }
    hdrColor += vec3<f32>(0.08, 0.35, 0.9) * min(glow, 5.0) * 0.08 * coreGlow;

    var clickField = 0.0;
    let aspect = res.x / max(res.y, 1.0);
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let delta = vec2<f32>((uv01.x - ripple.x) * aspect, uv01.y - ripple.y);
            clickField += exp(-abs(length(delta) - age * 0.24) * 70.0) * exp(-age * 1.45);
        }
    }
    hdrColor += vec3<f32>(0.2, 0.7 + audio.y * 0.4, 1.25 + audio.z * 0.5) * clickField * 0.35;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.06 + audio.x * 0.07), vec3<f32>(0.0), vec3<f32>(8.0));
    let mapped = acesToneMap(hdrColor);
    let alpha = clamp(select(0.03, 0.32 + length(mapped) * 0.32, hit) + clickField * 0.1, 0.02, 0.98);
    let depth = select(0.0, clamp(1.0 - travel / 14.0, 0.0, 1.0), hit);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
