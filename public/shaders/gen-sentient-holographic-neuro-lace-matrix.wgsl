// ----------------------------------------------------------------
// Sentient Holographic Neuro-Lace Matrix
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Fractal Complexity, y=Pulse Intensity, z=Neon Saturation, w=Bioluminescent Fog
    ripples: array<vec4<f32>, 50>,
};

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

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Distance estimator for the neuro-lace
fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Audio reactivity
    let bass = extraBuffer[0];

    // Mouse distortion
    let mousePos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
    let distToMouse = length(p - mousePos);
    if (distToMouse < 2.0) {
        // Pull strands towards mouse
        p -= normalize(p - mousePos) * (2.0 - distToMouse) * 0.5;
    }

    // Domain repetition
    let spacing = 2.0;
    p = (fract(p / spacing + 0.5) - 0.5) * spacing;

    // Construct gyroid-like intertwined lattice
    let scale = u.zoom_params.x * 2.0 + 1.0;
    var d = (dot(sin(p * scale), cos(p.zxy * scale)) - 0.5) / scale;

    // Add pulsing thickness
    d -= 0.1 + bass * 0.05 * sin(u.config.x * u.zoom_params.z + p.y * 10.0);

    return d;
}

// Normal calculation
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

// Main compute shader
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(dimensions)) / f32(dimensions.y);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0 - u.config.x * u.zoom_params.z * 0.5);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    var p = ro;
    var t = 0.0;
    var steps: i32 = 0;
    var hit = false;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d < SURF_DIST) {
            hit = true;
            steps = i;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d;
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0) * u.zoom_params.w;

        let colorShift = u.zoom_params.y;
        let baseColor = vec3<f32>(0.1, 0.5 + colorShift * 0.5, 0.8 - colorShift * 0.3);

        // Ambient occlusion based on steps
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        col = baseColor * diff * ao + spec;
    } else {
        // Background glow
        col = vec3<f32>(0.01, 0.02, 0.05);
    }

    // Post-processing (holographic scanlines)
    col *= 0.9 + 0.1 * sin(uv.y * 100.0 + u.config.x * 5.0);

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
