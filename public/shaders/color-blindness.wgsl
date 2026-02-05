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
  zoom_params: vec4<f32>,  // x=Type, y=Severity, z=SplitMode, w=Unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let cb_type_param = u.zoom_params.x; // 0-0.33 Protan, 0.33-0.66 Deutan, 0.66-1 Tritan
    let severity = u.zoom_params.y;
    let split_mode = u.zoom_params.z > 0.5; // If true, use mouse X as split line

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let color = original.rgb;

    // Select matrix based on type
    var m = mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0
    );

    if (cb_type_param < 0.33) {
        // Protanopia (Red blind)
        m = mat3x3<f32>(
            0.567, 0.558, 0.0,
            0.433, 0.442, 0.242,
            0.0, 0.0, 0.758
        );
    } else if (cb_type_param < 0.66) {
        // Deuteranopia (Green blind)
        m = mat3x3<f32>(
            0.625, 0.7, 0.0,
            0.375, 0.3, 0.3,
            0.0, 0.0, 0.7
        );
    } else {
        // Tritanopia (Blue blind)
        m = mat3x3<f32>(
            0.95, 0.0, 0.0,
            0.05, 0.433, 0.475,
            0.0, 0.567, 0.525
        );
    }

    // Note: GLSL/WGSL matrices are column-major constructed.
    // The matrix multiply `m * v` treats v as a column vector.
    // The above values are transposed if copying from row-major text.
    // Standard def:
    // | R' |   | .567 .433 0 | | R |
    // | G' | = | .558 .442 0 | | G |
    // | B' |   | 0 .242 .758 | | B |
    //
    // In WGSL `mat3x3(c0, c1, c2)` where cN are columns.
    // So Col 0 = (.567, .558, 0).
    // The code above:
    // Col 0 = (.567, .433, 0.0) -> Wait, I swapped them in my head or code?
    // Let's check Protan definition carefully.
    // R_new = .567*R + .433*G + 0*B
    // G_new = .558*R + .442*G + 0*B
    // B_new = 0*R + .242*G + .758*B
    //
    // Matrix multiplication `m * color` does:
    // x = dot(row0, color)
    // y = dot(row1, color)
    // z = dot(row2, color)
    //
    // WGSL `m * v` means `v` is column vector. `m` columns multiply components of `v`.
    // result = v.x * col0 + v.y * col1 + v.z * col2.
    // So if I want result.x = .567*R + .433*G + 0*B
    // Then Row 0 of the matrix (conceptually) should be (.567, .433, 0).
    //
    // In WGSL `mat3x3<f32>(c0, c1, c2)`
    // c0 = (m00, m10, m20)
    // c1 = (m01, m11, m21)
    // c2 = (m02, m12, m22)
    //
    // So result.x = m00*R + m01*G + m02*B
    // result.y = m10*R + m11*G + m12*B
    // result.z = m20*R + m21*G + m22*B
    //
    // My previous code:
    // m = mat3x3(
    //    0.567, 0.558, 0.0,   <- Col 0 (m00, m10, m20)
    //    0.433, 0.442, 0.242, <- Col 1 (m01, m11, m21)
    //    0.0, 0.0, 0.758      <- Col 2 (m02, m12, m22)
    // )
    // result.x = .567*R + .433*G + 0*B -> Correct.
    // result.y = .558*R + .442*G + 0*B -> Correct.
    // result.z = 0*R + .242*G + .758*B -> Correct.
    //
    // So my code construction was actually correct for the values I wrote down!

    var simulated = m * color;

    // Mix based on severity
    simulated = mix(color, simulated, severity);

    // Split screen logic
    var final_color = simulated;
    if (split_mode) {
        // Mouse X controls split
        if (uv.x < u.zoom_config.y) {
            final_color = color;
        }
    } else {
        // Just use severity
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, original.a));
}
