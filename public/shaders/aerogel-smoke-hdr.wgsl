// ═══════════════════════════════════════════════════════════════════
//  Aerogel Smoke HDR
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-21
//  Ideas: Rayleigh lambda^-4 chromatic extinction (§12.2F); phase functions toward a lamp, HG + Rayleigh lobe (§12.2F); energy-conserving bloom (§12.2F)
//  A packing: raw sim state (rho, energy, vel.xy); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
fn aces(x:vec3f)->vec3f{let a=2.51;let b=0.03;let c=2.43;let d=0.59;let e=0.14;return clamp((x*(a*x+vec3f(b)))/(x*(c*x+vec3f(d))+vec3f(e)),vec3f(0.0),vec3f(1.0));}
fn stateAt(p:vec2i,d:vec2i)->vec4f{return textureLoad(dataTextureC,clamp(p,vec2i(0),d-vec2i(1)),0);}
fn hash21(p:vec2f)->f32{return fract(sin(dot(p,vec2f(91.7,271.9)))*43758.5453);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);
 let dt=clamp((1.0 / 60.0),0.0,0.033);let densityGain=0.25+1.8*u.zoom_params.x;let scatter=0.3+2.7*u.zoom_params.y;
 let light=max(u.zoom_params.z,0.0);let bloom=u.zoom_params.w;let audio=plasmaBuffer[0].xyz;let c=stateAt(p,d);
 // follow-up rescue (same fix as fork C's jelly): sub-pixel semi-Lagrangian back-trace, 4 exact textureLoads blended by hand (no filtering sampler on rgba32float),
 // instead of round(vel*res*dt), whose integer snap + per-axis rounding terraced every plume into rectangles.
 let sp=vec2f(p)-c.zw*vec2f(du)*dt;let i0=vec2i(floor(sp));let fr=sp-floor(sp);
 let adv=mix(mix(stateAt(i0,d),stateAt(i0+vec2i(1,0),d),fr.x),mix(stateAt(i0+vec2i(0,1),d),stateAt(i0+vec2i(1,1),d),fr.x),fr.y);let n=stateAt(p+vec2i(0,1),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);let avg=(n+s+e+w)*0.25;
 var rho=mix(adv.x,avg.x,0.06);var energy=mix(adv.y,avg.y,0.08);var vel=mix(adv.zw,avg.zw,0.05);
 // follow-up rescue: HEAD's rho-gradient swirl (gain 0.22) saturates at every density cliff (steady state ~10x the 2-px difference), pinning velocity there and shearing the rim into
 // axis-aligned facets. Same gain for faint smoke, soft-saturated per-frame injection (max 0.22*0.025) so a cliff cannot drive it.
 let gs=vec2f(n.x-s.x,w.x-e.x);vel+=gs*(0.22*0.025/(0.025+length(gs)))+(vec2f(hash21(vec2f(p)+u.config.x),hash21(vec2f(p.yx)-u.config.x))-0.5)*0.012;
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);
 let brush=step(0.5,u.zoom_config.w)*exp(-dot(q,q)*190.0);rho+=brush*(0.018+audio.x*0.06)*densityGain;energy+=brush*(0.025+audio.z*0.08)*light;vel+=brush*normalize(q+vec2f(0.0001))*0.05;
 // rescue (Finding 1): HEAD is pass-through until the pointer or a click feeds it. Same brush on autopilot: Lissajous path, 25 % strength, off while the pointer is held.
 let ip=(uv-vec2f(0.5+0.28*sin(u.config.x*0.37),0.6+0.18*sin(u.config.x*0.53+1.3)))*vec2f(aspect,1.0);let idle=(1.0-step(0.5,u.zoom_config.w))*0.25*exp(-dot(ip,ip)*190.0);
 rho+=idle*(0.018+audio.x*0.06)*densityGain;energy+=idle*(0.025+audio.z*0.08)*light;vel+=idle*normalize(ip+vec2f(0.0001))*0.05;
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<2.3){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let rr=(length(cq)-age*0.15)*48.0;let ring=exp(-rr*rr)*exp(-age*1.2);rho+=ring*(0.015+audio.y*0.04);energy+=ring*(0.02+audio.z*0.06);vel+=normalize(cq+vec2f(0.0001))*ring*0.035;}}
 rho=clamp(rho*exp(-dt*0.24),0.0,2.0);energy=clamp(energy*exp(-dt*0.52),0.0,3.0);vel*=exp(-dt*1.25);vel*=min(1.0,1.0/max(length(vel),0.0001));textureStore(dataTextureA,p,vec4f(rho,energy,vel));
 let scene=textureSampleLevel(readTexture,u_sampler,clamp(uv+vel/vec2f(du)*5.0,vec2f(0.0),vec2f(1.0)),0.0).rgb;let grad=vec2f(e.x-w.x,n.x-s.x);let rim=pow(clamp(length(grad)*7.0,0.0,1.0),0.65);
 // ── Idea 1: Rayleigh lambda^-4 chromatic extinction (§12.2F). sigma = (650/lambda)^4 for R,G,B, normalised to mean 1 -> (0.41,0.80,1.79); the Blue Scatter slider
 // blends it toward grey (keeps its role: how blue the medium is). Transmitted light reddens, scattered light stays blue. In-scatter is also capped by the same
 // Beer-Lambert, (1-exp(-tau))/tau: the light the smoke scatters is what it removed from the beam, so thick smoke no longer scatters without limit (thin smoke unchanged).
 let sig=mix(vec3f(1.0),vec3f(0.41,0.80,1.79),clamp(scatter*0.4,0.0,1.0));let tau=rho*densityGain;let transC=exp(-tau*sig);let trans=(transC.x+transC.y+transC.z)/3.0;let selfAtt=(1.0-exp(-tau))/max(tau,0.001);
 // ── Idea 2: phase functions toward a lamp (§12.2F HG term + Rayleigh lobe). A lamp just behind the smoke drifts slowly; cosT is the angle between the view ray and the
 // lamp. Blue Rayleigh term gets 0.75(1+cos^2), warm Mie term gets a forward HG (g=0.6) with a soft inverse-square. Light Intensity keeps its role as the overall gain.
 let lampV=vec3f((vec2f(0.5+0.3*cos(u.config.x*0.17+0.6),0.3+0.1*sin(u.config.x*0.23))-uv)*vec2f(aspect,1.0),0.45);let lampD2=dot(lampV,lampV);let cosT=lampV.z*inverseSqrt(lampD2);
 let rPhase=0.75*(1.0+cosT*cosT);let mPhase=clamp(0.64/pow(1.36-1.2*cosT,1.5)*0.9/(0.25+lampD2),0.2,5.0);
 // ── Idea 3: energy-conserving bloom (§12.2F). HEAD's halo was added ON TOP of the core, doubling the light. Now the core gives up k of its scatter and the wide ring (inner
 // 4 taps + 4 diagonal taps at ~1/90 of the height) gets it back; k rides the HDR Bloom slider. Halo vector is HEAD's blue-white tint scaled to carry the same total at bloom 0.5.
 let br=i32(max(2.0,f32(du.y)/90.0));let wide=(n.y+s.y+e.y+w.y+stateAt(p+vec2i(br,br),d).y+stateAt(p+vec2i(-br,br),d).y+stateAt(p+vec2i(br,-br),d).y+stateAt(p+vec2i(-br,-br),d).y)*0.125;let k=0.4*bloom;
 let rayleigh=vec3f(0.18,0.62,2.4)*scatter;let mie=vec3f(2.6,1.45,0.42)*(0.35+0.65*audio.x);let hdr=(rayleigh*rPhase*(0.3+rim)+mie*mPhase*energy)*rho*light*selfAtt*(1.0-k);
 let color=scene*transC+hdr+wide*k*vec3f(0.75,1.63,3.75)+rho*audio*0.1;
 textureStore(writeTexture,p,vec4f(aces(color),clamp(1.0-trans+rim*0.2,0.0,1.0)));
}
