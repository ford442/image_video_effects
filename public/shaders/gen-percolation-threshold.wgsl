// ═══════════════════════════════════════════════════════════════════
//  Percolation Threshold
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: conduction pulses flowing left-to-right along the spanning cluster backbone (dangling ends dim); critical opalescence haze that blooms as p approaches p_c
//  A packing: lattice state in texels [0..79]x[0..59] = (cluster label, epoch stamp, touchesLeft, touchesRight); ACES display RGBA in all other texels
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Threshold Shift, .y = Lattice Zoom, .z = Bloom, .w = Grain
  ripples: array<vec4<f32>, 50>,
};

const LATTICE_W: i32 = 80;
const LATTICE_H: i32 = 60;
const P_C: f32 = 0.5927;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clampSite(s: vec2<i32>) -> vec2<i32> {
  return clamp(s, vec2<i32>(0), vec2<i32>(LATTICE_W - 1, LATTICE_H - 1));
}

// Screen uv -> continuous lattice-site coordinates (same mapping as the display).
fn uvToSite(uv: vec2<f32>, latticeZoom: f32) -> vec2<f32> {
  let zoomedUV = (uv - 0.5) * latticeZoom + 0.5;
  return zoomedUV * vec2<f32>(f32(LATTICE_W), f32(LATTICE_H));
}

// Stateless site occupancy: Bernoulli(p) per epoch, plus local doping from the
// held mouse probe and click ripples (forced-occupied disks, in site units).
fn siteOccupied(site: vec2<i32>, epoch: f32, p: f32, latticeZoom: f32) -> bool {
  let flatIdx = f32(site.y * LATTICE_W + site.x);
  if (hash12(vec2<f32>(flatIdx, epoch)) < p) { return true; }
  let sc = vec2<f32>(site) + 0.5;
  if (u.zoom_config.w > 0.5) {
    if (length(sc - uvToSite(u.zoom_config.yz, latticeZoom)) < 2.5) { return true; }
  }
  let time = u.config.x;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let rp = u.ripples[r];
    let age = time - rp.z;
    if (age < 0.0 || age > 3.0) { continue; }
    let radius = 1.5 + age * 4.0;
    let d = length(sc - uvToSite(rp.xy, latticeZoom));
    if (d < radius && d > radius - 2.0 * (1.0 - age / 3.0)) { return true; }
  }
  return false;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let coord = vec2<i32>(gid.xy);
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let pCritical = P_C + (bass - 0.5) * 0.1 + (u.zoom_params.x - 0.5) * 0.15;
  let p = clamp(pCritical, 0.35, 0.85);
  let latticeZoom = mix(0.6, 1.4, u.zoom_params.y);
  let bloomAmt = mix(0.8, 2.0, u.zoom_params.z);
  let grainAmt = mix(0.0, 0.15, u.zoom_params.w);

  // Lattice realisation epoch (reseeded every 5 s); stamp 0 = never written.
  let epoch = floor(time * 0.2);
  let epochStamp = epoch + 1.0;

  // ═══ Lattice simulation: iterative min-label flood fill + boundary flags ═══
  // Stored in the top-left LATTICE_W x LATTICE_H texels of dataTextureA, read
  // back exactly from dataTextureC next frame. Spanning = a cluster touching
  // both the left and right lattice edges (flags propagate through the cluster).
  let inLattice = gid.x < u32(LATTICE_W) && gid.y < u32(LATTICE_H);
  var simState = vec4<f32>(-1.0, epochStamp, 0.0, 0.0);
  if (inLattice) {
    let site = coord;
    if (siteOccupied(site, epoch, p, latticeZoom)) {
      var label = f32(site.y * LATTICE_W + site.x);
      var touchL = select(0.0, 1.0, site.x == 0);
      var touchR = select(0.0, 1.0, site.x == LATTICE_W - 1);
      let self_prev = textureLoad(dataTextureC, site, 0);
      if (self_prev.g == epochStamp && self_prev.r >= 0.0) {
        label = min(label, self_prev.r);
        touchL = max(touchL, self_prev.b);
        touchR = max(touchR, self_prev.a);
      }
      let offsets = array<vec2<i32>, 4>(vec2<i32>(0, -1), vec2<i32>(0, 1), vec2<i32>(1, 0), vec2<i32>(-1, 0));
      for (var k = 0; k < 4; k = k + 1) {
        let nb = site + offsets[k];
        if (nb.x < 0 || nb.y < 0 || nb.x >= LATTICE_W || nb.y >= LATTICE_H) { continue; }
        if (!siteOccupied(nb, epoch, p, latticeZoom)) { continue; }
        let ns = textureLoad(dataTextureC, nb, 0);
        if (ns.g == epochStamp && ns.r >= 0.0) {
          label = min(label, ns.r);
          touchL = max(touchL, ns.b);
          touchR = max(touchR, ns.a);
        }
      }
      simState = vec4<f32>(label, epochStamp, touchL, touchR);
    }
  }

  // ═══ Display ═══
  let siteF = uvToSite(uv, latticeZoom);
  let siteX = clamp(i32(floor(siteF.x)), 0, LATTICE_W - 1);
  let siteY = clamp(i32(floor(siteF.y)), 0, LATTICE_H - 1);
  let siteCoord = vec2<i32>(siteX, siteY);
  let occupied = siteOccupied(siteCoord, epoch, p, latticeZoom);

  // Idea 2: critical opalescence — fluctuations on all scales scatter light as p -> p_c.
  let criticality = exp(-abs(p - P_C) * 40.0);
  let flick = floor(time * 8.0);
  let fluct = hash12(vec2<f32>(siteCoord) + flick * 17.0) * 0.25
            + hash12(floor(vec2<f32>(siteCoord) / 4.0) + flick * 3.1) * 0.35
            + hash12(floor(vec2<f32>(siteCoord) / 16.0) + epoch * 7.7) * 0.4;
  let opalescence = vec3<f32>(0.55, 0.62, 0.85) * criticality * fluct * (0.6 + mids * 0.4);

  var displayColor = vec3<f32>(0.0);
  var alpha = 0.0;
  var outDepth = 0.0;

  if (!occupied) {
    let bg = vec3<f32>(0.02, 0.02, 0.04) * (1.0 + depth * 0.3) + opalescence * 0.12;
    displayColor = acesToneMap(bg);
    alpha = clamp(0.2 + depth * 0.2 + criticality * fluct * 0.1, 0.0, 1.0);
    outDepth = depth * 0.1;
  } else {
    let state = textureLoad(dataTextureC, siteCoord, 0);
    let valid = state.g == epochStamp && state.r >= 0.0;
    let label = select(f32(siteY * LATTICE_W + siteX), state.r, valid);
    let isSpanning = valid && state.b > 0.5 && state.a > 0.5;

    let hue = fract(hash12(vec2<f32>(label, floor(label * 0.01))) + 0.15);
    let jewel = clamp(abs(vec3<f32>(abs(hue * 6.0 - 3.0) - 1.0, 2.0 - abs(hue * 6.0 - 2.0), 2.0 - abs(hue * 6.0 - 4.0))), vec3<f32>(0.0), vec3<f32>(1.0));
    let sat = mix(jewel, vec3<f32>(1.0), 0.3);

    let nOcc = siteOccupied(clampSite(siteCoord + vec2<i32>(0, -1)), epoch, p, latticeZoom);
    let sOcc = siteOccupied(clampSite(siteCoord + vec2<i32>(0, 1)), epoch, p, latticeZoom);
    let eOcc = siteOccupied(clampSite(siteCoord + vec2<i32>(1, 0)), epoch, p, latticeZoom);
    let wOcc = siteOccupied(clampSite(siteCoord + vec2<i32>(-1, 0)), epoch, p, latticeZoom);
    let edgeCount = select(0, 1, !nOcc) + select(0, 1, !sOcc) + select(0, 1, !eOcc) + select(0, 1, !wOcc);

    var color = sat * 0.6;
    if (isSpanning) {
      color = sat * bloomAmt + vec3<f32>(0.3, 0.2, 0.5) * bloomAmt * 0.5;
      // Idea 1: conduction pulses — current flows left->right along the backbone;
      // dangling ends (many empty neighbours) carry little current.
      let backbone = 1.0 - f32(edgeCount) * 0.25;
      let flow = fract(f32(siteX) / f32(LATTICE_W) * 3.0 - time * (0.35 + bass * 0.4));
      let pulse = smoothstep(0.0, 0.06, flow) * (1.0 - smoothstep(0.06, 0.3, flow));
      color = color + (sat + vec3<f32>(0.4)) * pulse * backbone * backbone * bloomAmt * (0.6 + treble * 0.4);
    } else {
      // Finite clusters turn milky near criticality (idea 2).
      color = mix(color, color + opalescence, 0.35);
    }
    color = color + vec3<f32>(0.5, 0.3, 0.8) * f32(edgeCount) * 0.12;
    let ca = smoothstep(0.0, 1.0, f32(edgeCount)) * 0.08 * (1.0 + bass * 0.5);
    color = vec3<f32>(color.r + ca, color.g, color.b - ca);
    color = color + hash12(uv * 500.0 + time) * grainAmt;

    displayColor = acesToneMap(color * 1.1);
    let clusterProxy = 1.0 - f32(edgeCount) * 0.22;
    alpha = clamp(clusterProxy * select(1.0, 2.2, isSpanning) * (0.4 + depth * 0.6), 0.0, 1.0);
    outDepth = depth * 0.5 + select(0.0, 0.35, isSpanning);
  }

  let finalColor = vec4<f32>(displayColor, alpha);
  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  if (inLattice) {
    textureStore(dataTextureA, coord, simState);
  } else {
    textureStore(dataTextureA, coord, finalColor);
  }
}
