// ---------------------------------------------------------------
//  Prismatic Mosaic – tile-based color replacement with shifting prisms
//  Strong colors break into tiles that rotate hue and reassemble.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;

struct Uniforms {
  config:      vec4<f32>, // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>, // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>, // x=unused, y=unused, z=unused, w=unused
  ripples:     array<vec4<f32>, 50>,
  mosaic_params: vec4<f32>, // x=tileSize, y=speed, z=satBoost, w=unused
};

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    let src = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    var tileSize = u.mosaic_params.x; // fraction of screen (0.01-0.2)
    let speed = u.mosaic_params.y;
    let satBoost = u.mosaic_params.z;
    let time = u.config.x;

    // Mouse position for mosaic center or scale
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let dist_to_mouse = distance(uv, mouse_pos);
    if (dist_to_mouse < 0.3) {
      tileSize *= 1.0 + (1.0 - dist_to_mouse / 0.3) * 0.5;
    }
    
    // Ripples trigger rearrangements
    var jitter = vec2<f32>(0.0);
    for (var i = 0; i < 50; i++) {
      let ripple = u.ripples[i];
      if (ripple.z > 0.0) {
        let ripple_age = time - ripple.z;
        if (ripple_age > 0.0 && ripple_age < 2.0) {
          let dist_to_ripple = distance(uv, ripple.xy);
          if (dist_to_ripple < 0.2) {
            jitter += vec2<f32>(sin(ripple_age * 10.0), cos(ripple_age * 10.0)) * 0.01 * (1.0 - ripple_age / 2.0);
          }
        }
      }
    }

    // Snap UV to nearest tile centre
    let tileUV = floor((uv + jitter) / tileSize) * tileSize + tileSize * 0.5;
    let tileCol = textureSampleLevel(videoTex, videoSampler, tileUV, 0.0).rgb;

    // Determine if tile contains strong colour (saturation > threshold)
    let hsv = rgb2hsv(tileCol);
    if (hsv.y < 0.3) { // low saturation -> keep original
        textureStore(outTex, gid.xy, vec4<f32>(src, 1.0));
        return;
    }

    // Apply hue shift based on time and speed
    let newHue = fract(hsv.x + speed * time * 0.05);
    let boostedSat = min(hsv.y + satBoost, 1.0);
    let outCol = hsv2rgb(newHue, boostedSat, hsv.z);
    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));
}
