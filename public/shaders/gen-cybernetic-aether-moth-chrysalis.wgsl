// ----------------------------------------------------------------
// Cybernetic Aether-Moth Chrysalis
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
    zoom_params: vec4<f32>,  // x=Point Density, y=Rotation Speed, z=Point Size, w=Color Shift
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Helper Functions
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

// 3D Voronoi Distance
fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec3<f32>(8.0);
    var res = vec2<f32>(8.0);

    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let d = g - f + o;
                let d2 = dot(d, d);

                if (d2 < res.x) {
                    res.y = res.x;
                    res.x = d2;
                } else if (d2 < res.y) {
                    res.y = d2;
                }
            }
        }
    }
    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var q = p;
    for(var i = 0; i < 4; i++) {
        let v = voronoi(q);
        f += w * v.x;
        q *= 2.0;
        w *= 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

// ----------------------------------------------------------------
// Map Function
// ----------------------------------------------------------------
fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let t = u.config.x;

    // Mouse Interaction
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(3.14, 1.57);
    p = vec3<f32>(rot(-mouse.y) * p.xy, p.z);
    p = vec3<f32>(p.x, rot(mouse.x) * p.yz);

    let rotSpeed = u.zoom_params.y * 2.0;
    p = vec3<f32>(rot(t * rotSpeed) * p.xy, p.z);

    // Core Capsule
    let coreH = 2.5;
    let coreR = 1.0 + sin(t) * 0.1;
    let coreY = p.y - clamp(p.y, -coreH, coreH);
    let dCoreCapsule = length(vec2<f32>(p.x, p.z)) - coreR + p.y*p.y*0.05; // Tapered

    // Three-band audio reactivity comes from the engine audio buffer.
    let audio = plasmaBuffer[0].xyz;

    // Core Displacement
    let coreNoise = fbm(p * 2.0 - vec3<f32>(0.0, t * 1.5, 0.0)) * 0.5;
    let dCore = dCoreCapsule + coreNoise - audio.x * 0.3;

    // Shell
    let complexity = u.zoom_params.x * 5.0 + 3.0;
    let thickness = u.zoom_params.z * 0.3 + 0.1;
    let shellR = coreR + 0.4;
    let shellY = p.y - clamp(p.y, -coreH - 0.2, coreH + 0.2);
    let dShellBase = length(vec2<f32>(p.x, p.z)) - shellR + p.y*p.y*0.04;

    let v = voronoi(p * complexity + vec3<f32>(0.0, t * 0.2, 0.0));
    let cellEdge = v.y - v.x;
    let dShell = max(dShellBase, -(cellEdge - thickness - audio.y * 0.04));

    // Fiber Optics (Audio Reactive)
    let dFibers = length(vec2<f32>(p.x, p.z)) - (coreR + audio.x * 1.2) + abs(sin(p.y * (10.0 + audio.z * 4.0) - t * 5.0)) * 0.1;

    var d = min(dCore, dShell);
    d = min(d, max(dFibers, dCoreCapsule));

    var mat = 1.0; // Shell
    if (d == dCore) { mat = 2.0; } // Core
    else if (d == max(dFibers, dCoreCapsule)) { mat = 3.0; } // Fibers

    return vec2<f32>(d * 0.5, mat);
}

// ----------------------------------------------------------------
// Lighting & Shading
// ----------------------------------------------------------------
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    var uv = vec2<f32>(id.xy) / res;
    let p = (uv * 2.0 - 1.0) * vec2<f32>(res.x / res.y, 1.0);

    let ro = vec3<f32>(0.0, 0.0, 6.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(p.x * cu + p.y * cv + 1.5 * cw);

    var t = 0.0;
    var m = -1.0;
    var glow = vec3<f32>(0.0);
    var p_current = ro;

    let audio = plasmaBuffer[0].xyz;
    let colorShift = u.zoom_params.w;

    for (var i = 0; i < 120; i++) {
        p_current = ro + rd * t;
        let d = map(p_current);

        if (abs(d.x) < 0.001 || t > 20.0) {
            m = d.y;
            break;
        }

        t += d.x;

        // Accumulate Glow
        if (d.y == 2.0) { // Core
            let c = vec3<f32>(0.1, 0.6, 1.0) * (1.0 - colorShift) + vec3<f32>(0.8, 0.1, 1.0) * colorShift;
            glow += c * 0.02 / (0.1 + abs(d.x)) * (0.5 + audio.x * 1.5 + audio.y * 0.4);
        } else if (d.y == 3.0) { // Fibers
            glow += vec3<f32>(0.2, 1.0, 0.8) * 0.03 / (0.05 + abs(d.x)) * (audio.x + audio.z * 0.8);
        }
    }

    var col = vec3<f32>(0.02, 0.03, 0.05) * (1.0 - length(p)*0.3); // Background

    if (t < 20.0) {
        let n = getNormal(p_current);
        let l = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, l), 0.0);

        if (m == 1.0) { // Shell
            col = vec3<f32>(0.05, 0.05, 0.06);

            // Rim light
            let rim = 1.0 - max(dot(n, -rd), 0.0);
            col += vec3<f32>(0.1, 0.4, 0.8) * pow(rim, 4.0);

            // Specular
            let h = normalize(l - rd);
            let spec = pow(max(dot(n, h), 0.0), 32.0);
            col += vec3<f32>(0.5) * spec;
        } else if (m == 2.0) { // Core (should be occluded by shell, but just in case)
            col = vec3<f32>(1.0) * diff;
        }
    }

    col += glow;

    // Click fronts make the chrysalis flare without changing its raymarched silhouette.
    var clickGlow = 0.0;
    let uv01 = (vec2<f32>(id.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let delta = vec2<f32>((uv01.x - ripple.x) * aspect, uv01.y - ripple.y);
            clickGlow += exp(-abs(length(delta) - age * 0.2) * 70.0) * exp(-age * 1.4);
        }
    }
    col += mix(vec3<f32>(0.15, 0.8, 1.2), vec3<f32>(1.0, 0.2, 1.1), colorShift) * clickGlow * (0.25 + audio.z * 0.65);

    // Add some noise/dust
    col += hash3(vec3<f32>(p_current.xy * 100.0, u.config.x)).x * 0.03;

    let coord = vec2<i32>(id.xy);
    let history = textureLoad(dataTextureC, coord, 0);
    let hdrColor = clamp(mix(col, history.rgb, 0.06 + audio.x * 0.08), vec3<f32>(0.0), vec3<f32>(7.0));
    let mappedColor = acesToneMap(hdrColor);
    let hit = t < 20.0;
    let alpha = clamp(select(0.03, 0.32 + length(mappedColor) * 0.32, hit) + clickGlow * 0.12, 0.02, 0.98);
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);

    textureStore(writeTexture, coord, vec4<f32>(mappedColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
