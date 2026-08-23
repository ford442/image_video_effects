// Liquid Zoom — layered depth zoom through a moving refractive surface.
@group(0) @binding(0) var u_sampler:sampler; @group(0) @binding(1) var readTexture:texture_2d<f32>;
@group(0) @binding(2) var writeTexture:texture_storage_2d<rgba32float,write>; @group(0) @binding(3) var<uniform> u:Uniforms;
@group(0) @binding(4) var readDepthTexture:texture_2d<f32>; @group(0) @binding(5) var non_filtering_sampler:sampler;
@group(0) @binding(6) var writeDepthTexture:texture_storage_2d<r32float,write>; @group(0) @binding(7) var dataTextureA:texture_storage_2d<rgba32float,write>;
@group(0) @binding(8) var dataTextureB:texture_storage_2d<rgba32float,write>; @group(0) @binding(9) var dataTextureC:texture_2d<f32>;
@group(0) @binding(10) var<storage,read_write> extraBuffer:array<f32>; @group(0) @binding(11) var comparison_sampler:sampler_comparison;
@group(0) @binding(12) var<storage,read> plasmaBuffer:array<vec4<f32>>;
struct Uniforms{config:vec4<f32>,zoom_config:vec4<f32>,zoom_params:vec4<f32>,ripples:array<vec4<f32>,50>,};
fn historyAt(uv:vec2<f32>,size:vec2<i32>)->vec4<f32>{return textureLoad(dataTextureC,clamp(vec2<i32>(floor(uv*vec2<f32>(size))),vec2<i32>(0),size-vec2<i32>(1)),0);}
fn aces(x:vec3<f32>)->vec3<f32>{return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),vec3<f32>(0.0),vec3<f32>(1.0));}
fn safeDir(v:vec2<f32>)->vec2<f32>{let q=dot(v,v);return select(vec2<f32>(0.0),v*inverseSqrt(q),q>1e-8);}
fn mirrorUV(v:vec2<f32>)->vec2<f32>{let f=fract(v*0.5)*2.0;return 1.0-abs(f-1.0);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3<u32>){
 let resolution=u.config.zw;if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }let coord=vec2<i32>(gid.xy);let size=vec2<i32>(resolution);
 let uv=(vec2<f32>(gid.xy)+0.5)/resolution;let aspect=resolution.x/max(resolution.y,1.0);let aspectVec=vec2<f32>(aspect,1.0);let time=u.config.x;
 let audio=clamp(plasmaBuffer[0].xyz,vec3<f32>(0.0),vec3<f32>(1.0));let intensity=mix(0.35,2.8,u.zoom_params.x);let speed=mix(0.08,1.35,u.zoom_params.y);
 let scaleControl=mix(0.5,2.4,u.zoom_params.z);let detail=mix(1.0,7.0,u.zoom_params.w);let center=u.zoom_config.yz;let p=(uv-center)*aspectVec;
 var liquid=vec2<f32>(sin(p.y*(8.0+detail)+time*(1.1+audio.y)),cos(p.x*(7.0+detail*1.3)-time*(0.9+audio.z)))*0.008*scaleControl;
 let pointerDelta=(uv-u.zoom_config.yz)*aspectVec;let pointerDist=max(length(pointerDelta),0.0001);let hover=exp(-pointerDist*6.0);let held=clamp(u.zoom_config.w,0.0,1.0);
 liquid+=vec2<f32>(pointerDelta.x/aspect,pointerDelta.y)/pointerDist*hover*(0.003+held*0.03)*intensity;var lensEnergy=hover*(0.15+held*1.85);
 let vortexCenters=array<vec2<f32>,2>(vec2<f32>(0.28*cos(time*0.51),0.22*sin(time*0.67)),vec2<f32>(-0.34*sin(time*0.39),0.27*cos(time*0.43)));
 for(var k=0;k<2;k=k+1){let d=p-vortexCenters[k];liquid+=vec2<f32>(-d.y/aspect,d.x)/(dot(d,d)+0.035)*(0.0007+audio.x*0.0012)*scaleControl;}
 let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);for(var i=0u;i<rippleCount;i=i+1u){let e=u.ripples[i];let age=time-e.z;if (age < 0.0 || age > 3.1) { continue; }
  let d=(uv-e.xy)*aspectVec;let r=max(length(d),0.0001);let front=exp(-abs(r-age*(0.2+audio.x*0.08))*68.0)*exp(-age*0.85);liquid+=vec2<f32>(d.x/aspect,d.y)/r*front*0.019*intensity;lensEnergy+=front;}
 let depth=textureSampleLevel(readDepthTexture,non_filtering_sampler,uv,0.0).r;var hdr=vec3<f32>(0.0);var coverage=0.0;var weightSum=0.0;var activeDepth=depth;
 for(var layer=0;layer<3;layer=layer+1){let lf=f32(layer);let phase=fract(time*speed*(0.55+lf*0.22)+lf*0.333+depth*0.2);let nearFactor=pow(1.0-clamp(depth,0.0,1.0),0.7+lf*0.35);
  let zoom=1.0+phase*intensity*nearFactor*(1.0+audio.x*0.35);let shear=vec2<f32>(sin(time*0.5+lf*2.1),cos(time*0.43-lf))*liquid*(1.0+lf*0.45);
  let layerUV=mirrorUV((uv-center)/zoom+center+shear);let sampleColor=textureSampleLevel(readTexture,u_sampler,layerUV,0.0);let fade=smoothstep(0.0,0.16,phase)*(1.0-smoothstep(0.76,1.0,phase));let weight=mix(1.0,fade,nearFactor);
  hdr+=sampleColor.rgb*weight;coverage=max(coverage,sampleColor.a*weight);weightSum+=weight;activeDepth=min(activeDepth,textureSampleLevel(readDepthTexture,non_filtering_sampler,layerUV,0.0).r);}
 hdr/=max(weightSum,0.0001);let history=historyAt(clamp(uv-liquid,vec2<f32>(0.0),vec2<f32>(1.0)),size);let trailMix=clamp(0.08+scaleControl*0.05+lensEnergy*0.035,0.0,0.28)*history.a;
 hdr=mix(hdr,history.rgb,trailMix);let ridge=clamp(length(liquid)*28.0+lensEnergy*0.22,0.0,2.0);hdr+=vec3<f32>(0.08,0.38+audio.y*0.25,0.7+audio.z*0.5)*ridge*0.18;
 let rgb=aces(hdr);let alpha=clamp(coverage+ridge*0.14+history.a*trailMix*0.18,0.0,1.0);let outputColor=vec4<f32>(rgb,alpha);
 textureStore(writeTexture,coord,outputColor);textureStore(dataTextureA,coord,outputColor);textureStore(writeDepthTexture,coord,vec4<f32>(clamp(activeDepth-ridge*0.025,0.0,1.0),0.0,0.0,0.0));
}
