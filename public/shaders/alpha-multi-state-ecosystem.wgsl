// ═══════════════════════════════════════════════════════════════════
//  Alpha Multi-State Ecosystem
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Species 1 density (0.0 to 1.0+)
//    G = Species 2 density
//    B = Resource level (shared food)
//    A = Toxin concentration
//  Why f32: Continuous densities require sub-1% precision for stable
//  competitive dynamics. 8-bit quantization causes extinction cascades.
// ═══════════════════════════════════════════════════════════════════

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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var s1 = prevState.r;
    var s2 = prevState.g;
    var resource = prevState.b;
    var toxin = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        s1 = 0.0;
        s2 = 0.0;
        resource = 0.5;
        toxin = 0.0;
        // Seed species 1 clusters
        let n1 = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        if (n1 > 0.92) { s1 = 0.8; }
        // Seed species 2 clusters
        let n2 = fract(sin(dot(uv + vec2<f32>(5.0), vec2<f32>(93.0, 17.0))) * 271.0);
        if (n2 > 0.95) { s2 = 0.7; }
    }

    // Clamp
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resource = clamp(resource, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === DIFFUSION ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapS1 = left.r + right.r + down.r + up.r - 4.0 * s1;
    let lapS2 = left.g + right.g + down.g + up.g - 4.0 * s2;
    let lapResource = left.b + right.b + down.b + up.b - 4.0 * resource;
    let lapToxin = left.a + right.a + down.a + up.a - 4.0 * toxin;

    // === PARAMETERS ===
    let growthRate1 = mix(0.02, 0.08, u.zoom_params.x);
    let growthRate2 = mix(0.015, 0.06, u.zoom_params.y);
    let toxinDecay = 0.95;
    let resourceRegen = 0.001;
    let dt = 0.5;

    // === ECOSYSTEM DYNAMICS ===
    // Species consume resource to grow
    let food1 = s1 * resource * growthRate1;
    let food2 = s2 * resource * growthRate2;

    // Competition: species inhibit each other
    let competition = s1 * s2 * 0.1;

    // Species produce toxin
    let toxinProduction1 = s1 * 0.005;
    let toxinProduction2 = s2 * 0.003;

    // Toxin hurts both species
    let toxinDamage = toxin * 0.02;

    // Resource regeneration
    resource += resourceRegen - food1 - food2;
    resource += lapResource * 0.1;

    // Species update
    s1 += food1 - competition - toxinDamage + lapS1 * 0.05;
    s2 += food2 - competition - toxinDamage + lapS2 * 0.05;

    // Toxin update
    toxin += toxinProduction1 + toxinProduction2 - toxin * 0.01;
    toxin += lapToxin * 0.08;
    toxin *= toxinDecay;

    // Natural death
    s1 *= 0.998;
    s2 *= 0.998;

    // Clamp
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resource = clamp(resource, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === MOUSE INTERACTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
    // Mouse adds resource and removes toxin (nurturing)
    resource += mouseInfluence * 0.5;
    toxin -= mouseInfluence * 0.3;
    toxin = max(toxin, 0.0);

    // Ripples seed new life
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.0 && rDist < 0.04) {
            let strength = smoothstep(0.04, 0.0, rDist) * max(0.0, 1.0 - age);
            let sign = select(1.0, 0.0, f32(i) % 2.0 < 1.0);
            s1 += strength * sign * 0.5;
            s2 += strength * (1.0 - sign) * 0.5;
        }
    }
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(s1, s2, resource, toxin));

    // === VISUALIZATION ===
    // Species 1 = cyan/teal, Species 2 = magenta/pink, Resource = green, Toxin = dark purple
    let colorS1 = vec3<f32>(0.0, 0.8, 1.0) * min(s1, 1.0);
    let colorS2 = vec3<f32>(1.0, 0.2, 0.6) * min(s2, 1.0);
    let colorResource = vec3<f32>(0.2, 0.7, 0.2) * min(resource, 1.0) * 0.3;
    let colorToxin = vec3<f32>(0.3, 0.0, 0.4) * min(toxin, 1.0) * 0.5;

    var displayColor = colorS1 + colorS2 + colorResource + colorToxin;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Highlight edges where species meet
    let s1Grad = length(vec2<f32>(left.r - right.r, down.r - up.r));
    let s2Grad = length(vec2<f32>(left.g - right.g, down.g - up.g));
    let edgeHighlight = (s1Grad + s2Grad) * 2.0;
    displayColor += vec3<f32>(1.0, 0.9, 0.5) * edgeHighlight * 0.3;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, s1 + s2));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
