// ----------------------------------------------------------------
// Aethereal Ferrofluid Chrono-Core
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

// 4D Simplex noise approximation
fn hash4(p: vec4<f32>) -> f32 {
    let p_frac = fract(p * vec4<f32>(0.1031, 0.1030, 0.0973, 0.1099));
    let h = dot(p_frac, p_frac.wzxy + 33.33);
    return fract(h * h);
}

fn snoise4(v: vec4<f32>) -> f32 {
    let C = vec4<f32>(
        0.138196601125011,  // (5 - sqrt(5))/20  G4
        0.276393202250021,  // 2 * G4
        0.414589803375032,  // 3 * G4
        -0.447213595499958  // -1 + 4 * G4
    );

    let i = floor(v + dot(v, vec4<f32>(0.309016994374947))); // (sqrt(5) - 1)/4
    var x0 = v - i + dot(i, vec4<f32>(C.x));

    let i0 = step(x0.yzwx, x0.xyzw);
    let i1 = step(x0.wxyz, x0.xyzw);
    let i2 = step(x0.zwxy, x0.xyzw);

    let j0 = i0 * (1.0 - i1);
    let j1 = i1 * (1.0 - i2);
    let j2 = i2 * (1.0 - i0);

    let i3 = clamp(j0 + j1 + j2, vec4<f32>(0.0), vec4<f32>(1.0));

    // this is a simplified noise for performance and aesthetics
    return fract(sin(dot(v, vec4<f32>(12.9898, 78.233, 45.164, 94.673))) * 43758.5453);
}

fn simplex3d(p: vec3<f32>) -> f32 {
    let i = floor(p + dot(p, vec3<f32>(1.0 / 3.0)));
    let x0 = p - i + dot(i, vec3<f32>(1.0 / 6.0));

    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);

    let x1 = x0 - i1 + vec3<f32>(1.0 / 6.0);
    let x2 = x0 - i2 + vec3<f32>(1.0 / 3.0);
    let x3 = x0 - 1.0 + vec3<f32>(0.5);

    // Smooth
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453) * 2.0 - 1.0;
}

// 3D Voronoi for spike placement
fn voronoi(x: vec3<f32>) -> vec3<f32> {
    let p = floor(x);
    let f = fract(x);

    var res = vec3<f32>(8.0);

    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash33(p + b);
                let d = dot(r, r);

                if(d < res.x) {
                    res.y = res.x;
                    res.x = d;
                    res.z = hash33(p + b).x;
                } else if(d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return vec3<f32>(sqrt(res.x), sqrt(res.y), res.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hue2rgb(hue: f32) -> vec3<f32> {
    let R = abs(hue * 6.0 - 3.0) - 1.0;
    let G = 2.0 - abs(hue * 6.0 - 2.0);
    let B = 2.0 - abs(hue * 6.0 - 4.0);
    return saturate(vec3<f32>(R, G, B));
}

fn map(p: vec3<f32>, time: f32, audio_mod: f32) -> vec2<f32> { // returns vec2(sdf, id)
    var d = length(p) - 1.5; // Base sphere

    // Viscosity (zoom_params.x) controls temporal speed and noise amplitude
    let viscosity = u.zoom_params.x;
    // Spike Density (zoom_params.y) controls voronoi frequency
    let density = u.zoom_params.y * 5.0 + 1.0;

    // Audio affects temporal flow
    let t = time * viscosity * (1.0 + audio_mod * 0.5);

    // Apply Voronoi for spikes
    let v = voronoi(p * density + vec3<f32>(0.0, t * 0.2, 0.0));

    // Smooth out the voronoi cells to make spikes
    let spike_shape = 1.0 - v.x;

    // Apply 4D Simplex noise approximation for flow
    let flow = simplex3d(p * 2.0 + vec3<f32>(sin(t), cos(t), t * 0.5));

    let spike_displacement = (spike_shape * 0.5 + flow * 0.2) * (1.0 - viscosity * 0.5);

    d = d - spike_displacement;

    // Mouse Interaction: Magnetic Dipole
    var d_final = d;
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = u.zoom_config.xy; // 0 to 1
        // Convert to world space rough approx (depends on camera setup)
        let mouse_world = vec3<f32>((mouse_uv.x - 0.5) * 10.0, (0.5 - mouse_uv.y) * 10.0, 0.0);

        let magnetic_strength = u.zoom_params.z;
        let dist_to_mouse = length(p - mouse_world);

        // Create a well towards the mouse
        let pull = exp(-dist_to_mouse * 0.5) * magnetic_strength * 2.0;

        // Stretch geometry towards mouse
        d_final = smin(d_final, dist_to_mouse - pull, 0.8);
    }

    // ID based on spike shape for coloring
    return vec2<f32>(d_final, spike_shape);
}

fn get_normal(p: vec3<f32>, time: f32, audio_mod: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio_mod).x - map(p - e.xyy, time, audio_mod).x,
        map(p + e.yxy, time, audio_mod).x - map(p - e.yxy, time, audio_mod).x,
        map(p + e.yyx, time, audio_mod).x - map(p - e.yyx, time, audio_mod).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.xy);
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let uv = (fragCoord - 0.5 * resolution) / resolution.y;

    let time = u.config.z;

    // Extract Audio
    let bass = extraBuffer[0];
    let bassSmooth = extraBuffer[133]; // Using smooth for less flicker

    // Camera
    var ro = vec3<f32>(0.0, 0.0, 4.0);
    let target_pt = vec3<f32>(0.0, 0.0, 0.0);

    // Mouse orbit
    if (u.zoom_config.w > 0.0) {
        let mouse_orbit_x = (u.zoom_config.x - 0.5) * PI * 2.0;
        let mouse_orbit_y = (u.zoom_config.y - 0.5) * PI;
        let rotX = rot2D(mouse_orbit_y);
        let rotY = rot2D(-mouse_orbit_x);

        var temp_ro = vec3<f32>(0.0, 0.0, 4.0);
        let yz = temp_ro.yz * rotX;
        temp_ro = vec3<f32>(temp_ro.x, yz.x, yz.y);
        let xz = temp_ro.xz * rotY;
        temp_ro = vec3<f32>(xz.x, temp_ro.y, xz.y);
        ro = temp_ro;
    }

    let ww = normalize(target_pt - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var mat_id = 0.0;
    var p = ro;
    var steps: i32 = 0;

    for(var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let res = map(p, time, bassSmooth);
        d = res.x;
        mat_id = res.y;

        if (abs(d) < 0.001 || t > 20.0) {
            steps = i;
            break;
        }
        t += d;
    }

    var col = vec3<f32>(0.05, 0.05, 0.08); // Background
    var depth = 1.0; // Far clip

    if (t < 20.0) {
        // Hit
        let n = get_normal(p, time, bassSmooth);

        // Lighting
        let l = normalize(vec3<f32>(1.0, 1.0, 2.0));
        let v = -rd;
        let h = normalize(l + v);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        // Iridescent coloring based on fresnel and normal
        let iridescence_hue = fract(dot(n, vec3<f32>(0.5)) * 0.5 + time * 0.1);
        let iridescence = hue2rgb(iridescence_hue) * fresnel;

        // Fake Ambient Occlusion based on steps
        let ao = 1.0 - f32(steps) / 100.0;

        // Base metallic color
        var mat_col = vec3<f32>(0.1, 0.12, 0.15) * diff + spec * vec3<f32>(1.0) + iridescence * 2.0;

        // Bioluminescence in the valleys (based on spike shape/id inverted)
        // High mat_id means spike peak, low means valley
        let valley = saturate(1.0 - mat_id * 2.0);
        let bio_color = vec3<f32>(0.0, 0.8, 1.0) * valley; // Cyan glow
        let bioluminescence_intensity = u.zoom_params.w;

        // Modulate bio color with audio
        let bio = bio_color * bioluminescence_intensity * (1.0 + bass * 2.0) * ao;

        col = mat_col * ao + bio;

        // Depth
        let ndc = vec4<f32>(p, 1.0);
        depth = (t - 0.1) / (20.0 - 0.1);
    }

    // Output
    let store_coord = vec2<i32>(global_id.xy);
    textureStore(writeTexture, store_coord, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, store_coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // History
    textureStore(dataTextureA, store_coord, vec4<f32>(col, 1.0));
}
