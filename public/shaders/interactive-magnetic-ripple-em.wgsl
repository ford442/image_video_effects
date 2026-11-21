// ═══════════════════════════════════════════════════════════════════
//  Interactive Magnetic Ripple EM
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-21
//  Ideas: dielectric photo medium: eps_r = 1 + 2*luma slows the wave, fronts refract around bright objects (§12.2D wave equation in matter);
//         absorbing sponge boundary: quadratic conductivity ramp so waves leave the frame (§12.2D);
//         Poynting-flux energy transport: upwind advection of the energy glow by S/u (§12.1 tactic 7)
//  Rescues: Faraday sign (HEAD was elliptic: one click pinned 99% of the frame at |B|=2.5 within 5 s) -> staggered Yee-style update
//           + linear div-clean; damping + source amplitude recalibrated for a stable wave; idle antenna orbiting the pointer; pow(x,2.0) -> x*x
//  A packing: raw sim state (Ex, Ey, B, energy); ACES only on writeTexture
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
fn aces(x:vec3f)->vec3f{let a=2.51;let b=0.03;let c=2.43;let d=0.59;let e=0.14;return clamp((x*(a*x+vec3f(b)))/(x*(c*x+vec3f(d))+vec3f(e)),vec3f(0.0),vec3f(1.0));}
fn stateAt(p:vec2i,d:vec2i)->vec4f{return textureLoad(dataTextureC,clamp(p,vec2i(0),d-vec2i(1)),0);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);let dt=clamp((1.0 / 60.0),0.0,0.033);
 let fieldGain=0.25+2.75*u.zoom_params.x;let waveSpeed=0.08+0.82*u.zoom_params.y;let damping=0.005+0.16*u.zoom_params.z;let spectral=0.4+2.6*u.zoom_params.w;let audio=plasmaBuffer[0].xyz;
 let c=stateAt(p,d);let n=stateAt(p+vec2i(0,1),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);
 
 // ── Rescue R1: staggered (Yee-style) Faraday/Ampere update ──────────────────────────────────────────────
 // HEAD did B += c*curlE next to E += c*curlB, i.e. d2B/dt2 = -laplacian(B): elliptic, exponential growth (a single click pinned 99% of the
 // frame at |B|=2.5 within 5 s) and, with only the sign flipped but still forward Euler, a blow-up at the default speed. Here B is advanced
 // first with FORWARD differences of E and E is then advanced from the NEW B with BACKWARD differences (the adjoint pair), which conserves the
 // discrete energy and needs only 7 state loads (HEAD: 5). Stable for c <= 1/sqrt(2), so the propagation constant is waveSpeed*0.77 (top of the
 // slider = 0.69 cells/frame); the slider keeps its full range and its role.
 let cw=waveSpeed*0.77;
 let nw=stateAt(p+vec2i(-1,1),d);let se=stateAt(p+vec2i(1,-1),d);
 let bC=c.z-cw*((e.y-c.y)-(n.x-c.x));let bW=w.z-cw*((c.y-w.y)-(nw.x-w.x));let bS=s.z-cw*((se.y-s.y)-(c.x-s.x));
 // ── Idea 1: dielectric photo medium (§12.2D wave equation in matter) ────────────────────────────────────
 // The photo's luma is the relative permittivity: eps_r = 1 + 2*luma, Ampere becomes eps_r*dE/dt = curl B, so the wave speed is
 // c/sqrt(eps_r): fronts slow down inside bright objects and bend around them. Needs one photo sample; the file already samples it.
 let medium=textureSampleLevel(readTexture,u_sampler,uv,0.0).rgb;let epsR=1.0+2.0*dot(medium,vec3f(0.299,0.587,0.114));
 var electric=c.xy+(cw/epsR)*vec2f(bC-bS,-(bC-bW));var magnetic=bC;
 
 // ── Rescue R1b: HEAD's divergence clean was E -= (dEx/dx, dEy/dy)*divE*0.025 — quadratic in the field with an indefinite sign, and it alone
 // made an otherwise stable run grow without bound (bisected by removing it: |B| reached the 2.5 clamp with it, stayed ~0.13 without). Same intent (damp the longitudinal part of E), linear and dissipative:
 // E += kappa * grad(div E) with the divergence from forward differences and its gradient from backward ones (all inside the 7 loaded cells).
 let dvC=(e.x-c.x)+(n.y-c.y);let dvW=(c.x-w.x)+(nw.y-w.y);let dvS=(se.x-s.x)+(c.y-s.y);
 electric+=0.05*vec2f(dvC-dvW,dvC-dvS);
 // ── Rescue R2: HEAD's exp(-damping*1.1) (~0.91/frame at the default slider) only made sense while the instability fed the field;
 // a stable wave would die within ~5 cells. Same slider role (more = dies faster), 0.04 per frame*slider.
 // The same instability also supplied the AMPLITUDE: sources of ~0.03/frame were amplified ~1e4x into a saturated field, and the display thresholds
 // (smoothstep(0.03,0.7,|E|), energy*0.55) were tuned to that. A stable wave driven by the same sources peaks at |B|~0.1-0.5 (click ~0.14) and is nearly invisible, so every
 // source term below carries srcCal (a calibration constant, not a new slider; field_strength keeps its role as the overall amplitude).
 let srcCal=2.5;
 // ── Idea 2: absorbing sponge boundary (§12.2D): quadratic conductivity ramp in the outer 9% so waves leave instead of
 // reflecting off HEAD's clamp-to-edge mirror and filling the frame with standing interference.
 let edgeD=min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y));let ramp=1.0-smoothstep(0.0,0.09,edgeD);
 let decay=exp(-damping*0.04)*(1.0-0.15*ramp*ramp);electric*=decay;magnetic*=decay;
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);let r2=dot(q,q)+0.0004;let held=step(0.5,u.zoom_config.w);let dipole=held*exp(-r2*220.0);
 electric+=dipole*normalize(vec2f(-q.y,q.x)+vec2f(0.0001))*(0.025+audio.y*0.08)*fieldGain*srcCal;magnetic+=dipole*sin(u.config.x*6.0)*(0.035+audio.x*0.09)*fieldGain*srcCal;
 // ── Rescue R3: idle antenna. HEAD had no source without a held pointer or a click (meanA 0.000, picture == photo). When the
 // pointer is not held the same dipole runs at 0.35x on a small orbit around the pointer (default 0.5,0.5); held behaviour is unchanged.
 let orb=u.config.x*0.35;let qa=(uv-(mp+0.16*vec2f(cos(orb),sin(orb*1.3))))*vec2f(aspect,1.0);let idleDip=(1.0-held)*exp(-dot(qa,qa)*220.0)*0.35;
 electric+=idleDip*normalize(vec2f(-qa.y,qa.x)+vec2f(0.0001))*(0.025+audio.y*0.08)*fieldGain*srcCal;magnetic+=idleDip*sin(u.config.x*6.0)*(0.035+audio.x*0.09)*fieldGain*srcCal;
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<2.4){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let radius=age*(0.11+0.16*waveSpeed);let rr=(length(cq)-radius)*64.0;let ring=exp(-rr*rr)*exp(-age*damping*7.0);let tangent=normalize(vec2f(-cq.y,cq.x)+vec2f(0.0001));electric+=tangent*ring*(0.018+audio.y*0.055)*fieldGain*srcCal;magnetic+=ring*(0.02+audio.z*0.07)*srcCal*select(-1.0,1.0,(i%2u)==0u);}}
 
 // ── Idea 3: Poynting-flux energy transport (§12.1 tactic 7: direction, not just magnitude) ───────────────────
 // HEAD's energy channel was the isotropic smoothed E^2+B^2. Energy actually travels along S = E x B at the energy velocity S/u;
 // first-order upwind advection with the four neighbours already loaded (0 extra loads) makes the glow move with the front.
 let uDens=dot(electric,electric)+magnetic*magnetic;let flux=vec2f(electric.y*magnetic,-electric.x*magnetic);
 var cfl=flux/(uDens+0.02)*(2.0*cw);cfl*=min(1.0,0.9/max(abs(cfl.x)+abs(cfl.y),0.00001));
 let advEnergy=c.w-abs(cfl.x)*(c.w-select(w.w,e.w,cfl.x<0.0))-abs(cfl.y)*(c.w-select(s.w,n.w,cfl.y<0.0));
 let energy=clamp(mix(advEnergy,uDens,0.12)*(1.0-damping*0.08),0.0,4.0);electric=clamp(electric,vec2f(-2.5),vec2f(2.5));magnetic=clamp(magnetic,-2.5,2.5);textureStore(dataTextureA,p,vec4f(electric,magnetic,energy));
 let fieldMag=length(electric);let direction=atan2(electric.y,electric.x);let filings=pow(0.5+0.5*cos(direction*10.0+length(vec2f(p))*0.08+magnetic*4.0),12.0)*smoothstep(0.03,0.7,fieldMag);
 let spectralColor=0.5+0.5*cos(vec3f(0.0,2.094,4.189)+magnetic*spectral*4.0+energy*2.0);let warped=clamp(uv+electric/vec2f(du)*(3.0+spectral*4.0),vec2f(0.0),vec2f(1.0));let scene=textureSampleLevel(readTexture,u_sampler,warped,0.0).rgb;
 let emission=spectralColor*(energy*0.55+filings*1.6)*fieldGain+vec3f(audio.x,audio.y*0.6,audio.z)*fieldMag*0.16;textureStore(writeTexture,p,vec4f(aces(scene*(0.82-0.18*clamp(energy,0.0,1.0))+emission),clamp(energy*0.32+filings*0.45,0.0,1.0)));
}
