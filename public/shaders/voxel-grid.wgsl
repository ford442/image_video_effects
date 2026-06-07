// ═══════════════════════════════════════════════════════════════════
//  Voxel Grid
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
    return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                     1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                     0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
    let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
    let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
    let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
    return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                    -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                    -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    let r = select(clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0), 1.0, t <= 66.0);
    let g = select(clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0),
                   clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0), t <= 66.0);
    let b = select(select(clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0), 0.0, t <= 19.0), 1.0, t >= 66.0);
    return vec3<f32>(r, g, b);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coords) / vec2<f32>(dimensions);
    let aspect = u.config.z / u.config.w;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let grid_density = u.zoom_params.x;
    let touch_radius = u.zoom_params.y;
    let rotation_strength = u.zoom_params.z;
    let cell_gap = u.zoom_params.w;

    let grid_uv = floor(uv * grid_density) / grid_density;
    let cell_center = grid_uv + (0.5 / grid_density);
    let mouse = u.zoom_config.yz;
    let dist_vec = (cell_center - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);
    let influence = smoothstep(touch_radius, 0.0, dist);
    let angle = influence * rotation_strength * 3.14159;
    let c = cos(angle);
    let s = sin(angle);
    let local_uv = fract(uv * grid_density);
    let centered = local_uv - 0.5;
    let rotated = vec2<f32>(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
    let cell_color = textureSampleLevel(readTexture, u_sampler, clamp(cell_center, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let scale = 0.5 - (cell_gap * 0.5);
    let pop = influence * 0.2 + bass * 0.15;
    let current_scale = scale + pop;
    let box_dist = max(abs(rotated.x), abs(rotated.y)) - current_scale;

    let inside = select(0.0, 1.0, box_dist < 0.0);

    let key_temp = mix(3500.0, 6500.0, bass + influence * 0.5);
    let key_col = blackbodyRGB(key_temp);
    let fill_col = blackbodyRGB(8500.0);
    let nx = rotated.x / max(current_scale, 0.001);
    let ny = rotated.y / max(current_scale, 0.001);
    let nz = sqrt(max(0.0, 1.0 - nx*nx - ny*ny));
    let normal = vec3<f32>(nx, ny, nz);
    let key_lit = max(dot(normal, normalize(vec3<f32>(-0.5, 0.7, 0.5))), 0.0);
    let fill_lit = max(dot(normal, normalize(vec3<f32>(0.6, 0.2, 0.4))), 0.0) * 0.35;
    let fresnel = pow(1.0 - max(dot(normal, vec3<f32>(0.0, 0.0, 1.0)), 0.0), 3.0);
    let edge_dist = -box_dist / max(cell_gap + 0.02, 0.001);
    let irid = sin(fresnel * 12.0 + time * 2.0 + bass * 4.0 + mids * 2.0) * 0.5 + 0.5;
    let irid_col = vec3<f32>(0.4, 0.7, 1.0) * irid * fresnel * edge_dist;
    let lit = cell_color * (key_col * key_lit + fill_col * fill_lit);
    let shaded = mixOkLab(lit, irid_col, fresnel * edge_dist * 0.5);
    let hdr = shaded * (1.4 + influence * 0.6 + bass * 0.5 + treble * 0.2);
    let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(luma + influence * 0.3 + bass * 0.2, 0.2, 1.0);
    let mapped = aces(hdr);
    let dither = (ign(vec2<f32>(coords)) - 0.5) / 255.0;
    let inside_color = vec4<f32>((mapped + vec3<f32>(dither)) * alpha, alpha);

    let final_color = mix(vec4<f32>(0.0, 0.0, 0.0, 0.0), inside_color, inside);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coords, final_color);
    textureStore(dataTextureA, coords, final_color);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
