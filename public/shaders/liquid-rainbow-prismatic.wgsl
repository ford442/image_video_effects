// Liquid Rainbow Prismatic — Cauchy dispersion, thin-film optics, and caustics.
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
fn surface(p:vec2<f32>,t:f32)->f32{return sin(p.x*13.0+t*1.3)+0.62*sin(p.y*17.0-t*1.7)+0.43*sin((p.x+p.y)*25.0+t*0.8);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3<u32>){
 let resolution=u.config.zw;if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }let coord=vec2<i32>(gid.xy);let size=vec2<i32>(resolution);let uv=(vec2<f32>(gid.xy)+0.5)/resolution;
 let texel=1.0/resolution;let aspect=resolution.x/max(resolution.y,1.0);let aspectVec=vec2<f32>(aspect,1.0);let time=u.config.x;let audio=clamp(plasmaBuffer[0].xyz,vec3<f32>(0.0),vec3<f32>(1.0));
 let curvature=mix(0.25,1.8,u.zoom_params.x);let dispersion=mix(0.004,0.055,u.zoom_params.y);let filmScale=mix(0.25,1.5,u.zoom_params.z);let saturation=mix(0.35,1.65,u.zoom_params.w);
 let p=(uv-0.5)*aspectVec;let hx=surface(p+vec2<f32>(texel.x*aspect,0.0),time)-surface(p-vec2<f32>(texel.x*aspect,0.0),time);
 let hy=surface(p+vec2<f32>(0.0,texel.y),time)-surface(p-vec2<f32>(0.0,texel.y),time);var gradient=vec2<f32>(hx/aspect,hy)*curvature*0.045;
 let pointer=(u.zoom_config.yz-0.5)*aspectVec;let pd=p-pointer;let pr=max(length(pd),0.0001);let hover=exp(-pr*5.5);let held=clamp(u.zoom_config.w,0.0,1.0);
 gradient+=vec2<f32>(pd.x/aspect,pd.y)/pr*hover*(0.006+held*0.035)*curvature;var frontEnergy=hover*(0.15+held*1.85);
 let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);for(var i=0u;i<rippleCount;i=i+1u){let e=u.ripples[i];let age=time-e.z;if (age < 0.0 || age > 3.0) { continue; }
  let d=(uv-e.xy)*aspectVec;let r=max(length(d),0.0001);let front=exp(-abs(r-age*(0.2+audio.x*0.09))*72.0)*exp(-age*0.9);gradient+=vec2<f32>(d.x/aspect,d.y)/r*front*(0.012+dispersion);frontEnergy+=front;}
 // Cauchy n(lambda)=A+B/lambda^2 approximated at RGB wavelengths.
 let nR=1.46+dispersion/0.650/0.650;let nG=1.46+dispersion/0.510/0.510;let nB=1.46+dispersion/0.440/0.440;
 let uvR=clamp(uv-gradient*(nR-1.0),vec2<f32>(0.0),vec2<f32>(1.0));let uvG=clamp(uv-gradient*(nG-1.0),vec2<f32>(0.0),vec2<f32>(1.0));let uvB=clamp(uv-gradient*(nB-1.0),vec2<f32>(0.0),vec2<f32>(1.0));
 let sr=textureSampleLevel(readTexture,u_sampler,uvR,0.0);let sg=textureSampleLevel(readTexture,u_sampler,uvG,0.0);let sb=textureSampleLevel(readTexture,u_sampler,uvB,0.0);
 let thickness=filmScale*(0.5+0.5*sin(surface(p*1.7,time*0.7)*2.1+time*(0.35+audio.y)))+frontEnergy*0.08;
 let phase=vec3<f32>(thickness*19.0/0.650,thickness*19.0/0.510,thickness*19.0/0.440);
 let film=0.5+0.5*cos(phase+vec3<f32>(0.0,2.094,4.188));
 var caustic=vec3<f32>(0.0);for(var k=0;k<6;k=k+1){let a=f32(k)*1.04719755+time*0.31;let o=vec2<f32>(cos(a),sin(a))*texel*(2.0+filmScale*4.0);caustic+=textureSampleLevel(readTexture,u_sampler,clamp(uvG+o,vec2<f32>(0.0),vec2<f32>(1.0)),0.0).rgb;}caustic/=6.0;
 let history=historyAt(uv-gradient,size);var hdr=vec3<f32>(sr.r,sg.g,sb.b);hdr+=film*saturation*(0.12+audio.z*0.32)+caustic*(0.08+frontEnergy*0.08);
 hdr=mix(hdr,history.rgb,clamp(history.a*(0.08+filmScale*0.09),0.0,0.24));hdr+=vec3<f32>(0.25,0.05,0.35)*audio.x*frontEnergy*0.18;let rgb=aces(hdr);
 let normal=normalize(vec3<f32>(-gradient*24.0,1.0));let fresnel=0.04+0.96*pow(1.0-max(normal.z,0.0),5.0);let sourceAlpha=max(sr.a,max(sg.a,sb.a));let alpha=clamp(sourceAlpha*0.76+thickness*0.12+fresnel*0.24+frontEnergy*0.05,0.0,1.0);
 let outputColor=vec4<f32>(rgb,alpha);textureStore(writeTexture,coord,outputColor);textureStore(dataTextureA,coord,outputColor);let depth=textureSampleLevel(readDepthTexture,non_filtering_sampler,uvG,0.0).r;
 textureStore(writeDepthTexture,coord,vec4<f32>(clamp(depth-length(gradient)*0.2,0.0,1.0),0.0,0.0,0.0));
}
