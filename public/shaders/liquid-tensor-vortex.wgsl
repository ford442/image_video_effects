// Liquid Tensor Vortex — source-luma structure-tensor advection and metallic folds.
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
struct Uniforms { config:vec4<f32>, zoom_config:vec4<f32>, zoom_params:vec4<f32>, ripples:array<vec4<f32>,50>, };
fn lumaAt(uv:vec2<f32>)->f32{let c=textureSampleLevel(readTexture,u_sampler,clamp(uv,vec2<f32>(0.0),vec2<f32>(1.0)),0.0).rgb;return dot(c,vec3<f32>(0.2126,0.7152,0.0722));}
fn historyAt(uv:vec2<f32>,size:vec2<i32>)->vec4<f32>{return textureLoad(dataTextureC,clamp(vec2<i32>(floor(uv*vec2<f32>(size))),vec2<i32>(0),size-vec2<i32>(1)),0);}
fn safeDir(v:vec2<f32>)->vec2<f32>{let q=dot(v,v);return select(vec2<f32>(0.0),v*inverseSqrt(q),q>1e-8);}
fn aces(x:vec3<f32>)->vec3<f32>{return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),vec3<f32>(0.0),vec3<f32>(1.0));}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3<u32>){
  let resolution=u.config.zw;if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }let coord=vec2<i32>(gid.xy);let size=vec2<i32>(resolution);
  let uv=(vec2<f32>(gid.xy)+0.5)/resolution;let texel=1.0/resolution;let aspect=resolution.x/max(resolution.y,1.0);let aspectVec=vec2<f32>(aspect,1.0);let time=u.config.x;
  let audio=clamp(plasmaBuffer[0].xyz,vec3<f32>(0.0),vec3<f32>(1.0));let flowScale=mix(0.25,2.4,u.zoom_params.x);let tension=mix(0.7,4.2,u.zoom_params.y);
  let specularGain=mix(0.2,3.2,u.zoom_params.z);let transmission=clamp(u.zoom_params.w,0.0,1.0);
  let gx=lumaAt(uv+vec2<f32>(texel.x,0.0))-lumaAt(uv-vec2<f32>(texel.x,0.0));let gy=lumaAt(uv+vec2<f32>(0.0,texel.y))-lumaAt(uv-vec2<f32>(0.0,texel.y));
  let jxx=gx*gx+0.00001;let jyy=gy*gy+0.00001;let jxy=gx*gy;let angle=0.5*atan2(2.0*jxy,jxx-jyy);let major=vec2<f32>(cos(angle),sin(angle));let tangent=vec2<f32>(-major.y,major.x);
  let discriminant=sqrt(max((jxx-jyy)*(jxx-jyy)+4.0*jxy*jxy,0.0));let coherence=clamp(discriminant/max(jxx+jyy,0.0001),0.0,1.0);let p=(uv-0.5)*aspectVec;
  var flowAspect=tangent*(0.004+coherence*0.018)*flowScale*(1.0+audio.y*0.8);
  let centers=array<vec2<f32>,3>(vec2<f32>(0.31*cos(time*0.43),0.24*sin(time*0.57)),vec2<f32>(-0.37*sin(time*0.31),0.29*cos(time*0.49)),vec2<f32>(0.22*sin(time*0.71),-0.34*cos(time*0.39)));
  for(var k=0;k<3;k=k+1){let d=p-centers[k];flowAspect+=vec2<f32>(-d.y,d.x)/(dot(d,d)+0.025)*(0.0008+audio.x*0.0015)*flowScale;}
  let pointerDelta=p-(u.zoom_config.yz-0.5)*aspectVec;let pointerDist=max(length(pointerDelta),0.0001);let hover=exp(-pointerDist*6.5);let held=clamp(u.zoom_config.w,0.0,1.0);
  flowAspect+=vec2<f32>(-pointerDelta.y,pointerDelta.x)/pointerDist*hover*(0.002+held*0.022)*flowScale;var foldImpulse=hover*(0.2+held*1.8);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);for(var i=0u;i<rippleCount;i=i+1u){let event=u.ripples[i];let age=time-event.z;if (age < 0.0 || age > 3.2) { continue; }
    let d=(uv-event.xy)*aspectVec;let r=max(length(d),0.0001);let front=exp(-abs(r-age*(0.19+audio.x*0.07))*65.0)*exp(-age*0.85);flowAspect+=vec2<f32>(-d.y,d.x)/r*front*0.012*flowScale;foldImpulse+=front;}
  let flow=vec2<f32>(flowAspect.x/aspect,flowAspect.y);let history=historyAt(uv-flow,size);let source=textureSampleLevel(readTexture,u_sampler,clamp(uv+flow*0.5,vec2<f32>(0.0),vec2<f32>(1.0)),0.0);
  let foldPhase=dot(p,safeDir(flowAspect+tangent*0.01))*(28.0+tension*10.0)+time*(1.2+audio.x*2.0);let folds=pow(abs(sin(foldPhase+coherence*4.0)),tension)*(0.35+coherence*0.65);
  let normal=normalize(vec3<f32>(-gx*6.0-flowAspect.x*28.0,-gy*6.0-flowAspect.y*28.0,1.0));let light=normalize(vec3<f32>(-0.35+sin(time*0.3)*0.3,0.45,0.82));let halfVector=normalize(light+vec3<f32>(0.0,0.0,1.0));
  let spec=pow(max(dot(normal,halfVector),0.0),mix(12.0,72.0,coherence))*specularGain;let metal=mix(vec3<f32>(0.03,0.04,0.06),vec3<f32>(0.72,0.77,0.84),folds);
  let warmFold=vec3<f32>(1.1,0.46,0.08)*foldImpulse*0.16+vec3<f32>(0.18,0.45,1.0)*audio.z*coherence*0.28;var hdr=mix(source.rgb,metal,0.42+folds*0.45)+warmFold+spec*vec3<f32>(1.0,0.83,0.58);
  hdr=mix(hdr,history.rgb,clamp(history.a*(0.08+coherence*0.2),0.0,0.3));let rgb=aces(hdr);let fresnel=pow(1.0-max(normal.z,0.0),5.0);
  let alpha=clamp(source.a*(1.0-transmission*0.45)+folds*0.35+fresnel*0.3+length(flowAspect)*2.0,0.0,1.0);let outputColor=vec4<f32>(rgb,alpha);
  textureStore(writeTexture,coord,outputColor);textureStore(dataTextureA,coord,outputColor);let depth=textureSampleLevel(readDepthTexture,non_filtering_sampler,uv,0.0).r;
  textureStore(writeDepthTexture,coord,vec4<f32>(clamp(depth-folds*0.035,0.0,1.0),0.0,0.0,0.0));
}
