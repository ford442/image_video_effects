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
fn hash21(p:vec2f)->f32{return fract(sin(dot(p,vec2f(67.3,327.1)))*43758.5453);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);let dt=clamp((1.0 / 60.0),0.0,0.033);
 let densityGain=0.2+2.2*u.zoom_params.x;let height=0.08+0.84*u.zoom_params.y;let depthWeight=0.3+2.7*u.zoom_params.z;let turb=u.zoom_params.w;let audio=plasmaBuffer[0].xyz;
 let c=stateAt(p,d);let adv=stateAt(p-vec2i(round(c.yz*vec2f(du)*dt)),d);let n=stateAt(p+vec2i(0,1),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);let avg=(n+s+e+w)*0.25;
 var rho=mix(adv.x,avg.x,0.045+0.04*turb);var vel=mix(adv.yz,avg.yz,0.045);var moisture=mix(adv.w,avg.w,0.025);
 let terrain=exp(-pow((uv.y-height)*(3.0+3.0*height),2.0));rho+=terrain*dt*(0.025+audio.x*0.06)*densityGain;vel+=vec2f(n.x-s.x,w.x-e.x)*(0.12+0.4*turb)+(vec2f(hash21(vec2f(p)+u.config.x),hash21(vec2f(p.yx)-u.config.x))-0.5)*0.014*turb;
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);let held=step(0.5,u.zoom_config.w);let clear=held*exp(-dot(q,q)*150.0);rho*=1.0-clear*0.12;moisture+=clear*(0.018+audio.y*0.04);vel+=clear*normalize(q+vec2f(0.0001))*0.045;
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<2.5){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let ring=exp(-pow((length(cq)-age*0.12)*50.0,2.0))*exp(-age);rho+=ring*(0.012+audio.x*0.035);moisture+=ring*(0.02+audio.z*0.04);vel+=normalize(cq+vec2f(0.0001))*ring*0.04;}}
 rho=clamp(rho*exp(-dt*0.16),0.0,2.5);moisture=clamp(moisture*exp(-dt*0.3),0.0,2.0);vel=clamp(vel*exp(-dt*1.1),vec2f(-0.8),vec2f(0.8));textureStore(dataTextureA,p,vec4f(rho,vel,moisture));
 let scene=textureSampleLevel(readTexture,u_sampler,clamp(uv+vel/vec2f(du)*4.0,vec2f(0.0),vec2f(1.0)),0.0).rgb;var trans=1.0;var inscatter=vec3f(0.0);let sun=normalize(vec3f(-0.45,0.35,0.82));
 for(var j=0;j<8;j++){let z=(f32(j)+0.5)/8.0;let layer=rho*(0.65+0.5*hash21(vec2f(p)+vec2f(f32(j)*31.0,u.config.x*0.4)))*(1.15-z*0.5);let absorb=exp(-layer*densityGain*depthWeight*0.1);let phase=0.55+0.45*pow(max(sun.z,0.0),4.0);let fogColor=mix(vec3f(0.2,0.32,0.48),vec3f(1.4,0.92,0.5),phase)*(0.18+moisture*0.08+audio.y*0.06);inscatter+=trans*(1.0-absorb)*fogColor;trans*=absorb;}
 textureStore(writeTexture,p,vec4f(aces(scene*trans+inscatter),clamp(1.0-trans,0.0,1.0)));
}
