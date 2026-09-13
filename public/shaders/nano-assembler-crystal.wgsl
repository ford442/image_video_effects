// ═══════════════════════════════════════════════════════════════════
//  Nano Assembler Crystal
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12
//  Ideas: hex facet lock of orientation; recalescence glow from latent heat
//  A packing: raw (phase, temp, orientation, impurity)
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

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = fract(p * vec2<f32>(0.1031, 0.1030));
    p2 += dot(p2, p2.yx + 33.33);
    return fract((p2.xx + p2.yx) * p2.xy);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn stateAt(coord: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let prevState = stateAt(coord, dims);
    var phase = prevState.r;
    var temp = prevState.g;
    var orientation = prevState.b;
    var impurity = prevState.a;

    if (time < 0.1) {
        phase = 0.0;
        temp = -0.2;
        orientation = 0.0;
        impurity = hash12(uv * 100.0) * 0.1;
        let seed_grid = 20.0;
        let cell_uv_seed = fract(uv * seed_grid);
        let cell_center = length(cell_uv_seed - vec2<f32>(0.5));
        if (cell_center < 0.05) {
            phase = 1.0;
            temp = 0.0;
            orientation = atan2(uv.y - 0.5, uv.x - 0.5);
        }
    }

    phase = clamp(phase, 0.0, 1.0);
    temp = clamp(temp, -1.0, 1.0);
    impurity = clamp(impurity, 0.0, 1.0);

    let assembly_progress = u.zoom_params.x;
    let particle_density = u.zoom_params.y;
    let scatter_force = u.zoom_params.z;
    let rebuild_speed = u.zoom_params.w;

    let grid_size = mix(50.0, 5.0, particle_density);
    let grid_coord = floor(uv * grid_size) / grid_size;
    let cell_uv = fract(uv * grid_size);

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = u.config.z / max(u.config.w, 1.0);
    let dist_vec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(dist_vec);
    let mouse_repel = smoothstep(0.2, 0.0, mouseDist);

    let current_state = clamp(assembly_progress - mouse_repel * scatter_force * (1.0 + audio.x * 0.2), 0.0, 1.0);
    let pulse = 0.5 + 0.5 * sin(time * rebuild_speed * 2.0);
    let anim_state = mix(current_state, current_state * pulse, rebuild_speed * 0.5);

    phase = mix(phase, anim_state, 0.02);

    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);

    let lapPhase = left.r + right.r + down.r + up.r - 4.0 * phase;

    let anisotropy = mix(0.0, 0.5, u.zoom_params.y);
    let angle = orientation;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let gradPhase = vec2<f32>(right.r - left.r, up.r - down.r) * 0.5;
    let alignment = abs(dot(normalize(gradPhase + vec2<f32>(0.0001)), dir));
    let anisoFactor = 1.0 + anisotropy * (alignment - 0.5) * 2.0;

    let supercooling = mix(0.1, 0.8, u.zoom_params.x);
    let growthRate = mix(0.001, 0.01, u.zoom_params.z) * (1.0 + audio.y * 0.25);
    let m = temp + supercooling * (1.0 - 2.0 * impurity);
    let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + m * 0.5);

    phase += phaseReaction * growthRate * anisoFactor + lapPhase * 0.1 * growthRate;
    phase = clamp(phase, 0.0, 1.0);

    let lapTemp = left.g + right.g + down.g + up.g - 4.0 * temp;
    let latentHeat = (phase - prevState.r) * 0.5;
    temp += lapTemp * 0.05 + latentHeat;
    temp = clamp(temp, -1.0, 1.0);

    let lapOrient = left.b + right.b + down.b + up.b - 4.0 * orientation;
    orientation += lapOrient * 0.01 * phase;
    if (phase > 0.1 && phase < 0.9) {
        orientation = mix(orientation, atan2(gradPhase.y, gradPhase.x), 0.05);
    }

    // Idea 1 — hex facet lock: snap orientation to 60° when phase is high
    let hexStep = 6.28318530718 / 6.0;
    let snapped = round(orientation / hexStep) * hexStep;
    orientation = mix(orientation, snapped, smoothstep(0.55, 0.92, phase) * 0.35);

    let lapImpurity = left.a + right.a + down.a + up.a - 4.0 * impurity;
    let phaseChange = phase - prevState.r;
    impurity += lapImpurity * 0.02 - phaseChange * 0.1;
    impurity = clamp(impurity, 0.0, 1.0);

    let mouseInfluence = smoothstep(0.04, 0.0, mouseDist) * mouseDown;
    if (mouseDown > 0.5) {
        phase = mix(phase, 0.0, mouseInfluence * 0.5);
        temp = mix(temp, 0.3, mouseInfluence);
    }

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.3 && rDist < 0.03) {
            let nucleation = smoothstep(0.03, 0.0, rDist) * max(0.0, 1.0 - age * 3.0);
            phase = mix(phase, 1.0, nucleation * 0.5);
        }
    }
    phase = clamp(phase, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(phase, temp, orientation, impurity));

    let border = 0.1;
    let cell_dist = max(abs(cell_uv.x - 0.5), abs(cell_uv.y - 0.5)) * 2.0;
    let core_radius = 0.5 - border;
    let bot_alpha = exp(-pow(max(0.0, cell_dist - core_radius) / max(border * 0.5, 0.0001), 2.0) * 2.0);

    let orientNorm = fract(orientation / 6.283185307);
    let h6 = orientNorm * 6.0;
    let c = 0.8;
    let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var crystalColor: vec3<f32>;
    if (h6 < 1.0) { crystalColor = vec3(c, x, 0.3); }
    else if (h6 < 2.0) { crystalColor = vec3(x, c, 0.3); }
    else if (h6 < 3.0) { crystalColor = vec3(0.3, c, x); }
    else if (h6 < 4.0) { crystalColor = vec3(0.3, x, c); }
    else if (h6 < 5.0) { crystalColor = vec3(x, 0.3, c); }
    else { crystalColor = vec3(c, 0.3, x); }

    let liquidColor = vec3<f32>(0.05, 0.08, 0.15) * (1.0 + temp * 0.5);
    let disassembled_glow = vec3<f32>(0.2, 0.8, 1.0) * bot_alpha * (1.0 - phase);

    let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
    let interfaceColor = vec3<f32>(0.9, 0.95, 1.0);

    var displayColor = mix(liquidColor, crystalColor, smoothstep(0.4, 0.6, phase));
    displayColor = mix(displayColor, interfaceColor, interfaceMask * 0.5);
    displayColor += disassembled_glow;

    // Idea 2 — recalescence glow from the latent-heat temperature spike
    let recalescence = max(latentHeat, 0.0) * (1.4 + audio.z * 0.5);
    displayColor += vec3<f32>(1.0, 0.82, 0.45) * recalescence * 3.2;

    displayColor = mix(displayColor, vec3<f32>(0.8, 0.6, 0.4), impurity * 0.3);

    let edge_dist = abs(cell_dist - core_radius);
    let edge_highlight = (1.0 - smoothstep(0.0, 0.05, edge_dist)) * (1.0 - anim_state);
    displayColor += vec3<f32>(0.0, 1.0, 1.0) * edge_highlight;

    let mapped = aces(max(displayColor, vec3<f32>(0.0)));
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = clamp(src.a * 0.15 + phase * 0.7 + recalescence * 2.0 + bot_alpha * (1.0 - phase) * 0.35, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
