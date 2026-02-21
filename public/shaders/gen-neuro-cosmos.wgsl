// ----------------------------------------------------------------
//  Neuro-Cosmos - Generative visualization of neural/cosmic web
//  Category: generative
//  Features: mouse-driven, 3d raymarching, voronoi
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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Density, y=PulseSpeed, z=Glow, w=Thickness
    ripples: array<vec4<f32>, 50>,
};

// 3D Hash Function
fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Voronoi Map - Returns vec3(F1, F2, CellHash)
// But we mainly need F1 and F2 for the web structure.
// F1 is distance to closest center (Neuron)
// F2 is distance to second closest center (defines Voronoi edges)
fn voronoiMap(p: vec3<f32>) -> vec3<f32> {
    let n = floor(p);
    let f = fract(p);

    var f1 = 1.0;
    var f2 = 1.0;
    var cell_id = vec3<f32>(0.0);

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + g);
                // Animate the points a bit
                let time = u.config.x * 0.1;
                let anim = 0.5 + 0.5 * sin(time + 6.2831 * o);

                let r = g + o - f;
                let d = dot(r, r);

                if (d < f1) {
                    f2 = f1;
                    f1 = d;
                    cell_id = o; // Store hash of closest cell
                } else if (d < f2) {
                    f2 = d;
                }
            }
        }
    }

    // Convert squared distances to Euclidean
    return vec3<f32>(sqrt(f1), sqrt(f2), cell_id.x);
}

// Raymarching Map function
// Returns distance to the "structure" but since this is volumetric,
// we might treat it as density field or just SDF to closest element.
// For a web, we want the space where F2 - F1 is small.
fn map(p: vec3<f32>) -> vec4<f32> {
    // Parameter: Network Density
    let scale = u.zoom_params.x * 2.0;
    let p_scaled = p * scale;

    let v = voronoiMap(p_scaled);
    let f1 = v.x;
    let f2 = v.y;
    let cell_hash = v.z;

    // Neurons are at f1 approx 0 (center of cell)
    // Synapses (Web) are where f2 - f1 approx 0 (edges)

    // Thickness parameter controls how "thick" the web is
    let thickness = u.zoom_params.w * 0.2;

    // Distance to web strand
    // f2 - f1 is distance from Voronoi boundary
    // We want to be "inside" the strand if f2 - f1 < thickness
    // So SDF = (f2 - f1) - thickness
    let d_web = (f2 - f1) - thickness;

    // Distance to neuron (cell center)
    // f1 is distance to center. Neuron radius ~ thickness * 2
    let neuron_radius = thickness * 3.0;
    let d_neuron = f1 - neuron_radius;

    // Combine web and neuron (smooth union)
    let k = 0.1;
    let h = clamp(0.5 + 0.5 * (d_web - d_neuron) / k, 0.0, 1.0);
    let d = mix(d_web, d_neuron, h) - k * h * (1.0 - h);

    // Return distance and cell hash for coloring
    return vec4<f32>(d / scale, cell_hash, f1, f2);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Camera Control
    let mouse = u.zoom_config.yz; // 0..1

    // Orbit camera
    let yaw = (mouse.x - 0.5) * 6.28;
    let pitch = (mouse.y - 0.5) * 3.14;
    let dist = 5.0; // Orbit distance

    // Drifting camera motion
    let time = u.config.x * 0.1;
    let camPos = vec3<f32>(
        dist * sin(yaw + time) * cos(pitch),
        dist * sin(pitch) + sin(time * 0.5),
        dist * cos(yaw + time) * cos(pitch)
    );

    let target = vec3<f32>(0.0, 0.0, 0.0);
    let forward = normalize(target - camPos);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarching
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;
    var hit = false;
    var hit_data = vec4<f32>(0.0);

    // Volumetric march
    for(var i=0; i<80; i++) {
        let p = camPos + rd * t;
        let data = map(p);
        let d = data.x;

        // Accumulate glow based on proximity to structure
        // The closer we are (smaller d), the more glow
        // Intensity controlled by param Z
        let glow_intensity = u.zoom_params.z;
        glow += (0.02 * glow_intensity) / (abs(d) + 0.05);

        if (d < 0.002) {
            hit = true;
            hit_data = data;
            break;
        }

        if (t > 20.0) { break; }
        t += d * 0.8; // Step size
    }

    // Base colors
    let col_neuron_core = vec3<f32>(1.0, 0.9, 0.7); // Bright warm core
    let col_neuron_outer = vec3<f32>(0.2, 0.5, 1.0); // Blue outer
    let col_synapse = vec3<f32>(0.1, 0.8, 0.9); // Cyan web
    let bg_col = vec3<f32>(0.02, 0.0, 0.05); // Deep space

    if (hit) {
        let p = camPos + rd * t;
        let n = calcNormal(p);

        let f1 = hit_data.z;
        let f2 = hit_data.w;
        let hash = hit_data.y;

        // Lighting
        let lightPos = vec3<f32>(2.0, 5.0, 2.0);
        let lightDir = normalize(lightPos - p);
        let diff = max(dot(n, lightDir), 0.2);

        // Pulse animation
        // Pulse travels along strands based on distance from center (f1)
        let pulse_speed = u.zoom_params.y * 5.0;
        let pulse = sin(f1 * 10.0 - u.config.x * pulse_speed);
        let pulse_strength = smoothstep(0.8, 1.0, pulse);

        // Determine if Neuron or Web
        // Based on f1 value (small f1 = closer to center)
        let is_neuron = smoothstep(0.2, 0.0, f1);

        var object_col = mix(col_synapse, col_neuron_outer, is_neuron);

        // Add core glow to neuron
        object_col = mix(object_col, col_neuron_core, is_neuron * smoothstep(0.1, 0.0, f1));

        // Add pulse to web
        object_col += col_synapse * pulse_strength * (1.0 - is_neuron);

        col = object_col * diff;

        // Rim lighting for 3D feel
        let rim = 1.0 - max(dot(n, -rd), 0.0);
        col += vec3<f32>(0.2, 0.4, 1.0) * pow(rim, 3.0);

    } else {
        col = bg_col;
    }

    // Apply volumetric glow
    // Glow color changes slightly based on view direction or time
    let glow_col = vec3<f32>(0.1, 0.2, 0.5) + vec3<f32>(0.1, 0.0, 0.2) * sin(u.config.x);
    col += glow * glow_col;

    // Distance fog
    col = mix(col, bg_col, 1.0 - exp(-t * 0.1));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(t / 20.0, 0.0, 0.0, 0.0));
}
