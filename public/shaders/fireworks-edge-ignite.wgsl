// Fireworks Edge Ignite — image contours launch pyrotechnics
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
  config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn hash1(n: f32) -> f32 { return fract(sin(n*127.1)*43758.5453); }
fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv-c); return (exp(-d*d/(r*r*0.5))+0.3*exp(-d/(r*3.0)))*i;
}
fn sampleImg(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv*0.5+0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}
fn edgeAt(uv: vec2<f32>, res: vec2<f32>) -> f32 {
  let e = 2.0/min(res.x,res.y);
  let l0 = dot(sampleImg(uv), vec3<f32>(0.299,0.587,0.114));
  let lx = dot(sampleImg(uv+vec2<f32>(e,0.0)), vec3<f32>(0.299,0.587,0.114));
  let ly = dot(sampleImg(uv+vec2<f32>(0.0,e)), vec3<f32>(0.299,0.587,0.114));
  return length(vec2<f32>(lx-l0, ly-l0));
}
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v*age - vec2<f32>(0.0, g)*age*age*0.5;
}
// zoom_config.yz and ripples[].xy are NORMALIZED [0,1] coords — multiplying
// by res turns them into pixels before recentering into the shader's
// centered-UV space. Treating them as pixels puts bursts far off-screen.
fn normToCentered(p: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  return (p * res - res * 0.5) / min(res.x, res.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  // Slider wiring (saved-preset contract — roles fixed):
  //   x = Edge Sensitivity -> edge detection threshold
  //   y = Launch Power     -> shell velocity / burst energy
  //   z = Trail Glow       -> temporal feedback persistence
  //   w = Color Boost      -> contour glow + spark brightness
  let edgeSens = mix(0.1, 0.8, u.zoom_params.x);
  let power = mix(0.35, 1.6, u.zoom_params.y);
  let trail = mix(0.88, 0.96, u.zoom_params.z);
  let boost = mix(0.5, 1.5, u.zoom_params.w);
  let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let imgCol = sampleImg(uv);
  let edge = edgeAt(uv, res);
  var col = imgCol * (0.45 + edge * boost * 0.3);

  // Edge glow along contours
  if (edge > edgeSens * 0.3) {
    col += imgCol * boost * smoothstep(edgeSens*0.3, edgeSens, edge) * 0.5;
  }

  // Bass deepens the ambient contour glow so kicks widen the ignition lines.
  col += imgCol * smoothstep(edgeSens*0.5, edgeSens*1.2, edge) * bass * 0.35;

  for (var s = 0; s < 8; s = s + 1) {
    let si = f32(s); let seed = hash1(si*43.0+1.0);
    let probe = vec2<f32>((seed-0.5)*1.5, (hash1(si*67.0)-0.5)*1.2);
    let probeEdge = edgeAt(probe, res);
    if (probeEdge < edgeSens * 0.4) { continue; }
    let cycle = 2.5;
    let birth = floor((time*0.6+seed*1.5)/cycle)*cycle-seed*1.5;
    let age = time-birth; if (age < 0.0 || age > 5.0) { continue; }
    let pCol = sampleImg(probe);
    let energy = power * probeEdge * boost * (0.6+bass*0.6);
    let bAge = max(0.0, age-0.6);
    if (bAge > 0.0) {
      let n = i32(12.0 + energy*20.0);
      for (var j = 0; j < n; j = j + 1) {
        let ang = f32(j)/f32(n)*TAU + seed;
        let vel = vec2<f32>(cos(ang), sin(ang)) * (0.25+hash1(f32(j)*2.1)*0.35)*energy;
        let sp = sparkPos(probe, vel, bAge, 0.8);
        col += pCol * boost * softGlow(uv, sp, 0.006, smoothstep(4.0,0.2,bAge)*energy);
      }
      col += pCol * exp(-bAge*8.0) * energy * softGlow(uv, probe, 0.04, 1.0);
    }
  }

  // --- Click shells: every individual click launches a one-shot firework ---
  // ripples[].xy = normalized click position, .z = click time.
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let rAge = time - rp.z;
    if (rAge < 0.0 || rAge > 4.2) { continue; }
    let rUV = normToCentered(rp.xy, res);
    let rEdge = edgeAt(rUV, res);
    let rCol = sampleImg(rUV);
    let rEnergy = power * (0.7 + rEdge) * boost * (0.6 + bass*0.6);
    let apex = rUV + vec2<f32>(0.0, 0.22);
    // Ascent phase (age 0 .. 0.6): bright comet climbs from the click point.
    if (rAge < 0.6) {
      let at = rAge / 0.6;
      let head = rUV + vec2<f32>(0.0, 0.22) * at;
      col += rCol * boost * softGlow(uv, head, 0.009, (1.0-at)*1.8*rEnergy);
      // Warm trailing streak behind the rising shell.
      for (var tt = 1; tt < 5; tt = tt + 1) {
        let tf = at - f32(tt)*0.05;
        if (tf > 0.0) {
          let tp = rUV + vec2<f32>(0.0, 0.22) * tf;
          col += vec3<f32>(1.0,0.85,0.55) * softGlow(uv, tp, 0.004, (1.0-at)*0.6);
        }
      }
    }
    // Burst phase (age >= 0.6): one-shot radial shell detonates at the apex.
    let rb = max(0.0, rAge - 0.6);
    if (rb > 0.0) {
      let rn = i32(16.0 + rEnergy*18.0);
      let rFade = smoothstep(3.6, 0.15, rb);
      for (var q = 0; q < rn; q = q + 1) {
        let jq = hash1(f32(ri)*57.0 + f32(q)*2.9);
        let ang = f32(q)/f32(rn)*TAU + jq*0.5;
        let vel = vec2<f32>(cos(ang), sin(ang)) * (0.3+jq*0.35) * rEnergy;
        let sp = sparkPos(apex, vel, rb, 0.85);
        col += rCol * boost * softGlow(uv, sp, 0.006, rFade*rEnergy);
      }
      col += rCol * exp(-rb*9.0) * rEnergy * softGlow(uv, apex, 0.045, 1.2);
    }
  }

  if (u.zoom_config.w > 0.5) {
    // FIXED: zoom_config.yz is normalized [0,1] — convert to pixels first so
    // the held-click burst centers on the cursor instead of off-screen.
    let mUV = (u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y);
    let mEdge = edgeAt(mUV, res);
    if (mEdge > edgeSens*0.2) {
      let mAge = fract(time*1.2)*2.5;
      let mCol = sampleImg(mUV);
      // Ignition flash hugging the cursor contour.
      col += mCol * boost * exp(-mAge*3.0) * softGlow(uv, mUV, 0.03, power);
      for (var k = 0; k < 20; k = k + 1) {
        let ang = f32(k)/20.0*TAU;
        let sp = sparkPos(mUV, vec2<f32>(cos(ang),sin(ang))*0.4*power, mAge, 0.7);
        col += mCol*boost*softGlow(uv, sp, 0.005, smoothstep(2.0,0.1,mAge)*power);
      }
    }
  }

  // Treble crackle: white-hot micro-sparks walk along the strong contours.
  let crackle = step(0.992-treble*0.02, hash1(dot(uv, vec2<f32>(211.0,97.0))+time*17.0));
  col += vec3<f32>(1.0,0.95,0.85) * crackle * smoothstep(edgeSens*0.4, edgeSens, edge) * treble * 0.5;

  col = mix(prev*trail, col, 0.32);
  col += vec3<f32>(0.65,0.8,1.0)*step(0.986-treble*0.03, hash1(dot(uv,vec2<f32>(73.0,157.0))+time*12.0))*treble*0.6;
  col = acesToneMap(col*1.05);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.5+prev*0.4, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.15, 0.12, 0.96)));
  // Honest depth: luminance of the tonemapped color pushes sparks and bright
  // contours forward instead of clobbering chain depth with a flat 0.0.
  let depthOut = clamp(dot(col, vec3<f32>(0.299,0.587,0.114)) * 0.9 + edge * 0.2, 0.0, 1.0);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut));
}
