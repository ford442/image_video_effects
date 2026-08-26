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
fn hash21(p:vec2f)->f32{return fract(sin(dot(p,vec2f(113.5,271.9)))*43758.5453);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);let dt=clamp((1.0 / 60.0),0.0,0.033);
 let strength=0.3+2.7*u.zoom_params.x;let refract=0.5+7.5*u.zoom_params.y;let depth=0.25+2.75*u.zoom_params.z;let turb=u.zoom_params.w;let audio=plasmaBuffer[0].xyz;
 let c=stateAt(p,d);let adv=stateAt(p-vec2i(round((c.xy+vec2f(0.0,c.z*0.4))*vec2f(du)*dt)),d);let n=stateAt(p+vec2i(0,1),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);let avg=(n+s+e+w)*0.25;
 var velocity=mix(adv.xy,avg.xy,0.04);var heat=mix(adv.z,avg.z,0.055);var column=mix(adv.w,avg.w,0.025);
 velocity+=vec2f(n.z-s.z,w.z-e.z)*(0.15+0.55*turb);
 velocity+=(vec2f(hash21(vec2f(p)+u.config.x),hash21(vec2f(p.yx)-u.config.x))-vec2f(0.5))*0.015*turb+vec2f(0.0,heat*0.018);
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);let brush=step(0.5,u.zoom_config.w)*exp(-dot(q,q)*250.0);
 heat+=brush*(0.035+audio.x*0.09)*strength;column+=brush*(0.025+audio.y*0.06)*depth;velocity+=brush*vec2f(audio.z-audio.y,0.08+audio.x*0.1);
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<1.7){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let ring=exp(-pow((length(cq)-(0.02+age*0.2))*62.0,2.0))*exp(-age*1.6);heat+=ring*(0.025+audio.z*0.05);column+=ring*0.02;velocity+=normalize(cq+vec2f(0.0001))*ring*0.06;}}
 heat=clamp(heat*exp(-dt*0.6),0.0,2.0);column=clamp(column*exp(-dt*0.22),0.0,2.0);velocity=clamp(velocity*exp(-dt*1.3),vec2f(-1.0),vec2f(1.0));textureStore(dataTextureA,p,vec4f(velocity,heat,column));
 let grad=vec2f(e.z-w.z,n.z-s.z);var accum=vec3f(0.0);var trans=1.0;
 for(var j=0;j<6;j++){let z=(f32(j)+0.5)/6.0;let shimmer=(hash21(vec2f(p)+vec2f(f32(j)*23.0,u.config.x*8.0))-0.5)*turb;let offset=(grad+velocity*0.25+shimmer*vec2f(1.0,-0.7))*refract*(0.25+z)/vec2f(du);let sampleColor=textureSampleLevel(readTexture,u_sampler,clamp(uv+offset,vec2f(0.0),vec2f(1.0)),0.0).rgb;let extinction=exp(-column*depth*0.07);accum+=trans*sampleColor*(1.0-extinction);trans*=extinction;}
 let base=textureSampleLevel(readTexture,u_sampler,uv,0.0).rgb;let glow=heat*vec3f(1.8,0.35,0.04)*(0.1+audio.z*0.2);textureStore(writeTexture,p,vec4f(aces(base*trans+accum+glow),clamp(column*0.38+heat*0.16,0.0,1.0)));
}
