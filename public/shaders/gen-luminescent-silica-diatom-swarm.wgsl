// ----------------------------------------------------------------
// Luminescent Silica Diatom Swarm
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Swarm Density, .y = Bioluminescence, .z = Glass Refraction, .w = Audio Reactivity
  ripples: array<vec4<f32>, 50>,
};

// Rotates a 2D vector
fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

// 3D hash
fn hash33(p: vec3<f32>) -> vec3<f32> {
  let p2 = vec3<f32>(
    dot(p, vec3<f32>(127.1, 311.7, 74.7)),
    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
    dot(p, vec3<f32>(113.5, 271.9, 124.6))
  );
  return fract(sin(p2) * 43758.5453123);
}

// 3D Voronoi-like noise for diatom structure
fn voronoi3D(x: vec3<f32>) -> f32 {
  let p = floor(x);
  let f = fract(x);
  var res = 100.0;
  for (var k = -1; k <= 1; k++) {
    for (var j = -1; j <= 1; j++) {
      for (var i = -1; i <= 1; i++) {
        let b = vec3<f32>(f32(i), f32(j), f32(k));
        let r = vec3<f32>(b) - f + hash33(p + b);
        let d = dot(r, r);
        if (d < res) {
          res = d;
        }
      }
    }
  }
  return sqrt(res);
}

// SDF for a microscopic silica shell
fn map(p: vec3<f32>, audioReact: f32) -> vec2<f32> { // returns (distance, material_id)
  let time = u.config.x;

  // Domain folding for the swarm
  // Scale space based on Swarm Density slider
  let scale = 2.0 / max(0.1, u.zoom_params.x);

  var q = p;

  // Audio reactivity affecting the domain warp
  q.x += sin(q.y * 1.5 + time) * 0.2 * audioReact;
  q.z += cos(q.y * 1.2 - time * 0.8) * 0.2 * audioReact;

  let cellIndex = floor(q / scale);
  q = (fract(q / scale) - 0.5) * scale;

  // Add some rotation variation per cell
  let h = hash33(cellIndex);
  let rM1 = rot(time * 0.5 + h.x * 6.28);
  let rM2 = rot(time * 0.3 + h.y * 6.28);

  let t_q = vec3<f32>(q.x, q.y, q.z);
  var t2_q = t_q;

  let xz = rM1 * vec2<f32>(t2_q.x, t2_q.z);
  t2_q.x = xz.x;
  t2_q.z = xz.y;

  let xy = rM2 * vec2<f32>(t2_q.x, t2_q.y);
  t2_q.x = xy.x;
  t2_q.y = xy.y;

  q = t2_q;

  // Diatom shell shape: porous sphere/capsule mix
  let baseSphere = length(q) - (0.4 * scale);

  // subtract Voronoi noise for porous silica look
  let noiseFreq = 8.0 / scale;
  let vNoise = voronoi3D(q * noiseFreq);

  // the thickness of the shell
  let shell = abs(baseSphere) - 0.02 * scale;

  // punch holes using the voronoi noise
  let holes = 0.25 * scale - vNoise * 0.4 * scale;

  let d = max(shell, -holes);

  // inner glowing core
  let core = length(q) - (0.15 * scale);

  // material: 1.0 = silica shell, 2.0 = glowing core
  if (core < d) {
    return vec2<f32>(core, 2.0);
  }
  return vec2<f32>(d, 1.0);
}

// Normal calculation
fn calcNormal(p: vec3<f32>, audioReact: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let nx = map(p + vec3<f32>(e.x, e.y, e.y), audioReact).x - map(p - vec3<f32>(e.x, e.y, e.y), audioReact).x;
  let ny = map(p + vec3<f32>(e.y, e.x, e.y), audioReact).x - map(p - vec3<f32>(e.y, e.x, e.y), audioReact).x;
  let nz = map(p + vec3<f32>(e.y, e.y, e.x), audioReact).x - map(p - vec3<f32>(e.y, e.y, e.x), audioReact).x;
  return normalize(vec3<f32>(nx, ny, nz));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let texSize = textureDimensions(writeTexture);
  if (global_id.x >= texSize.x || global_id.y >= texSize.y) { return; }

  let fragCoord = vec2<f32>(global_id.xy);
  let res = vec2<f32>(texSize);

  var uv = (fragCoord - 0.5 * res) / min(res.x, res.y);

  let time = u.config.x;

  // Audio reactivity sampling
  // Sample frequency data from dataTextureC
  let audioUV = vec2<f32>(abs(uv.x) * 0.5 + 0.25, 0.5);
  let audioSample = textureSampleLevel(dataTextureC, non_filtering_sampler, audioUV, 0.0).r;
  let audioIntensity = audioSample * u.zoom_params.w;

  // Camera setup
  var ro = vec3<f32>(0.0, 0.0, time * 2.0); // Moving forward
  var ta = ro + vec3<f32>(0.0, 0.0, 1.0);

  // Mouse Interaction (localized thermal/gravity well warping)
  // map mouse to -1..1
  var mouseUV = (u.zoom_config.yz - 0.5) * 2.0;
  mouseUV.y = -mouseUV.y; // invert Y

  // Distort rays based on mouse proximity
  let mouseDist = length(uv - mouseUV);
  let mouseWarp = exp(-mouseDist * 4.0) * u.zoom_config.w; // only warp if mouse down? or just always based on proximity.

  // apply some warp to the view ray
  var uv_warped = uv;
  if(u.zoom_config.w > 0.5) {
     let dirToMouse = normalize(uv - mouseUV);
     uv_warped -= dirToMouse * mouseWarp * 0.2;
  }

  // Camera basis vectors
  let cw = normalize(ta - ro);
  let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
  let cv = normalize(cross(cu, cw));

  // Ray direction
  var rd = normalize(uv_warped.x * cu + uv_warped.y * cv + 1.2 * cw);

  // Raymarching
  var t = 0.0;
  var mat = 0.0;
  let maxD = 30.0;

  var hit = false;
  var minDistanceToCore = 100.0;

  for (var i = 0; i < 100; i++) {
    let p = ro + rd * t;
    let resMap = map(p, audioIntensity);

    // Accumulate subsurface scatter/glow effect based on distance to core
    if (resMap.y == 2.0) {
       minDistanceToCore = min(minDistanceToCore, resMap.x);
    }

    if (resMap.x < 0.001) {
      hit = true;
      mat = resMap.y;
      break;
    }
    if (t > maxD) {
      break;
    }
    t += resMap.x * 0.7; // step slightly slower for fine details
  }

  // Background color - deep oceanic gradient
  var col = mix(vec3<f32>(0.01, 0.03, 0.08), vec3<f32>(0.0, 0.01, 0.02), clamp(uv.y + 0.5, 0.0, 1.0));

  if (hit) {
    let p = ro + rd * t;
    let n = calcNormal(p, audioIntensity);

    // Mouse proximity color shift
    // approximate 3D pos of mouse on a plane
    let mouseWorldPos = ro + normalize(mouseUV.x * cu + mouseUV.y * cv + 1.2 * cw) * t;
    let distToMouseWorld = length(p - mouseWorldPos);
    let mouseColorInfluence = exp(-distToMouseWorld * 0.5) * u.zoom_config.w;

    if (mat == 1.0) {
      // Silica Shell (Glassy Refraction/Reflection)
      let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
      let diff = max(dot(n, lightDir), 0.0);
      let viewDir = -rd;
      let refl = reflect(-lightDir, n);
      let spec = pow(max(dot(viewDir, refl), 0.0), 32.0);

      // Fresnel effect
      let f0 = 0.04;
      let fresnel = f0 + (1.0 - f0) * pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);

      // Glass refraction parameter
      let refrFactor = u.zoom_params.z - 1.0;

      let shellColor = vec3<f32>(0.2, 0.5, 0.6) * diff + vec3<f32>(1.0) * spec * fresnel;
      col = shellColor + fresnel * 0.5 * refrFactor;

    } else if (mat == 2.0) {
      // Glowing Core
      var baseGlow = vec3<f32>(0.1, 0.8, 0.9); // Cyan
      let warmGlow = vec3<f32>(1.0, 0.7, 0.2); // Warm Gold

      // Shift hue near mouse
      baseGlow = mix(baseGlow, warmGlow, mouseColorInfluence);

      // Audio reactive intensity and hue
      baseGlow += vec3<f32>(audioIntensity * 0.5, audioIntensity * 0.2, 0.0);

      col = baseGlow * u.zoom_params.y * 2.0;
    }
  }

  // Subsurface Bioluminescent Glow (volumetric integration approx)
  if (minDistanceToCore < 1.0 && !hit) {
      var glowCol = vec3<f32>(0.0, 0.6, 0.8);
      let warmGlow = vec3<f32>(1.0, 0.6, 0.1);

      // Approximate mouse influence on the ray path
      let rayMouseDist = length(cross(rd, mouseUV.x * cu + mouseUV.y * cv + 1.2 * cw));
      let rayMouseInf = exp(-rayMouseDist * 2.0) * u.zoom_config.w;
      glowCol = mix(glowCol, warmGlow, rayMouseInf);

      let glowStr = exp(-minDistanceToCore * 4.0) * u.zoom_params.y;
      col += glowCol * glowStr * (1.0 + audioIntensity);
  }

  // Fog / Depth of field approximation (fade to background)
  let fogFactor = 1.0 - exp(-t * 0.05);
  let bgColor = vec3<f32>(0.01, 0.02, 0.05);
  col = mix(col, bgColor, clamp(fogFactor, 0.0, 1.0));

  // Tone mapping and gamma correction
  col = col / (1.0 + col);
  col = pow(col, vec3<f32>(1.0 / 2.2));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}