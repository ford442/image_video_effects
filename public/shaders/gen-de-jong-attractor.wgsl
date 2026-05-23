// ═══════════════════════════════════════════════════════════════════
//  Peter de Jong Attractor
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Description: Strange attractor density accumulation for the 2D
//    Peter de Jong map: x' = sin(a·y)−cos(b·x), y' = sin(c·x)−cos(d·y).
//    Parameters slowly morph through time, producing an infinite
//    gallery of intricate lace-work patterns — butterflies, snowflakes,
//    spirographs — as the attractor topology continuously transforms.
//    Temporal Monte Carlo builds density per frame; bass warps geometry.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=speed_a, y=speed_b, z=glow_radius, w=decay

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=speed_a, y=speed_b, z=glowR, w=decay
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var q = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    q = q + dot(q, q.yzx + 33.33);
    return fract((q.xx + q.yz) * q.zy);
}

// De Jong map: one iteration
fn de_jong(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a * p.y) - cos(b * p.x), sin(c * p.x) - cos(d * p.y));
}

// Inigo Quilez cosine palette — maps density to colour
fn palette(t: f32, hueOff: f32) -> vec3<f32> {
    let h = fract(t + hueOff);
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 0.9);
    let d = vec3<f32>(0.10, 0.40, 0.65);
    return clamp(a + b * cos(TAU * (c * h + d)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;
    let time  = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Slowly morphing parameters — each param follows a different sinusoidal phase
    // Bass expands the amplitude (more extreme parameter values → richer topology)
    let amp    = 1.8 + bass * 0.4;
    let sa     = 0.03 + u.zoom_params.x * 0.07;  // speed_a: 0.03–0.10 Hz
    let sb     = 0.02 + u.zoom_params.y * 0.06;  // speed_b: 0.02–0.08 Hz
    let a      = amp * sin(time * sa);
    let b      = amp * sin(time * sb + 1.1);
    let c      = amp * sin(time * sa * 1.33 + 2.2 + mids * 0.5);
    let d      = amp * sin(time * sb * 1.57 + 3.3);

    let glowR  = max(0.015 + u.zoom_params.z * 0.045, 0.005);
    let decay  = 0.965 + u.zoom_params.w * 0.025;

    // Mouse: pan and zoom the view into the attractor
    // Attractor lives in ~[-2,2]²; mouse offsets the view centre
    let mouse  = u.zoom_config.yz;
    let zoom   = 1.0 + u.zoom_config.w * 1.5;  // click zooms in
    let centre = (mouse - 0.5) * 2.0;
    // Pixel → attractor space: [-2,2]² centred on mouse (with zoom)
    let viewPos = (uv - 0.5) * (4.0 / zoom) + centre;

    // Seed starting point from hash — de Jong is bounded so any start works
    let seed   = hash22(uv * 131.7 + vec2<f32>(fract(time * 0.031), fract(time * 0.041 + 0.5)));
    var p      = seed * 4.0 - 2.0;  // uniform start in [-2,2]²

    // Trace 128 steps; accumulate Gaussian kernel contributions to this pixel
    var contrib = 0.0;
    let invR2   = 1.0 / (glowR * glowR);
    // Treble adds a finer inner kernel for sparkle detail
    let innerR2 = max(invR2 * 4.0, invR2);

    for (var i = 0u; i < 128u; i = i + 1u) {
        p = de_jong(p, a, b, c, d);
        let dx = p.x - viewPos.x;
        let dy = p.y - viewPos.y;
        let d2 = dx * dx + dy * dy;
        contrib += exp(-d2 * invR2);
        // Fine-grain sparkle from treble
        contrib += exp(-d2 * innerR2) * treble * 0.25;
    }
    contrib *= (1.0 / 128.0);

    // Temporal accumulation: blend new orbit segment with accumulated density
    let prevDensity = textureLoad(dataTextureC, coord, 0).r;
    let accumulated = mix(contrib, prevDensity, clamp(decay, 0.0, 0.999));

    // Colour mapped from density; hue drifts with time for palette evolution
    let hueOff  = fract(time * 0.015);
    let density = clamp(accumulated * 10.0, 0.0, 1.0);
    let col     = palette(density, hueOff);

    // Alpha: bright attractor regions are more opaque; bass pulses the glow
    let alpha    = clamp(density * 0.85 + bass * 0.12, 0.0, 1.0);
    let finalOut = vec4<f32>(col, alpha);

    // Write accumulated state for next frame's dataTextureC
    textureStore(dataTextureA, coord, vec4<f32>(accumulated, hueOff, 0.0, 0.0));
    textureStore(writeTexture, coord, finalOut);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
