// ----------------------------------------------------------------
// Procedural Cyber Terminal (ASCII)
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Grid Density, y=Glyph Sharpness, z=Character Brightness, w=Scanline Bloom
    ripples: array<vec4<f32>, 50>,
};

// Returns pseudo-random noise based on cell ID
fn hash21(p: vec2<f32>) -> f32 {
    let p3 = fract(p.xyx * 0.1031);
    let pd = p3 + vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((pd.x + pd.y) * pd.z);
}

// 2D Rotation Matrix
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// -----------------------------------------------------------------------------
// Procedural Glyph Generator (SDFs)
// ID determines which glyph to draw.
// uv is the 0-1 local coordinates of the cell.
// -----------------------------------------------------------------------------
fn get_character(id: i32, uv: vec2<f32>, sharpness: f32) -> f32 {
    // Empty
    if (id == 0) {
        return 0.0;
    }

    // . (Dot)
    if (id == 1) {
        let center = vec2<f32>(0.5, 0.2);
        let dist = length(uv - center);
        return 1.0 - smoothstep(0.1 - (1.0 - sharpness) * 0.1 - 0.01, 0.1, dist);
    }

    // : (Colon)
    if (id == 2) {
        let c1 = vec2<f32>(0.5, 0.3);
        let c2 = vec2<f32>(0.5, 0.7);
        let d1 = length(uv - c1);
        let d2 = length(uv - c2);
        let dist = min(d1, d2);
        return 1.0 - smoothstep(0.1 - (1.0 - sharpness) * 0.1 - 0.01, 0.1, dist);
    }

    // - (Minus)
    if (id == 3) {
        let center = uv - vec2<f32>(0.5, 0.5);
        let d = max(abs(center.x) - 0.25, abs(center.y) - 0.05);
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    // = (Equals)
    if (id == 4) {
        let center1 = uv - vec2<f32>(0.5, 0.4);
        let center2 = uv - vec2<f32>(0.5, 0.6);
        let d1 = max(abs(center1.x) - 0.25, abs(center1.y) - 0.05);
        let d2 = max(abs(center2.x) - 0.25, abs(center2.y) - 0.05);
        let d = min(d1, d2);
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    // + (Plus)
    if (id == 5) {
        let center = uv - vec2<f32>(0.5, 0.5);
        let d1 = max(abs(center.x) - 0.25, abs(center.y) - 0.05);
        let d2 = max(abs(center.x) - 0.05, abs(center.y) - 0.25);
        let d = min(d1, d2);
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    // * (Asterisk)
    if (id == 6) {
        let center = uv - vec2<f32>(0.5, 0.5);
        let d1 = max(abs(center.x) - 0.25, abs(center.y) - 0.03);
        let d2 = max(abs(center.x) - 0.03, abs(center.y) - 0.25);

        var rc = center * rot2D(3.14159 * 0.25);
        let d3 = max(abs(rc.x) - 0.25, abs(rc.y) - 0.03);
        let d4 = max(abs(rc.x) - 0.03, abs(rc.y) - 0.25);

        let d = min(min(d1, d2), min(d3, d4));
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    // # (Hash)
    if (id == 7) {
        let c = uv - vec2<f32>(0.5, 0.5);
        let d1 = max(abs(c.x + 0.1) - 0.04, abs(c.y) - 0.3);
        let d2 = max(abs(c.x - 0.1) - 0.04, abs(c.y) - 0.3);
        let d3 = max(abs(c.x) - 0.3, abs(c.y + 0.1) - 0.04);
        let d4 = max(abs(c.x) - 0.3, abs(c.y - 0.1) - 0.04);
        let d = min(min(d1, d2), min(d3, d4));
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    // @ (At - Simplified as an outer ring and inner dot)
    if (id == 8) {
        let c = uv - vec2<f32>(0.5, 0.5);
        let outer_dist = abs(length(c) - 0.3) - 0.05;
        let inner_dist = length(c + vec2<f32>(0.05, 0.0)) - 0.1;
        let d = min(outer_dist, inner_dist);
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    // Binary / Hex Mode (0/1 based on noise)
    if (id == 9) {
        // 0
        let c = uv - vec2<f32>(0.5, 0.5);
        let d = abs(length(vec2<f32>(c.x * 1.5, c.y)) - 0.25) - 0.05;
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    if (id == 10) {
        // 1
        let c = uv - vec2<f32>(0.5, 0.5);
        let d = max(abs(c.x + 0.05) - 0.05, abs(c.y) - 0.3);
        return 1.0 - smoothstep(0.02 - (1.0 - sharpness) * 0.05 - 0.01, 0.02, d);
    }

    return 0.0;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    let uv = fragCoord / dims;
    let aspect = dims.x / dims.y;

    // Parameters
    let grid_density = u.zoom_params.x;
    let sharpness = u.zoom_params.y;
    let brightness_mult = u.zoom_params.z;
    let scanline_bloom = u.zoom_params.w;

    // Mouse coords (0-1)
    let mX = u.zoom_config.y / dims.x;
    let mY = u.zoom_config.z / dims.y;
    let mouse_uv = vec2<f32>(mX, mY);

    // Audio-driven cursor jitter
    let bass = plasmaBuffer[0].x;
    let jittered_mouse = mouse_uv + vec2<f32>(
        bass * 0.03 * sin(u.config.x * 15.0),
        bass * 0.03 * cos(u.config.x * 12.0)
    );

    // Create a dynamic grid based on density (e.g. 80x25 to 160x50)
    let grid_cols = floor(80.0 * grid_density);
    let grid_rows = floor(grid_cols / (aspect * 0.5)); // Characters are taller than wide
    let grid_size = vec2<f32>(grid_cols, grid_rows);

    let cell_uv = fract(uv * grid_size);
    let cell_id = floor(uv * grid_size);
    let cell_center_uv = (cell_id + vec2<f32>(0.5)) / grid_size;

    // Sample underlying image at cell center
    let tex = textureSampleLevel(readTexture, u_sampler, cell_center_uv, 0.0);
    let tex_color = tex.rgb;
    let tex_alpha = tex.a;

    // Calculate luminance
    let luma = dot(tex_color, vec3<f32>(0.299, 0.587, 0.114));

    // Map luminance to character ID
    var char_id = 0;
    if (luma > 0.05) { char_id = 1; } // .
    if (luma > 0.15) { char_id = 2; } // :
    if (luma > 0.25) { char_id = 3; } // -
    if (luma > 0.40) { char_id = 4; } // =
    if (luma > 0.55) { char_id = 5; } // +
    if (luma > 0.70) { char_id = 6; } // *
    if (luma > 0.85) { char_id = 7; } // #
    if (luma > 0.95) { char_id = 8; } // @

    // Interactive Decoder Logic
    let dist_to_mouse = length((uv - jittered_mouse) * vec2<f32>(aspect, 1.0));
    var is_decoded = false;

    // Fixed decoder radius
    let decoder_radius = 0.25;
    let decoder_thresh = decoder_radius;
    if (decoder_thresh > 0.01 && dist_to_mouse < decoder_thresh) {
        // Falloff blending
        let falloff = 1.0 - smoothstep(decoder_thresh * 0.5, decoder_thresh, dist_to_mouse);

        // Switch to Binary (0 or 1) based on pseudo-random hash and luma
        if (falloff > 0.5) {
            // Audio reactivity: bass causes binary values to scramble rapidly
            let rnd = hash21(cell_id + vec2<f32>(u.config.x + bass * 8.0));
            if (luma > 0.1) {
                if (rnd > 0.5) {
                    char_id = 9; // 0
                } else {
                    char_id = 10; // 1
                }
            } else {
                char_id = 0;
            }
            is_decoded = true;
        }
    }

    // Generate the actual character mask
    let char_mask = get_character(char_id, cell_uv, sharpness);

    // Base color
    var col = tex_color * char_mask * brightness_mult;

    // Monochrome retro phosphor tint if not decoded
    if (!is_decoded) {
        let phosphor_green = vec3<f32>(0.1, 0.9, 0.2);
        // Mix image color with phosphor green based on some stylistic choice
        col = mix(col, phosphor_green * luma * char_mask * brightness_mult, 0.5);
    } else {
        // High contrast bright green for decoded binary
        col = vec3<f32>(0.2, 1.0, 0.5) * char_mask * 1.5;
    }

    // CRT Vignette
    let crt_uv = uv * (vec2<f32>(1.0) - uv.yx);
    let vignette = pow(crt_uv.x * crt_uv.y * 15.0, 0.2);
    col *= vignette;

    // Scanlines with bloom
    let scanline = 0.5 + 0.5 * sin(uv.y * dims.y * 3.14159);
    let scanlineMix = 0.15 + scanline_bloom * 0.2;
    col *= mix(1.0, scanline, scanlineMix);
    col += vec3<f32>(0.2, 1.0, 0.5) * max(scanline - 0.5, 0.0) * scanline_bloom * 0.5;

    // Glyph edge alpha anti-aliasing
    let finalAlpha = char_mask * vignette * tex_alpha;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, finalAlpha));
}
