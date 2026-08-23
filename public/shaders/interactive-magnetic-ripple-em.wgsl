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
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);let dt=clamp((1.0 / 60.0),0.0,0.033);
 let fieldGain=0.25+2.75*u.zoom_params.x;let waveSpeed=0.08+0.82*u.zoom_params.y;let damping=0.005+0.16*u.zoom_params.z;let spectral=0.4+2.6*u.zoom_params.w;let audio=plasmaBuffer[0].xyz;
 let c=stateAt(p,d);let n=stateAt(p+vec2i(0,1),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);
 let gradB=0.5*vec2f(e.z-w.z,n.z-s.z);let curlE=0.5*((e.y-w.y)-(n.x-s.x));var electric=c.xy+waveSpeed*vec2f(gradB.y,-gradB.x);var magnetic=c.z+waveSpeed*curlE;
 let divE=0.5*((e.x-w.x)+(n.y-s.y));electric-=vec2f(e.x-w.x,n.y-s.y)*divE*0.025;let decay=exp(-damping*(0.6+dt*30.0));electric*=decay;magnetic*=decay;
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);let r2=dot(q,q)+0.0004;let held=step(0.5,u.zoom_config.w);let dipole=held*exp(-r2*220.0);
 electric+=dipole*normalize(vec2f(-q.y,q.x)+vec2f(0.0001))*(0.025+audio.y*0.08)*fieldGain;magnetic+=dipole*sin(u.config.x*6.0)*(0.035+audio.x*0.09)*fieldGain;
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<2.4){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let radius=age*(0.11+0.16*waveSpeed);let ring=exp(-pow((length(cq)-radius)*64.0,2.0))*exp(-age*damping*7.0);let tangent=normalize(vec2f(-cq.y,cq.x)+vec2f(0.0001));electric+=tangent*ring*(0.018+audio.y*0.055)*fieldGain;magnetic+=ring*(0.02+audio.z*0.07)*select(-1.0,1.0,(i%2u)==0u);}}
 let energy=clamp(mix(c.w,dot(electric,electric)+magnetic*magnetic,0.12)*(1.0-damping*0.08),0.0,4.0);electric=clamp(electric,vec2f(-2.5),vec2f(2.5));magnetic=clamp(magnetic,-2.5,2.5);textureStore(dataTextureA,p,vec4f(electric,magnetic,energy));
 let fieldMag=length(electric);let direction=atan2(electric.y,electric.x);let filings=pow(0.5+0.5*cos(direction*10.0+length(vec2f(p))*0.08+magnetic*4.0),12.0)*smoothstep(0.03,0.7,fieldMag);
 let spectralColor=0.5+0.5*cos(vec3f(0.0,2.094,4.189)+magnetic*spectral*4.0+energy*2.0);let warped=clamp(uv+electric/vec2f(du)*(3.0+spectral*4.0),vec2f(0.0),vec2f(1.0));let scene=textureSampleLevel(readTexture,u_sampler,warped,0.0).rgb;
 let emission=spectralColor*(energy*0.55+filings*1.6)*fieldGain+vec3f(audio.x,audio.y*0.6,audio.z)*fieldMag*0.16;textureStore(writeTexture,p,vec4f(aces(scene*(0.82-0.18*clamp(energy,0.0,1.0))+emission),clamp(energy*0.32+filings*0.45,0.0,1.0)));
}
