@group(0) @binding(0) var u_sampler:sampler;
@group(0) @binding(1) var readTexture:texture_2d<f32>;
@group(0) @binding(2) var writeTexture:texture_storage_2d<rgba32float,write>;
@group(0) @binding(3) var<uniform> u:Uniforms;
@group(0) @binding(4) var readDepthTexture:texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler:sampler;
@group(0) @binding(6) var writeDepthTexture:texture_storage_2d<r32float,write>;
@group(0) @binding(7) var dataTextureA:texture_storage_2d<rgba32float,write>;
@group(0) @binding(8) var dataTextureB:texture_storage_2d<rgba32float,write>;
@group(0) @binding(9) var dataTextureC:texture_2d<f32>;
@group(0) @binding(10) var<storage,read_write> extraBuffer:array<f32>;
@group(0) @binding(11) var comparison_sampler:sampler_comparison;
@group(0) @binding(12) var<storage,read> plasmaBuffer:array<vec4<f32>>;
struct Uniforms{config:vec4<f32>,zoom_config:vec4<f32>,zoom_params:vec4<f32>,ripples:array<vec4<f32>,50>,};
fn aces(x:vec3f)->vec3f{let a=2.51;let b=0.03;let c=2.43;let d=0.59;let e=0.14;return clamp((x*(a*x+vec3f(b)))/(x*(c*x+vec3f(d))+vec3f(e)),vec3f(0.0),vec3f(1.0));}
fn stateAt(p:vec2i,d:vec2i)->vec4f{return textureLoad(dataTextureC,clamp(p,vec2i(0),d-vec2i(1)),0);}
fn hash21(p:vec2f)->f32{return fract(sin(dot(p,vec2f(91.7,271.9)))*43758.5453);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);
 let dt=clamp((1.0 / 60.0),0.0,0.033);let densityGain=0.25+1.8*u.zoom_params.x;let scatter=0.3+2.7*u.zoom_params.y;
 let light=max(u.zoom_params.z,0.0);let bloom=u.zoom_params.w;let audio=plasmaBuffer[0].xyz;let c=stateAt(p,d);
 let adv=stateAt(p-vec2i(round(c.zw*vec2f(du)*dt)),d);let n=stateAt(p+vec2i(0,1),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);let avg=(n+s+e+w)*0.25;
 var rho=mix(adv.x,avg.x,0.06);var energy=mix(adv.y,avg.y,0.08);var vel=mix(adv.zw,avg.zw,0.05);
 vel+=vec2f(n.x-s.x,w.x-e.x)*0.22+(vec2f(hash21(vec2f(p)+u.config.x),hash21(vec2f(p.yx)-u.config.x))-0.5)*0.012;
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);
 let brush=step(0.5,u.zoom_config.w)*exp(-dot(q,q)*190.0);rho+=brush*(0.018+audio.x*0.06)*densityGain;energy+=brush*(0.025+audio.z*0.08)*light;vel+=brush*normalize(q+vec2f(0.0001))*0.05;
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<2.3){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let ring=exp(-pow((length(cq)-age*0.15)*48.0,2.0))*exp(-age*1.2);rho+=ring*(0.015+audio.y*0.04);energy+=ring*(0.02+audio.z*0.06);vel+=normalize(cq+vec2f(0.0001))*ring*0.035;}}
 rho=clamp(rho*exp(-dt*0.24),0.0,2.0);energy=clamp(energy*exp(-dt*0.52),0.0,3.0);vel=clamp(vel*exp(-dt*1.25),vec2f(-1.0),vec2f(1.0));textureStore(dataTextureA,p,vec4f(rho,energy,vel));
 let scene=textureSampleLevel(readTexture,u_sampler,clamp(uv+vel/vec2f(du)*5.0,vec2f(0.0),vec2f(1.0)),0.0).rgb;let grad=vec2f(e.x-w.x,n.x-s.x);let rim=pow(clamp(length(grad)*7.0,0.0,1.0),0.65);
 let rayleigh=vec3f(0.18,0.62,2.4)*scatter;let mie=vec3f(2.6,1.45,0.42)*(0.35+0.65*audio.x);let hdr=(rayleigh*(0.3+rim)+mie*energy)*rho*light;
 let halo=(n.y+s.y+e.y+w.y)*0.25*bloom;let trans=exp(-rho*densityGain);let color=scene*trans+hdr+halo*vec3f(0.3,0.65,1.5)+rho*audio*0.1;
 textureStore(writeTexture,p,vec4f(aces(color),clamp(1.0-trans+rim*0.2,0.0,1.0)));
}
