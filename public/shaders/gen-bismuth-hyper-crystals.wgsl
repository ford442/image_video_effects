// ----------------------------------------------------------------
// Bismuth Hyper-Crystals
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Param
  zoom_params: vec4<f32>,  // x=Complexity, y=ColorShift, z=GrowthSpeed, w=Specular
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    // Mouse distortion
    let mousePos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
    let distToMouse = length(p - mousePos);

    // Audio reactivity: use extraBuffer[0] (bass) to modulate rotation
    let bass = extraBuffer[0];

    // Domain repetition and folding
    for(var i = 0; i < i32(u.zoom_params.x * 5.0 + 3.0); i = i + 1) {
        p = abs(p) - 1.0;

        let r = rot(u.config.x * u.zoom_params.z * 0.1 + bass * 0.5);
        let pxz = r * vec2<f32>(p.x, p.z);
        p.x = pxz.x;
        p.z = pxz.y;
    }

    // Hopper crystal base (stepped box)
    let q = abs(p) - vec3<f32>(1.0);
    var d = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);

    // Apply stepping
    d = d - 0.1 * floor(length(p) * 10.0) / 10.0;

    return d;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

fn iridescence(thickness: f32) -> vec3<f32> {
    // Audio reactivity: use extraBuffer[1] or bass to shift color phase slightly
    let audioShift = extraBuffer[0] * 0.2;
    // Thin film interference approximation
    let phase = thickness * 5.0 + u.zoom_params.y * 3.14 + audioShift;
    return 0.5 + 0.5 * cos(6.28318 * (phase + vec3<f32>(0.0, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let uv = vec2<f32>(id.xy) / vec2<f32>(dimensions);
    let uv_centered = (uv - 0.5) * 2.0;
    let aspect = f32(dimensions.x) / f32(dimensions.y);
    let p_screen = vec2<f32>(uv_centered.x * aspect, uv_centered.y);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(p_screen, 1.0));

    // Raymarching
    var dO: f32 = 0.0;
    var hit: bool = false;
    var p: vec3<f32>;
    var steps: i32 = 0;

    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        steps = i;
        p = ro + rd * dO;
        let dS = map(p);
        dO = dO + dS;
        if (dS < SURF_DIST) {
            hit = true;
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));

        // Lighting
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(n, halfDir), 0.0), u.zoom_params.w * 100.0);

        // Iridescence based on position and normal
        // Mouse interaction shifts the color locally
        let mousePos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
        let distToMouse = length(p - mousePos);
        let mouseThicknessShift = max(0.0, 1.0 - distToMouse * 0.5) * 0.2;

        let thickness = length(p) * 0.1 + dot(n, viewDir) * 0.5 + mouseThicknessShift;
        let albedo = iridescence(thickness);

        col = albedo * (diff * 0.5 + 0.5) + vec3<f32>(spec);

        // Fake AO
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);
        col = col * ao;
    }

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
