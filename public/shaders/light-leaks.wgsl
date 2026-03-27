struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
}

@group(0) @binding(0) 
var u_sampler: sampler;
@group(0) @binding(1) 
var readTexture: texture_2d<f32>;
@group(0) @binding(2) 
var writeTexture: texture_storage_2d<rgba32float,write>;
@group(0) @binding(3) 
var<uniform> u: Uniforms;
@group(0) @binding(4) 
var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) 
var non_filtering_sampler: sampler;
@group(0) @binding(6) 
var writeDepthTexture: texture_storage_2d<r32float,write>;
@group(0) @binding(7) 
var dataTextureA: texture_storage_2d<rgba32float,write>;
@group(0) @binding(8) 
var dataTextureB: texture_storage_2d<rgba32float,write>;
@group(0) @binding(9) 
var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) 
var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) 
var comparison_sampler: sampler_comparison;
@group(0) @binding(12) 
var<storage> plasmaBuffer: array<vec4<f32>>;

fn getLuma(color_1: vec3<f32>) -> f32 {
    return dot(color_1, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12_(p: vec2<f32>) -> f32 {
    var p3_: vec3<f32>;

    p3_ = fract((vec3<f32>(p.xyx) * 0.1031));
    let _e7 = p3_;
    let _e8 = p3_;
    let _e14 = p3_;
    p3_ = (_e14 + vec3(dot(_e7, (_e8.yzx + vec3(33.33)))));
    let _e18 = p3_.x;
    let _e20 = p3_.y;
    let _e23 = p3_.z;
    return fract(((_e18 + _e20) * _e23));
}

@compute @workgroup_size(8, 8, 1) 
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    var uv: vec2<f32>;
    var mousePos: vec2<f32>;
    var gx: vec3<f32> = vec3(0.0);
    var gy: vec3<f32> = vec3(0.0);
    var i: i32 = -1;
    var j: i32;
    var wx: f32;
    var wy: f32;
    var color: vec3<f32>;
    var finalColor: vec3<f32>;
    var ink_alpha: f32 = 0.0;
    var d: f32;

    let _e3 = u.config;
    let resolution = _e3.zw;
    if ((global_id.x >= u32(resolution.x)) || (global_id.y >= u32(resolution.y))) {
        return;
    }
    uv = (vec2<f32>(global_id.xy) / resolution);
    let _e20 = u.zoom_config;
    mousePos = _e20.yz;
    let time = u.config.x;
    let _e30 = u.zoom_params.x;
    let dotSize = ((_e30 * 20.0) + 2.0);
    let _e40 = u.zoom_params.y;
    let edgeThresh = max(0.01, ((1.0 - _e40) * 0.5));
    let _e48 = u.zoom_params.z;
    let levels = (floor((_e48 * 10.0)) + 2.0);
    let inkDensity = u.zoom_params.w;
    let pixelSize = (vec2(1.0) / resolution);
    loop {
        let _e69 = i;
        if (_e69 <= 1) {
        } else {
            break;
        }
        {
            j = -1;
            loop {
                let _e74 = j;
                if (_e74 <= 1) {
                } else {
                    break;
                }
                {
                    let _e77 = i;
                    let _e79 = j;
                    let offset = (vec2<f32>(f32(_e77), f32(_e79)) * pixelSize);
                    let _e85 = uv;
                    let _e88 = textureSampleLevel(readTexture, u_sampler, (_e85 + offset), 0.0);
                    let s = _e88.xyz;
                    let _e90 = getLuma(s);
                    wx = 0.0;
                    wy = 0.0;
                    let _e95 = i;
                    if (_e95 == -1) {
                        wx = -1.0;
                    }
                    let _e99 = i;
                    if (_e99 == 1) {
                        wx = 1.0;
                    }
                    let _e103 = j;
                    if (_e103 == -1) {
                        wy = -1.0;
                    }
                    let _e107 = j;
                    if (_e107 == 1) {
                        wy = 1.0;
                    }
                    let _e111 = j;
                    if (_e111 == 0) {
                        let _e115 = wx;
                        wx = (_e115 * 2.0);
                    }
                    let _e117 = i;
                    if (_e117 == 0) {
                        let _e121 = wy;
                        wy = (_e121 * 2.0);
                    }
                    let _e123 = wx;
                    let _e126 = gx;
                    gx = (_e126 + vec3((_e90 * _e123)));
                    let _e128 = wy;
                    let _e131 = gy;
                    gy = (_e131 + vec3((_e90 * _e128)));
                }
                continuing {
                    let _e134 = j;
                    j = (_e134 + 1);
                }
            }
        }
        continuing {
            let _e137 = i;
            i = (_e137 + 1);
        }
    }
    let _e139 = gx;
    let _e140 = gy;
    let edge = length((_e139 + _e140));
    let isEdge = select(0.0, 1.0, (edge > edgeThresh));
    let _e149 = uv;
    let _e151 = textureSampleLevel(readTexture, u_sampler, _e149, 0.0);
    color = _e151.xyz;
    let _e154 = color;
    let _e155 = getLuma(_e154);
    let gridPos = (vec2<f32>(global_id.xy) / vec2(dotSize));
    let gridCenter = (floor(gridPos) + vec2(0.5));
    let dist = length((gridPos - gridCenter));
    let radius = (sqrt(_e155) * 0.5);
    let _e169 = color;
    color = (floor((_e169 * levels)) / vec3(levels));
    let dotRadius = ((1.0 - _e155) * 0.7);
    let isDot = select(0.0, 1.0, (dist < dotRadius));
    let _e182 = color;
    finalColor = _e182;
    if (isEdge > 0.5) {
        let line_density = ((inkDensity * 0.9) + 0.05);
        ink_alpha = line_density;
        let _e192 = finalColor;
        finalColor = mix(_e192, vec3<f32>(0.02, 0.02, 0.04), (isEdge * inkDensity));
    }
    if (isDot > 0.5) {
        let dot_coverage = smoothstep(0.0, 0.7, (1.0 - _e155));
        let dot_alpha = ((dot_coverage * inkDensity) * 0.85);
        let inkColor = vec3<f32>(0.08, 0.07, 0.09);
        let _e213 = finalColor;
        let _e214 = finalColor;
        finalColor = mix(_e213, (_e214 * 0.7), (isDot * 0.8));
        let _e220 = ink_alpha;
        ink_alpha = max(_e220, dot_alpha);
    }
    let _e222 = ink_alpha;
    if (_e222 < 0.01) {
        ink_alpha = mix(0.15, 0.45, (_e155 * inkDensity));
    }
    let _e229 = uv;
    let _e236 = hash12_((((_e229 * time) * 0.001) + vec2(100.0)));
    let paper_tex = (0.95 + (0.05 * _e236));
    let _e241 = ink_alpha;
    ink_alpha = (_e241 * paper_tex);
    let _e244 = mousePos.x;
    if (_e244 >= 0.0) {
        let _e247 = uv;
        let _e248 = mousePos;
        let dVec = (_e247 - _e248);
        d = length(dVec);
        let _e254 = d;
        let vignette = smoothstep(0.8, 0.2, (_e254 * 0.5));
        let _e258 = finalColor;
        finalColor = (_e258 * vignette);
        let _e260 = ink_alpha;
        let _e262 = ink_alpha;
        ink_alpha = mix(_e260, min(1.0, (_e262 * 1.2)), (vignette * 0.5));
    }
    let _e272 = finalColor;
    let _e273 = ink_alpha;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(_e272, _e273));
    let _e277 = ink_alpha;
    let _e280 = ink_alpha;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(_e277, 0.0, 0.0, _e280));
    return;
}
