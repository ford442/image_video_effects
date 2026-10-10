// ----------------------------------------------------------------
// Biomechanical Neural Mycelium
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> f32 {
    var q = p;
    let time = u.config.x * u.zoom_params.y; // Pulse speed

    // Audio reactive
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    if (u.zoom_config.w > 0.0) {
        let mouse_pos = vec2<f32>(u.zoom_config.y - 0.5, (1.0 - u.zoom_config.z) - 0.5) * 5.0;
        let dist = length(q.xy - mouse_pos);
        let pull = exp(-dist * 3.0);
        let qxy = q.xy - mouse_pos * pull;
        q = vec3<f32>(qxy, q.z);
    }

    let rot = rot2D(time * 0.1 + q.z * 0.1);
    let qxy2 = q.xy * rot;
    q = vec3<f32>(qxy2.x, qxy2.y, q.z);

    let scale = u.zoom_params.x * 2.0 + 1.0; // Network Density

    // Domain repetition
    var qRep = q;
    qRep.x = (fract(qRep.x / scale + 0.5) - 0.5) * scale;
    qRep.y = (fract(qRep.y / scale + 0.5) - 0.5) * scale;
    qRep.z = (fract(qRep.z / scale + 0.5) - 0.5) * scale;

    var d = length(qRep) - (0.1 + bass * 0.05); // Spheres at nodes

    // Fibers
    var d2 = length(qRep.xy) - 0.02; // Z-axis fibers
    d2 = min(d2, length(qRep.xz) - 0.02); // Y-axis fibers
    d2 = min(d2, length(qRep.yz) - 0.02); // X-axis fibers

    d = smin(d, d2, 0.2);

    // Noise distortion
    d += sin(q.x * 5.0 + time) * cos(q.y * 4.0 - time) * 0.05;

    return d;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    if (f32(id.x) >= dims.x || f32(id.y) >= dims.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) * 2.0 - dims) / min(dims.x, dims.y);
    let time = u.config.x;

    let ro = vec3<f32>(0.0, 0.0, -3.0 + time * 0.5);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t: f32 = 0.0;
    var d: f32 = 0.0;
    var glow: f32 = 0.0;
    var steps: i32 = 0;
    var hit: bool = false;

    let glowIntens = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.y;

    for (var i: i32 = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p);

        let localTime = time * pulseSpeed * 5.0;
        let glowPulse = sin(localTime + length(p) * 2.0) * 0.5 + 0.5;

        // Accumulate glow based on distance to nearest fiber
        glow += (0.01 / (d * d + 0.01)) * glowPulse * glowIntens;

        if (d < 0.001) {
            steps = i;
            hit = true;
            break;
        }
        if (t > 20.0) {
            steps = i;
            break;
        }
        t += d * 0.8; // Raymarching step
    }

    var col = vec3<f32>(0.0);
    let colorShift = u.zoom_params.w;

    // Base colors based on color shift (Acid-green to electric-blue)
    let c1 = vec3<f32>(0.2 + colorShift * 0.3, 1.0 - colorShift * 0.5, 0.2 + colorShift * 0.8);
    let c2 = vec3<f32>(0.1, 0.4 + colorShift * 0.4, 0.8 - colorShift * 0.2);

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0)); // Light dir
        let v = normalize(ro - p); // View dir
        let refl = reflect(-l, n);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(v, refl), 0.0), 32.0); // High specularity for bio-metallic look

        // Fake ambient occlusion based on step count
        let ao = 1.0 - f32(steps) / 100.0;

        col = mix(c2, c1, diff) * ao + vec3<f32>(spec);
    }

    // Add emissive glow
    col += c1 * glow * 0.02;

    // Fog for intense scale
    let fog = exp(-t * 0.1);
    col = mix(vec3<f32>(0.02, 0.02, 0.05), col, fog);

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / 20.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(col, 1.0));
}
