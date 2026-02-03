// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BurnRadius, y=BurnSpeed, z=GrainStrength, w=EdgeGlow
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pos = p;
    // Simple rotation
    let rot = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Parameters
    let radius_param = u.zoom_params.x; // 0 to 1
    let speed = u.zoom_params.y * 2.0;
    let grain_str = u.zoom_params.z;
    let glow_width = u.zoom_params.w * 0.2 + 0.01;

    // Base Burn Radius
    let burn_radius = radius_param * 0.8;

    // Calculate distance to mouse
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Burn Shape Generation
    // We want the edge to be jagged.
    // effective_dist = dist - noise
    let noise_scale = 10.0;
    let noise_val = fbm(uv * noise_scale + vec2<f32>(time * speed * 0.1, 0.0));

    // Distort the distance field with noise
    let distorted_dist = dist - noise_val * 0.2; // 0.2 is noise amplitude

    // States:
    // 1. Burnt (Hole): distorted_dist < burn_radius
    // 2. Burning Edge: distorted_dist is close to burn_radius
    // 3. Intact Film: distorted_dist > burn_radius

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Apply Film Grain to intact part (and everywhere really, simpler)
    let grain = hash12(uv * time * 100.0) * grain_str * 0.2;
    // Sepia / Old Film tint
    let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let sepia = vec3<f32>(gray * 1.2, gray * 1.0, gray * 0.8);
    color = mix(color, sepia + grain, 0.5); // Mix original with sepia/grain

    // Calculate Burn Masks
    // Smoothstep for anti-aliased edge
    // Edge goes from burn_radius (burnt) to burn_radius + glow_width (clean)

    // 'hole' is 1.0 where burnt, 0.0 where clean
    let hole = 1.0 - smoothstep(burn_radius, burn_radius + 0.02, distorted_dist);

    // 'edge' is the glowing band
    // Peak at burn_radius, falloff outwards
    // We can use a bell curve or just difference of smoothsteps
    let outer_edge = smoothstep(burn_radius, burn_radius + glow_width, distorted_dist);
    let inner_edge = smoothstep(burn_radius - 0.05, burn_radius, distorted_dist);
    let fire_mask = inner_edge - outer_edge; // Positive band?
    // Wait:
    // dist < R : hole = 1.
    // dist > R : hole = 0.

    // Better fire logic:
    // normalize distance around radius
    let d = distorted_dist - burn_radius; // < 0 is hole, > 0 is film

    var final_color = color;

    if (d < 0.0) {
        // Inside hole: Black/Charred
        final_color = vec3<f32>(0.0);
        // Optional: Inner glow (ember)
        let inner_glow = smoothstep(-0.1, 0.0, d); // 0 to 1 near edge
        final_color += vec3<f32>(1.0, 0.2, 0.0) * inner_glow * 0.5;
    } else if (d < glow_width) {
        // Burning Edge
        let t = d / glow_width; // 0 to 1
        // Gradient: White -> Yellow -> Red -> Dark
        let fire = mix(vec3<f32>(1.0, 1.0, 0.8), vec3<f32>(1.0, 0.3, 0.0), t);
        fire = mix(fire, vec3<f32>(0.1, 0.0, 0.0), t * t);

        // Add noise/sparkle to fire
        let sparkle = step(0.5, noise(uv * 50.0 + time * 10.0));
        fire += sparkle * 0.5 * (1.0 - t);

        final_color = fire;
    } else {
        // Intact film (with grain applied earlier)
        // Add slight darkening near fire
        let smoke = smoothstep(glow_width, glow_width * 3.0, d);
        final_color *= (0.5 + 0.5 * smoke);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
}
