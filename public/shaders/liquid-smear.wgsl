// Liquid Smear — anisotropic viscous paint advection with display-RGBA feedback.
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
struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };
fn safeDir(v: vec2<f32>) -> vec2<f32> { let m2=dot(v,v); return select(vec2<f32>(0.0),v*inverseSqrt(m2),m2>1e-8); }
fn historyAt(uv: vec2<f32>, size: vec2<i32>) -> vec4<f32> { let p=clamp(vec2<i32>(floor(uv*vec2<f32>(size))),vec2<i32>(0),size-vec2<i32>(1)); return textureLoad(dataTextureC,p,0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),vec3<f32>(0.0),vec3<f32>(1.0)); }
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution=u.config.zw; if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord=vec2<i32>(gid.xy); let size=vec2<i32>(resolution); let uv=(vec2<f32>(gid.xy)+0.5)/resolution; let texel=1.0/resolution;
  let aspect=resolution.x/max(resolution.y,1.0); let aspectVec=vec2<f32>(aspect,1.0); let time=u.config.x;
  let audio=clamp(plasmaBuffer[0].xyz,vec3<f32>(0.0),vec3<f32>(1.0));
  let strength=mix(0.006,0.075,u.zoom_params.x); let brush=mix(0.035,0.32,u.zoom_params.y)*(1.0+audio.x*0.45);
  let persistence=mix(0.72,0.992,u.zoom_params.z); let wetMix=mix(0.08,0.92,u.zoom_params.w);
  let pointerDelta=(uv-u.zoom_config.yz)*aspectVec; let pointerDist=max(length(pointerDelta),0.0001); let pointerDir=pointerDelta/pointerDist;
  let hover=1.0-smoothstep(brush*0.55,brush*1.6,pointerDist); let held=clamp(u.zoom_config.w,0.0,1.0); let pointerWeight=hover*(0.18+held*1.82);
  var flowAspect=pointerDir*pointerWeight*strength*(0.6+audio.x*1.2);
  flowAspect+=vec2<f32>(-pointerDir.y,pointerDir.x)*pointerWeight*strength*(0.25+audio.y*1.45)*sin(time*2.1+pointerDist*23.0);
  flowAspect+=vec2<f32>(sin(uv.y*17.0+time*0.9),cos(uv.x*13.0-time*0.7))*strength*0.09;
  var eddyEnergy=pointerWeight; let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for(var i=0u;i<rippleCount;i=i+1u){let event=u.ripples[i];let age=time-event.z;if (age < 0.0 || age > 3.4) { continue; }
    let delta=(uv-event.xy)*aspectVec;let radius=max(length(delta),0.0001);let radial=delta/radius;
    let front=exp(-abs(radius-age*(0.16+audio.x*0.08))*62.0)*exp(-age*0.9);let swirl=vec2<f32>(-radial.y,radial.x)*sin(radius*31.0-age*7.0);
    flowAspect+=(radial*0.35+swirl)*front*strength*(0.8+audio.y);eddyEnergy+=front;}
  let flow=vec2<f32>(flowAspect.x/aspect,flowAspect.y);let tangent=safeDir(flow+vec2<f32>(texel.x,0.0));let normal=vec2<f32>(-tangent.y,tangent.x);let departure=uv-flow;
  var advected=historyAt(departure,size)*0.34;advected+=historyAt(departure+tangent*texel*2.0,size)*0.20;advected+=historyAt(departure-tangent*texel*2.0,size)*0.20;
  advected+=historyAt(departure+normal*texel,size)*0.13;advected+=historyAt(departure-normal*texel,size)*0.13;
  let source=textureSampleLevel(readTexture,u_sampler,clamp(uv-flow*0.35,vec2<f32>(0.0),vec2<f32>(1.0)),0.0);let initialized=select(source,advected,advected.a>0.0001);
  var hdr=mix(source.rgb,initialized.rgb,persistence*wetMix);let ridge=clamp(length(advected.rgb-source.rgb)*1.7+length(flowAspect)*14.0,0.0,2.0);
  hdr+=vec3<f32>(1.0,0.38+audio.y*0.3,0.08+audio.z*0.5)*ridge*(0.08+audio.z*0.24);hdr+=vec3<f32>(0.05,0.16,0.22)*eddyEnergy*audio.x*0.12;
  let rgb=aces(hdr);let sourceCoverage=max(source.a,initialized.a*persistence);let alpha=clamp(sourceCoverage+ridge*0.16+length(flowAspect)*1.8+eddyEnergy*0.025,0.0,1.0);
  let outputColor=vec4<f32>(rgb,alpha);textureStore(writeTexture,coord,outputColor);textureStore(dataTextureA,coord,outputColor);
  let depth=textureSampleLevel(readDepthTexture,non_filtering_sampler,uv,0.0).r;textureStore(writeDepthTexture,coord,vec4<f32>(clamp(depth-ridge*0.025,0.0,1.0),0.0,0.0,0.0));
}
