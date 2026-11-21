// ═══════════════════════════════════════════════════════════════════
//  Atmospheric Fog Volumetric
//  Category: advanced-hybrid
//  Features: depth-aware, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-21
//  Ideas: Beer-Lambert on real scene depth (§12.2F); HG forward scatter toward a per-pixel sun (§12.2F); exponential height fog (§12.2F)
//  A packing: raw sim state (rho, vel.xy, moisture); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
fn aces(x:vec3f)->vec3f{let a=2.51;let b=0.03;let c=2.43;let d=0.59;let e=0.14;return clamp((x*(a*x+vec3f(b)))/(x*(c*x+vec3f(d))+vec3f(e)),vec3f(0.0),vec3f(1.0));}
fn stateAt(p:vec2i,d:vec2i)->vec4f{return textureLoad(dataTextureC,clamp(p,vec2i(0),d-vec2i(1)),0);}
fn hash21(p:vec2f)->f32{return fract(sin(dot(p,vec2f(67.3,327.1)))*43758.5453);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);let dt=clamp((1.0 / 60.0),0.0,0.033);
 let densityGain=0.2+2.2*u.zoom_params.x;let height=0.08+0.84*u.zoom_params.y;let depthWeight=0.3+2.7*u.zoom_params.z;let turb=u.zoom_params.w;let audio=plasmaBuffer[0].xyz;
 let c=stateAt(p,d);
 // follow-up rescue (same fix as aerogel / fork C's jelly): sub-pixel semi-Lagrangian back-trace, 4 exact textureLoads blended by hand (no filtering sampler on rgba32float),
 // instead of round(vel*res*dt), whose integer snap + per-axis rounding terraced every disturbance into rectangles.
 let sp=vec2f(p)-c.yz*vec2f(du)*dt;let i0=vec2i(floor(sp));let fr=sp-floor(sp);
 let adv=mix(mix(stateAt(i0,d),stateAt(i0+vec2i(1,0),d),fr.x),mix(stateAt(i0+vec2i(0,1),d),stateAt(i0+vec2i(1,1),d),fr.x),fr.y);let n=stateAt(p+vec2i(0,1),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);let avg=(n+s+e+w)*0.25;
 var rho=mix(adv.x,avg.x,0.045+0.04*turb);var vel=mix(adv.yz,avg.yz,0.045);var moisture=mix(adv.w,avg.w,0.025);
 let th=(uv.y-height)*(3.0+3.0*height);let terrain=exp(-th*th);rho+=terrain*dt*(0.025+audio.x*0.06)*densityGain;// follow-up rescue: the rho-gradient swirl saturates at density cliffs (same defect as aerogel); same gain for faint fog, soft-saturated injection so a cliff cannot drive it.
 let gs=vec2f(n.x-s.x,w.x-e.x);vel+=gs*((0.12+0.4*turb)*0.025/(0.025+length(gs)))+(vec2f(hash21(vec2f(p)+u.config.x),hash21(vec2f(p.yx)-u.config.x))-0.5)*0.014*turb;
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);let held=step(0.5,u.zoom_config.w);let clear=held*exp(-dot(q,q)*150.0);rho*=1.0-clear*0.12;moisture+=clear*(0.018+audio.y*0.04);vel+=clear*normalize(q+vec2f(0.0001))*0.045;
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<2.5){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let rr=(length(cq)-age*0.12)*50.0;let ring=exp(-rr*rr)*exp(-age);rho+=ring*(0.012+audio.x*0.035);moisture+=ring*(0.02+audio.z*0.04);vel+=normalize(cq+vec2f(0.0001))*ring*0.04;}}
 rho=clamp(rho*exp(-dt*0.16),0.0,2.5);moisture=clamp(moisture*exp(-dt*0.3),0.0,2.0);vel*=exp(-dt*1.1);vel*=min(1.0,0.8/max(length(vel),0.0001));textureStore(dataTextureA,p,vec4f(rho,vel,moisture));
 let scene=textureSampleLevel(readTexture,u_sampler,clamp(uv+vel/vec2f(du)*4.0,vec2f(0.0),vec2f(1.0)),0.0).rgb;var trans=1.0;var inscatter=vec3f(0.0);let sun=normalize(vec3f(-0.45,0.35,0.82));
 // ── Idea 1: Beer-Lambert on real scene depth (§12.2F). The DPT map is inverse depth (1 = near), so distance = 1 - depth. A slice only
 // counts while it lies in FRONT of the surface; near objects stay crisp, far ones sink into the fog. No depth map (all 0) -> dist = 1 -> HEAD's full 8 slices.
 let dist=0.08+0.92*(1.0-clamp(textureSampleLevel(readDepthTexture,non_filtering_sampler,uv,0.0).r,0.0,1.0));
 // ── Idea 2: HG forward scatter toward a real per-pixel sun direction (§12.2F). HEAD's phase came from the constant sun.z, so every pixel got the same
 // in-scatter. The view ray differs per pixel: glare warm+bright around the sun, cooler+dimmer away from it. Two lobes (g=+0.55 / -0.2), normalised to ~1 at frame centre.
 let ray=normalize(vec3f((uv.x-0.5)*aspect,0.5-uv.y,1.0));let cs=dot(ray,sun);
 let hg=mix((1.0-0.04)/pow(1.04+0.4*cs,1.5),(1.0-0.3025)/pow(1.3025-1.1*cs,1.5),0.7)*0.48;
 let phase=clamp(0.3+0.453*hg,0.0,1.0);let glare=0.45+0.55*hg;
 // ── Idea 3: exponential height fog (§12.2F). Density thins with height along the ray: rays climbing out of the layer (upper frame) lose fog with distance,
 // the bank hugs the ground the Fog Height slider positions. One exp per pixel; per-slice factor built by repeated multiply.
 let hStep=exp(-max(0.5-uv.y,0.0)*2.6/(8.0*(0.15+0.55*height)));var hf=sqrt(hStep);
 for(var j=0;j<8;j++){let z=(f32(j)+0.5)/8.0;let front=1.0-smoothstep(dist-0.05,dist+0.05,z);let layer=rho*(0.65+0.5*hash21(vec2f(p)+vec2f(f32(j)*31.0,u.config.x*0.4)))*(1.15-z*0.5)*front*hf;hf*=hStep;let absorb=exp(-layer*densityGain*depthWeight*0.1);let fogColor=mix(vec3f(0.2,0.32,0.48),vec3f(1.4,0.92,0.5),phase)*(0.18+moisture*0.08+audio.y*0.06)*glare;inscatter+=trans*(1.0-absorb)*fogColor;trans*=absorb;}
 textureStore(writeTexture,p,vec4f(aces(scene*trans+inscatter),clamp(1.0-trans,0.0,1.0)));
}
