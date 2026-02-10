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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// --- SDF Primitives ---

fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

fn sdCross(p: vec2<f32>, s: f32, t: f32) -> f32 {
    let b = vec2<f32>(s, t);
    let d1 = sdBox(p, b);
    let d2 = sdBox(p, b.yx);
    return min(d1, d2);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// Procedural Glyph drawing
// uv is local 0.0-1.0 within cell
fn get_character(id: i32, uv: vec2<f32>) -> f32 {
    let p = uv - 0.5; // Center coords: -0.5 to 0.5
    var d = 1.0;

    // 0: Empty / Dot
    if (id == 0) {
        return 0.0;
    }
    // 1: Small Dot (.)
    else if (id == 1) {
        d = sdCircle(p, 0.05);
    }
    // 2: Colon (:)
    else if (id == 2) {
        let p_top = p - vec2<f32>(0.0, -0.15);
        let p_bot = p - vec2<f32>(0.0, 0.15);
        d = min(sdCircle(p_top, 0.05), sdCircle(p_bot, 0.05));
    }
    // 3: Minus (-)
    else if (id == 3) {
        d = sdBox(p, vec2<f32>(0.25, 0.05));
    }
    // 4: Plus (+)
    else if (id == 4) {
        d = sdCross(p, 0.25, 0.05);
    }
    // 5: Star (*)
    else if (id == 5) {
        let rot45 = mat2x2<f32>(0.707, -0.707, 0.707, 0.707);
        let p_rot = rot45 * p;
        d = min(sdCross(p, 0.2, 0.05), sdCross(p_rot, 0.2, 0.05));
    }
    // 6: Double Line (=)
    else if (id == 6) {
        let p_top = p - vec2<f32>(0.0, -0.1);
        let p_bot = p - vec2<f32>(0.0, 0.1);
        d = min(sdBox(p_top, vec2<f32>(0.25, 0.04)), sdBox(p_bot, vec2<f32>(0.25, 0.04)));
    }
    // 7: Hash (#)
    else if (id == 7) {
        // Vertical bars
        let v1 = sdBox(p - vec2<f32>(-0.1, 0.0), vec2<f32>(0.04, 0.3));
        let v2 = sdBox(p - vec2<f32>(0.1, 0.0), vec2<f32>(0.04, 0.3));
        // Horizontal bars
        let h1 = sdBox(p - vec2<f32>(0.0, -0.1), vec2<f32>(0.3, 0.04));
        let h2 = sdBox(p - vec2<f32>(0.0, 0.1), vec2<f32>(0.3, 0.04));
        d = min(min(v1, v2), min(h1, h2));
    }
    // 8: At (@) - Simplified as Circle + curve
    else {
        let circle = abs(sdCircle(p, 0.25)) - 0.04;
        let inner = sdCircle(p - vec2<f32>(0.0, 0.05), 0.08); // Inner 'a' part approximation
        d = min(circle, inner);
    }

    // Anti-aliased rendering
    let aa = 0.05; // Softness
    return 1.0 - smoothstep(0.0, aa, d);
}

// Binary digits (0 or 1) for decoder effect
fn get_binary_char(id: i32, uv: vec2<f32>) -> f32 {
    let p = uv - 0.5;
    var d = 1.0;

    if (id % 2 == 0) {
        // '0'
        d = abs(sdBox(p, vec2<f32>(0.15, 0.25))) - 0.05;
    } else {
        // '1'
        d = sdBox(p, vec2<f32>(0.05, 0.25));
    }

    return 1.0 - smoothstep(0.0, 0.05, d);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    let time = u.config.x;
    // Normalize UV
    let uv = vec2<f32>(gid.xy) / resolution;

    // --- Grid Setup ---
    // zoomParam1 controls grid density (10.0 - 200.0)
    let density = clamp(u.zoom_params.x, 10.0, 200.0);
    // Adjust density based on aspect ratio to keep cells roughly square or 1:2 ratio for characters?
    let aspect = resolution.x / resolution.y;
    // Using simple square cells for now, but scaled by density
    let grid_dims = vec2<f32>(density * aspect, density);

    let cell_uv = fract(uv * grid_dims);
    let cell_id = floor(uv * grid_dims);
    let cell_center_uv = (cell_id + 0.5) / grid_dims;

    // --- Sampling ---
    // Sample texture at cell center
    let color = textureSampleLevel(readTexture, u_sampler, cell_center_uv, 0.0).rgb;
    // Calculate luminance
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));

    // --- Mouse Interaction (Decoder) ---
    let mouse = u.zoom_config.yz; // Mouse UV

    // Calculate distance to mouse in UV space, correcting for aspect ratio for circular radius
    let to_mouse = (cell_center_uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist_mouse = length(to_mouse);
    let decoder_radius = 0.15;
    let is_decoder = step(dist_mouse, decoder_radius); // 1.0 inside, 0.0 outside

    // --- Glyph Selection ---
    var char_mask = 0.0;

    if (is_decoder > 0.5) {
        // Decoder Mode: Binary/Hex + Brightness Boost
        // Use cell position + time for random flickering binary
        let seed = dot(cell_id, vec2<f32>(12.9898, 78.233)) + time * 5.0;
        let rand = fract(sin(seed) * 43758.5453);
        let binary_id = i32(step(0.5, rand)); // 0 or 1

        char_mask = get_binary_char(binary_id, cell_uv);

        // Glitch offset occasionally
        if (rand > 0.95) {
            char_mask = 0.0; // Dropout
        }
    } else {
        // Standard ASCII Mode
        // Map luma 0.0-1.0 to glyphs 0-8
        let num_glyphs = 8;
        // Apply some gamma or contrast to luma before mapping for better distribution
        let luma_adjusted = pow(luma, 1.2);
        var glyph_idx = i32(luma_adjusted * f32(num_glyphs) + 0.5); // Round to nearest
        glyph_idx = clamp(glyph_idx, 0, num_glyphs);

        char_mask = get_character(glyph_idx, cell_uv);
    }

    // --- Coloring ---
    // zoomParam2 controls Color Mode (0.0 = Mono, 1.0 = Full Color)
    let color_mode = clamp(u.zoom_params.y, 0.0, 1.0);
    let glow_strength = clamp(u.zoom_params.z, 0.0, 2.0); // zoomParam3

    // Monochrome Palette (Phosphor Green)
    let phosphor_color = vec3<f32>(0.0, 1.0, 0.2);
    let mono_color = phosphor_color * luma * 2.0; // Brightness based on luma

    // Full Color Mode
    // Boost saturation slightly
    let final_rgb = mix(mono_color, color, color_mode);

    // Apply Glow
    var output_color = final_rgb * char_mask * glow_strength;

    // Decoder Highlight (White/Cyan hot)
    if (is_decoder > 0.5) {
        output_color = mix(output_color, vec3<f32>(0.8, 1.0, 1.0), 0.8) * char_mask * 2.0;
    }

    // --- Post Processing ---

    // Vignette
    let uv_center = uv - 0.5;
    let dist_center = length(uv_center);
    let vignette = smoothstep(0.8, 0.2, dist_center);
    output_color = output_color * vignette;

    // Scanlines
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.1 + 0.9; // Subtle
    output_color = output_color * scanline;

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(output_color, 1.0));
}
