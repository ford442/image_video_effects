// ----------------------------------------------------------------
// Abyssal Geode Matrix
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let p_abs = abs(p);
    return (p_abs.x + p_abs.y + p_abs.z - s) * 0.57735027;
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction (Gravity Well)
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
        let d2 = length(p - mouse_pos);
        if (d2 < 2.0) {
            let force = (2.0 - d2) * u.zoom_params.x * 2.0;
            p = mix(p, mouse_pos, force * 0.1);
        }
    }

    // Domain Repetition
    let c = 4.0;
    p = (fract(p/c + 0.5) - 0.5) * c;

    // Fractal Fold
    var s = 1.0;
    let t = u.config.x * u.zoom_params.y;
    for(var i=0; i<i32(4.0 + u.zoom_params.w * 3.0); i++) {
        p = abs(p) - vec3<f32>(1.0, 0.5, 0.2) * s;
        let r_mat = rot(t * 0.2 + f32(i));
        p = vec3<f32>(r_mat * p.xy, p.z);
        p = vec3<f32>(p.x, r_mat * p.yz);
        s *= 0.5;
    }

    let d1 = sdOctahedron(p, 1.5 * s);
    return d1;
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
    let dimensions = vec2<f32>(u.config.zw);
    let coord = vec2<f32>(f32(id.x), f32(id.y));
    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }

    let uv = (coord - 0.5 * dimensions) / dimensions.y;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5); // move forward
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Raymarching
    var dO = 0.0;
    var p = vec3<f32>(0.0);
    var glow = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        p = ro + rd * dO;
        let dS = map(p);
        dO += dS;
        // Accumulate glow near surfaces
        glow += 0.01 / (0.01 + dS*dS);
        if(dO > MAX_DIST || dS < SURF_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    if(dO < MAX_DIST) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ao = 1.0 - f32(MAX_STEPS) / 100.0; // Fake AO

        let baseCol = vec3<f32>(0.05, 0.15, 0.25); // Deep sea
        col = baseCol * diff * ao;
    }

    // Bioluminescence based on audio and proximity
    let emissiveColor = vec3<f32>(0.0, 1.0, 1.0) * bass + vec3<f32>(1.0, 0.0, 1.0) * mids;
    col += glow * emissiveColor * u.zoom_params.z;

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
