// Liquid Lens — Batch 59 premium caustic optics.
// A/C packing: display RGBA history. B and extraBuffer are intentionally unused.
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
fn boundedLoad(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> { let c=clamp(vec2<i32>(floor(uv*vec2<f32>(dims))),vec2<i32>(0),dims-vec2<i32>(1)); return textureLoad(dataTextureC,c,0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x*(2.51*x+0.03))/max(x*(2.43*x+0.59)+0.14,vec3<f32>(0.001)),vec3<f32>(0.0),vec3<f32>(1.0)); }
fn lensLobe(p:vec2<f32>,c:vec2<f32>,r:f32,lobes:f32,phase:f32)->vec2<f32>{let q=p-c;let d=max(length(q),0.0001);let b=r*(1.0+0.13*sin(atan2(q.y,q.x)*lobes+phase));let h=smoothstep(b,b*0.35,d);return q/d*h*(b-d)/max(b,0.001);}
@compute @workgroup_size(16,16,1)
fn main(@builtin(global_invocation_id) gid:vec3<u32>){
 let res=u.config.zw;if(gid.x>=u32(res.x)||gid.y>=u32(res.y)){return;}let coord=vec2<i32>(gid.xy);let uv=(vec2<f32>(gid.xy)+0.5)/res;let dims=vec2<i32>(res);let aspect=res.x/max(res.y,1.0);let t=u.config.x;let audio=clamp(plasmaBuffer[0].xyz,vec3<f32>(0.0),vec3<f32>(1.0));
 let refraction=0.012+u.zoom_params.x*0.065;let radius=0.10+u.zoom_params.y*0.34;let dispersion=0.001+u.zoom_params.z*0.018;let waves=0.15+u.zoom_params.w*1.35;let pointer=u.zoom_config.yz;let held=clamp(u.zoom_config.w,0.0,1.0);let p=(uv-0.5)*vec2<f32>(aspect,1.0);let mp=(pointer-0.5)*vec2<f32>(aspect,1.0);
 let orbitA=mp+vec2<f32>(cos(t*2.3),sin(t*2.7))*(0.10+audio.x*0.035);let orbitB=mp+vec2<f32>(cos(-t*3.1+2.0),sin(t*2.1+2.0))*0.17;var bend=lensLobe(p,mp,radius*(1.0-held*0.18),5.0,t*2.8)*(1.0+held*2.1);bend+=lensLobe(p,orbitA,radius*0.36,3.0,-t*4.0)*0.62;bend+=lensLobe(p,orbitB,radius*0.25,4.0,t*5.0)*0.42;
 let mesh=sin((p.x+p.y)*42.0-t*7.5)*sin((p.x-p.y)*35.0+t*6.0);bend+=vec2<f32>(sin(p.y*29.0+t*5.4),cos(p.x*31.0-t*4.7))*mesh*waves*0.0008;var ring=0.0;let count=min(u32(max(u.config.y,0.0)),50u);
 for(var i=0u;i<count;i=i+1u){let r=u.ripples[i];let age=t-r.z;if(age>=0.0&&age<3.0){let q=(uv-r.xy)*vec2<f32>(aspect,1.0);let d=max(length(q),0.0001);let front=sin((d-age*0.30)*70.0)*exp(-abs(d-age*0.30)*20.0-age*0.8);bend+=vec2<f32>(q.x/aspect,q.y)/d*front*refraction;ring+=abs(front);}}
 let flow=vec2<f32>(bend.x/aspect,bend.y)*refraction*(1.0+audio.y*0.55);let dir=flow/max(length(flow),0.0001);let baseUV=clamp(uv-flow,vec2<f32>(0.0),vec2<f32>(1.0));let spread=dir*dispersion*(1.0+audio.z*0.7);let sr=textureSampleLevel(readTexture,u_sampler,clamp(baseUV+spread,vec2<f32>(0.0),vec2<f32>(1.0)),0.0);let sg=textureSampleLevel(readTexture,u_sampler,baseUV,0.0);let sb=textureSampleLevel(readTexture,u_sampler,clamp(baseUV-spread,vec2<f32>(0.0),vec2<f32>(1.0)),0.0);let history=boundedLoad(clamp(uv-flow*0.35,vec2<f32>(0.0),vec2<f32>(1.0)),dims);
 let caustic=pow(clamp(abs(mesh)*length(bend)*9.0+ring*0.35,0.0,1.0),2.0);let normal=normalize(vec3<f32>(-bend*5.0,1.0));let fresnel=0.04+0.96*pow(1.0-max(normal.z,0.0),5.0);var rgb=vec3<f32>(sr.r,sg.g,sb.b);rgb+=mix(vec3<f32>(0.05,0.82,0.94),vec3<f32>(1.0,0.48,0.08),0.5+0.5*sin(t*1.9+p.x*8.0))*caustic*(0.28+audio.y*0.4);rgb+=vec3<f32>(0.32,0.7,0.9)*fresnel*0.3;rgb=mix(rgb,history.rgb,clamp(history.a*0.12,0.0,0.16));let alpha=clamp(max(max(sr.a,sg.a),sb.a)*0.86+fresnel*0.12+caustic*0.16,0.0,1.0);let outColor=vec4<f32>(aces(rgb),alpha);textureStore(writeTexture,coord,outColor);textureStore(dataTextureA,coord,outColor);let depth=textureSampleLevel(readDepthTexture,non_filtering_sampler,baseUV,0.0).r;textureStore(writeDepthTexture,coord,vec4<f32>(clamp(depth-caustic*0.02,0.0,1.0),0.0,0.0,0.0));
}
