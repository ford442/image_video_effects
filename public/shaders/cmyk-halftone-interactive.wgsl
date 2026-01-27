// ═══════════════════════════════════════════════════════════════
//  CMYK Halftone Interactive
//  Separates image into CMYK channels and applies rotatable halftone screens.
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=ResX, z=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=AngleOffset, z=Spread, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

fn rgb2cmyk(rgb: vec3<f32>) -> vec4<f32> {
    let k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
    if (k >= 1.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let c = (1.0 - rgb.r - k) / (1.0 - k);
    let m = (1.0 - rgb.g - k) / (1.0 - k);
    let y = (1.0 - rgb.b - k) / (1.0 - k);
    return vec4<f32>(c, m, y, k);
}

fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a);
    let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz; // 0-1

    // Params
    let density = 50.0 + u.zoom_params.x * 150.0;
    let baseAngle = u.zoom_params.y * 3.14159;
    let spread = u.zoom_params.z * 0.05; // Max shift
    let inkDarkness = 0.5 + u.zoom_params.w * 0.5;

    // Mouse Interaction
    // Mouse X adds rotation
    let interactAngle = (mouse.x - 0.5) * 3.14159;
    // Mouse Y adds separation/spread
    let interactSpread = mouse.y * 0.1;

    let finalSpread = spread + interactSpread;

    // Sample Source
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let cmyk = rgb2cmyk(srcColor);

    // Standard Angles (in radians)
    // C: 15, M: 75, Y: 0, K: 45
    let angC = radians(15.0) + baseAngle + interactAngle;
    let angM = radians(75.0) + baseAngle + interactAngle;
    let angY = radians(0.0)  + baseAngle + interactAngle;
    let angK = radians(45.0) + baseAngle + interactAngle;

    // Offsets for spread (simulate misregistration)
    // Shift each channel slightly away from center
    let offC = vec2<f32>(-1.0, 0.0) * finalSpread;
    let offM = vec2<f32>(1.0, 0.0) * finalSpread;
    let offY = vec2<f32>(0.0, -1.0) * finalSpread;
    let offK = vec2<f32>(0.0, 1.0) * finalSpread;

    // Helper to calculate dot presence
    // Returns 1.0 if ink, 0.0 if paper (soft edge)
    // val is the ink amount (0-1)

    var finalC = 0.0;
    var finalM = 0.0;
    var finalY = 0.0;
    var finalK = 0.0;

    // Function inlined manually because WGSL scope/closure limits
    // Cyan
    {
        let localUV = rotate((uv + offC) * vec2<f32>(aspect, 1.0), angC) * density;
        let grid = fract(localUV) - 0.5;
        let dist = length(grid);
        // Radius depends on ink amount. Area ~ val. R ~ sqrt(val).
        // Max radius = 0.707 (touching). Let's say 0.6 to avoid too much blotch.
        let radius = sqrt(cmyk.x) * 0.6;
        finalC = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
    }

    // Magenta
    {
        let localUV = rotate((uv + offM) * vec2<f32>(aspect, 1.0), angM) * density;
        let grid = fract(localUV) - 0.5;
        let dist = length(grid);
        let radius = sqrt(cmyk.y) * 0.6;
        finalM = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
    }

    // Yellow
    {
        let localUV = rotate((uv + offY) * vec2<f32>(aspect, 1.0), angY) * density;
        let grid = fract(localUV) - 0.5;
        let dist = length(grid);
        let radius = sqrt(cmyk.z) * 0.6;
        finalY = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
    }

    // Black
    {
        let localUV = rotate((uv + offK) * vec2<f32>(aspect, 1.0), angK) * density;
        let grid = fract(localUV) - 0.5;
        let dist = length(grid);
        let radius = sqrt(cmyk.w) * 0.6;
        finalK = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
    }

    // Composite Subtractive
    // Start with White
    var color = vec3<f32>(1.0);

    // Subtract inks (Cyan absorbs Red, etc)
    // Cyan color is (0, 1, 1). It subtracts Red.
    // Magenta (1, 0, 1). Subtracts Green.
    // Yellow (1, 1, 0). Subtracts Blue.

    // Simple mix model
    let cColor = vec3<f32>(0.0, 1.0, 1.0); // Pure Cyan
    let mColor = vec3<f32>(1.0, 0.0, 1.0);
    let yColor = vec3<f32>(1.0, 1.0, 0.0);
    let kColor = vec3<f32>(0.0, 0.0, 0.0);

    // Multiply blend (standard for print simulation)
    // Paper is 1.0.
    // If Cyan dot is present (finalC = 1), we multiply by Cyan Color (or mix white to cyan).

    let mixC = mix(vec3<f32>(1.0), cColor, finalC * inkDarkness);
    let mixM = mix(vec3<f32>(1.0), mColor, finalM * inkDarkness);
    let mixY = mix(vec3<f32>(1.0), yColor, finalY * inkDarkness);
    let mixK = mix(vec3<f32>(1.0), kColor, finalK * inkDarkness);

    color = color * mixC * mixM * mixY * mixK;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
