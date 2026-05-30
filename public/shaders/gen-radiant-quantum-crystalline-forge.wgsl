// ═══════════════════════════════════════════════════════════════════
//  Radiant Quantum-Crystalline Forge
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════

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
    zoom_params: vec4<f32>,  // x=Density, y=Chroma, z=Fog, w=Unused
    ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 80;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.01;

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn mapSDF(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let t = u.config.x * 0.5;
    let audio = plasmaBuffer[0].x; // bass drives fold expansion
    let density = u.zoom_params.x;

    p.x += sin(p.z * 0.2 + t) * 0.5;
    p.y += cos(p.x * 0.2 + t) * 0.5;

    var scale: f32 = 1.0;
    let iter = 6;
    for(var i = 0; i < iter; i++) {
        p = abs(p) - vec3<f32>(1.2, 0.8, 1.5) * density * (1.0 + audio * 0.2);
        let rot = rotate(t * 0.2 + f32(i) * 0.5);
        p = vec3<f32>(rot * p.xy, p.z);
        let rot2 = rotate(t * 0.3);
        p = vec3<f32>(p.x, rot2 * p.yz);

        let s = 1.8;
        p *= s;
        scale *= s;
    }

    let d = (length(p) - 1.0) / scale;
    return vec2<f32>(d, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        mapSDF(p + e.xyy).x - mapSDF(p - e.xyy).x,
        mapSDF(p + e.yxy).x - mapSDF(p - e.yxy).x,
        mapSDF(p + e.yyx).x - mapSDF(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    var uv = (vec2<f32>(global_id.xy) - vec2<f32>(0.5) * res) / res.y;

    // Audio reactivity: mids feed volumetric fog, treble adds spec sparkle
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse Interaction: Gravity well distortion
    var m = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) - vec2<f32>(0.5) * res) / res.y;
    let mDist = length(uv - m);
    if (mDist < 0.5 && u.zoom_config.y > 0.0) {
        let force = (0.5 - mDist) * 2.0;
        uv += normalize(uv - m) * force * 0.1 * sin(u.config.x * 2.0);
    }

    let ro = vec3<f32>(0.0, 0.0, -8.0 + u.config.x * 2.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var dO = 0.0;
    var hit = false;
    var glow = 0.0;
    var p = ro;

    let chroma = u.zoom_params.y;
    let fogInt = u.zoom_params.z;

    for(var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let dS = mapSDF(p);

        // Volumetric Fog accumulation
        glow += 0.01 * fogInt / (1.0 + dS.x * dS.x * 100.0) * (1.0 + mids * 0.8);

        if(dS.x < SURF_DIST) {
            hit = true;
            break;
        }
        if(dO > MAX_DIST) { break; }
        dO += dS.x * 0.8;
    }

    var col = vec3<f32>(0.0);
    var surfFresnel = 0.0;

    if(hit) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));
        let view = normalize(ro - p);
        let h = normalize(l + view);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), 32.0) * (1.0 + treble * 1.5);
        let fresnel = pow(1.0 - max(dot(n, view), 0.0), 4.0);
        surfFresnel = fresnel;

        // Iridescent chromatic dispersion based on normals and time
        let baseCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(u.config.x) + p.xyz * 0.5 + vec3<f32>(0.0, 2.0, 4.0));

        col = baseCol * diff + spec * vec3<f32>(1.0) + fresnel * vec3<f32>(0.5, 0.8, 1.0) * chroma;
    }

    // Add fog
    let fogCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(u.config.x * 0.2) + vec3<f32>(0.0, 1.0, 2.0));
    col += vec3<f32>(glow) * fogCol;

    // Background fade
    let bgFade = smoothstep(0.0, MAX_DIST, dO);
    col = mix(col, vec3<f32>(0.05, 0.0, 0.1), bgFade);

    // Alpha: crystal surface coverage + volumetric fog density, never flat 1.0
    let alpha = clamp(select(0.0, 0.4, hit) + surfFresnel * 0.4 + clamp(glow, 0.0, 1.0) * 0.4, 0.0, 1.0);
    let out = vec4<f32>(col, alpha);

    // Depth: ray-march hit distance (near = closer)
    let depth = select(0.0, clamp(1.0 - dO / MAX_DIST, 0.0, 1.0), hit);
    let coord = vec2<i32>(global_id.xy);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
