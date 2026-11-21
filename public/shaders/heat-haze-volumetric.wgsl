// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Volumetric — persistent heat + column field refracting the photo through six slices of hot air
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware
//  Upgraded: 2026-11-21
//  Ideas: sun-baked surface heat source (scene luma); Boussinesq buoyancy (§12.2D); coherent convective eddies (curl of value noise, Gladstone–Dale weight)
//  A packing: raw sim state (vx, vy, heat, column); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
fn aces(x:vec3f)->vec3f{let a=2.51;let b=0.03;let c=2.43;let d=0.59;let e=0.14;return clamp((x*(a*x+vec3f(b)))/(x*(c*x+vec3f(d))+vec3f(e)),vec3f(0.0),vec3f(1.0));}
fn stateAt(p:vec2i,d:vec2i)->vec4f{return textureLoad(dataTextureC,clamp(p,vec2i(0),d-vec2i(1)),0);}
fn hash21(p:vec2f)->f32{return fract(sin(dot(p,vec2f(113.5,271.9)))*43758.5453);}
// ── integer lattice hash, copied verbatim from public/shaders/_std/_std_hash.wgsl (pcg2d, u32ToUnit, hashCell21) ──
fn pcg2d(v_in: vec2<u32>) -> vec2<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  v.x += v.y * 1664525u;
  v.y += v.x * 1664525u;
  v = v ^ (v >> vec2<u32>(16u));
  return v;
}
fn u32ToUnit(x: u32) -> f32 {
  return f32(x >> 8u) * (1.0 / 16777216.0);
}
fn hashCell21(c: vec2<i32>) -> f32 {
  return u32ToUnit(pcg2d(bitcast<vec2<u32>>(c)).x);
}
// ── Idea 3 helper: curl of a quintic value-noise field (analytic gradient) = a divergence-free convected eddy vector ──
fn eddyCurl(q:vec2f)->vec2f{
 let i=vec2i(floor(q));let f=fract(q);let fu=f*f*f*(f*(f*6.0-15.0)+10.0);let dq=30.0*f*f*(f*(f-2.0)+1.0);
 let a=hashCell21(i);let b=hashCell21(i+vec2i(1,0));let cc=hashCell21(i+vec2i(0,1));let dd=hashCell21(i+vec2i(1,1));
 return vec2f(dq.y*mix(cc-a,dd-b,fu.x),-dq.x*mix(b-a,dd-cc,fu.y));
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
 let du=textureDimensions(dataTextureC);if(gid.x>=du.x||gid.y>=du.y){return;}let p=vec2i(gid.xy);let d=vec2i(du);let uv=(vec2f(gid.xy)+0.5)/vec2f(du);let dt=clamp((1.0 / 60.0),0.0,0.033);
 let strength=0.3+2.7*u.zoom_params.x;let refract=0.5+7.5*u.zoom_params.y;let depth=0.25+2.75*u.zoom_params.z;let turb=u.zoom_params.w;let audio=plasmaBuffer[0].xyz;
 // scene photo (idea 1 reads its luma; the display pass reuses it) and scene distance (readDepthTexture: 1 = near, 0 = far / no map)
 let base=textureSampleLevel(readTexture,u_sampler,uv,0.0).rgb;let sceneZ=clamp(textureSampleLevel(readDepthTexture,non_filtering_sampler,uv,0.0).r,0.0,1.0);
 let c=stateAt(p,d);let n=stateAt(p+vec2i(0,1),d);
 // ── Idea 2 (drift): the semi-Lagrangian pull takes the lift of this cell OR the cell below it (n = below on screen); HEAD used this cell's heat only, so an empty cell above a hot one never drew it up ──
 let lift=max(c.z-0.35*c.w,n.z-0.35*n.w);let adv=stateAt(p-vec2i(round((c.xy+vec2f(0.0,-lift*0.4))*vec2f(du)*dt)),d);let s=stateAt(p-vec2i(0,1),d);let e=stateAt(p+vec2i(1,0),d);let w=stateAt(p-vec2i(1,0),d);let avg=(n+s+e+w)*0.25;
 var velocity=mix(adv.xy,avg.xy,0.04);var heat=mix(adv.z,avg.z,0.055);var column=mix(adv.w,avg.w,0.025);
 velocity+=vec2f(n.z-s.z,w.z-e.z)*(0.15+0.55*turb);
 // ── Idea 3: coherent convective eddies — the curl of value noise scrolled up the plume replaces the per-pixel white-hash velocity jitter ──
 let eL=max(f32(du.y)*0.05,4.0);let rise=u.config.x*0.8;let eNear=eddyCurl(vec2f(p)/eL+vec2f(0.0,rise));let eFar=eddyCurl(vec2f(p)/(eL*2.2)+vec2f(17.3,rise*0.6+9.1));
 velocity+=eNear*0.006*turb;
 // ── Idea 2: Boussinesq buoyancy f_y=(αT−βρ)g — hot air rises (−y is up the picture), dense residual haze settles (HEAD pushed +y = down) ──
 velocity+=vec2f(0.0,-(heat-0.35*column)*0.03);
 let aspect=u.config.z/max(u.config.w,1.0);let mp=u.zoom_config.yz;let q=(uv-mp)*vec2f(aspect,1.0);let brush=step(0.5,u.zoom_config.w)*exp(-dot(q,q)*250.0);
 heat+=brush*(0.035+audio.x*0.09)*strength;column+=brush*(0.025+audio.y*0.06)*depth;velocity+=brush*vec2f(audio.z-audio.y,-(0.08+audio.x*0.1)); // thermal kick now points up the picture (HEAD +y = down)
 // ── Idea 1: sun-baked surfaces — bright (sunlit) pixels of the photo radiate heat and a thin hot-air column; HEAD only ever heated under the pointer ──
 let sunlit=smoothstep(0.45,0.9,dot(base,vec3f(0.2126,0.7152,0.0722)));heat+=sunlit*sunlit*0.0065*strength;column+=sunlit*0.0016*depth;
 let clicks=min(u32(max(u.config.y,0.0)),50u);for(var i=0u;i<clicks;i=i+1u){let event=u.ripples[i];let age=u.config.x-event.z;if(age>=0.0&&age<1.7){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);let rw=(length(cq)-(0.02+age*0.2))*62.0;let ring=exp(-rw*rw)*exp(-age*1.6);heat+=ring*(0.025+audio.z*0.05);column+=ring*0.02;velocity+=normalize(cq+vec2f(0.0001))*ring*0.06;}}
 heat=clamp(heat*exp(-dt*0.6),0.0,2.0);column=clamp(column*exp(-dt*0.22),0.0,2.0);velocity=clamp(velocity*exp(-dt*1.3),vec2f(-1.0),vec2f(1.0));textureStore(dataTextureA,p,vec4f(velocity,heat,column));
 let grad=vec2f(e.z-w.z,n.z-s.z);var accum=vec3f(0.0);var trans=1.0;
 // optical path length: far scene content is seen through more hot air (depth 1 = near; no depth map reads 0 → ×1.0 = HEAD)
 let path=0.5+0.5*(1.0-sceneZ);let refractivity=0.4+min(heat,1.5); // Gladstone–Dale: n−1 ∝ ρ_air, so deflection tracks the heat contrast
 for(var j=0;j<6;j++){let z=(f32(j)+0.5)/6.0;let shimmer=mix(eNear,eFar,z)*vec2f(1.5,2.0)*refractivity*turb;let offset=(grad+velocity*0.25+shimmer)*refract*(0.25+z)*path/vec2f(du);let sampleColor=textureSampleLevel(readTexture,u_sampler,clamp(uv+offset,vec2f(0.0),vec2f(1.0)),0.0).rgb;let extinction=exp(-column*depth*0.07);accum+=trans*sampleColor*(1.0-extinction);trans*=extinction;}
 let glow=heat*vec3f(1.8,0.35,0.04)*(0.1+audio.z*0.2);textureStore(writeTexture,p,vec4f(aces(base*trans+accum+glow),clamp(column*0.38+heat*0.16,0.0,1.0)));
 textureStore(writeDepthTexture,p,vec4f(sceneZ,0.0,0.0,0.0));
}
