// ═══════════════════════════════════════════════════════════════════
//  Liquid Lens — multi-lobed liquid lens under the pointer, premium caustic optics.
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Upgraded: 2026-11-21
//  Ideas: Snell-law refraction (§12.2F Snell vector refraction); Jacobian-determinant caustic (ray-density of the warp); deviation-proportional lateral CA (prism law)
//  A packing: display RGBA history (A=writeTexture colour, C read as colour). B and extraBuffer are intentionally unused.
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
fn boundedLoad(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> { let c=clamp(vec2<i32>(floor(uv*vec2<f32>(dims))),vec2<i32>(0),dims-vec2<i32>(1)); return textureLoad(dataTextureC,c,0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x*(2.51*x+0.03))/max(x*(2.43*x+0.59)+0.14,vec3<f32>(0.001)),vec3<f32>(0.0),vec3<f32>(1.0)); }
fn lensLobe(p:vec2<f32>,c:vec2<f32>,r:f32,lobes:f32,phase:f32)->vec2<f32>{let q=p-c;let d=max(length(q),0.0001);if(d>=r*1.13){return vec2<f32>(0.0);}let b=r*(1.0+0.13*sin(atan2(q.y,q.x)*lobes+phase));let h=1.0-smoothstep(b*0.35,b,d);return q/d*h*(b-d)/max(b,0.001);}
// The main (pointer) lens lobe exactly as HEAD built it; a function so the Jacobian can re-evaluate it at neighbouring points.
fn lensMain(p:vec2<f32>,mp:vec2<f32>,radius:f32,held:f32,t:f32)->vec2<f32>{return lensLobe(p,mp,radius*(1.0-held*0.18),5.0,t*2.8)*(1.0+held*2.1);}
// ── Idea 1: Snell-law refraction. HEAD's flow = bend*refraction is the small-angle limit of Snell. For a ray entering a liquid (eta = 1/1.33)
// at slope s the lateral shift per unit slope is (1 - eta*cosI/cosT)/(1 - eta) times that linear value: 1 at flat, superlinear where the
// surface is steep (lens core, harder when held), bounded by 1/(1-eta) = 4. Slope lever 0.4 on |bend| (a slope-like field).
fn snellGain(b:vec2<f32>)->f32{let s=length(b)*0.4;let cosI=inverseSqrt(1.0+s*s);let cosT=sqrt(max(1.0-0.5625*(1.0-cosI*cosI),0.0001));return (1.0-0.75*cosI/cosT)*4.0;}
@compute @workgroup_size(16,16,1)
fn main(@builtin(global_invocation_id) gid:vec3<u32>){
 let res=u.config.zw;if(gid.x>=u32(res.x)||gid.y>=u32(res.y)){return;}let coord=vec2<i32>(gid.xy);let uv=(vec2<f32>(gid.xy)+0.5)/res;let dims=vec2<i32>(res);let aspect=res.x/max(res.y,1.0);let t=u.config.x;let audio=clamp(plasmaBuffer[0].xyz,vec3<f32>(0.0),vec3<f32>(1.0));
 let refraction=0.012+u.zoom_params.x*0.065;let radius=0.10+u.zoom_params.y*0.34;let dispersion=0.001+u.zoom_params.z*0.018;let waves=0.15+u.zoom_params.w*1.35;let pointer=u.zoom_config.yz;let held=clamp(u.zoom_config.w,0.0,1.0);let p=(uv-0.5)*vec2<f32>(aspect,1.0);let mp=(pointer-0.5)*vec2<f32>(aspect,1.0);
 let orbitA=mp+vec2<f32>(cos(t*2.3),sin(t*2.7))*(0.10+audio.x*0.035);let orbitB=mp+vec2<f32>(cos(-t*3.1+2.0),sin(t*2.1+2.0))*0.17;let bMain=lensMain(p,mp,radius,held,t);var bend=bMain+lensLobe(p,orbitA,radius*0.36,3.0,-t*4.0)*0.62+lensLobe(p,orbitB,radius*0.25,4.0,t*5.0)*0.42;
 let mesh=sin((p.x+p.y)*42.0-t*7.5)*sin((p.x-p.y)*35.0+t*6.0);bend+=vec2<f32>(sin(p.y*29.0+t*5.4),cos(p.x*31.0-t*4.7))*mesh*waves*0.0008;var ring=0.0;let count=min(u32(max(u.config.y,0.0)),50u);
 for(var i=0u;i<count;i=i+1u){let r=u.ripples[i];let age=t-r.z;if(age>=0.0&&age<3.0){let q=(uv-r.xy)*vec2<f32>(aspect,1.0);let d=max(length(q),0.0001);let front=sin((d-age*0.30)*70.0)*exp(-abs(d-age*0.30)*20.0-age*0.8);bend+=vec2<f32>(q.x/aspect,q.y)/d*front*refraction;ring+=abs(front);}}
 let refrK=refraction*(1.0+audio.y*0.55);let flow=vec2<f32>(bend.x/aspect,bend.y)*refrK*snellGain(bend);let baseUV=clamp(uv-flow,vec2<f32>(0.0),vec2<f32>(1.0));
 // ── Idea 3: deviation-proportional lateral CA. A prism's colour fringe is a fixed fraction (Abbe ratio) of its deviation, so once |flow| is a real
 // refraction (>2e-3) the fringe width follows it: dispersion*|flow|/0.0445 (0.0445 = default refraction => the default lens core keeps HEAD's
 // width), floored at 0.35 and capped at 2x so a pressed lens does not smear. HEAD used full width wherever |flow|>1e-4, i.e. colour ghosts on the
 // lens skirts and ripple tails; below 2e-4 (the faint surface-wave shimmer) the weight stays exactly 1 = HEAD.
 let fm=length(flow);let dir=flow/max(fm,0.0001);let spread=dir*dispersion*(1.0+audio.z*0.7)*mix(1.0,clamp(fm/0.0445,0.35,2.0),smoothstep(0.0002,0.002,fm));
 // ── Idea 2: Jacobian-determinant caustic. The warp is uv' = uv - flow(uv); |det(I - dflow/dp)| is its screen->source area ratio = ray density:
 // >1 where the source is compressed into the screen (focal core, bright rim), <1 where it is stretched (dim fold ring). Forward differences of
 // the Snell-scaled MAIN lens lobe at centre, +x, +y (the lenslets keep the mesh/ring caustic; a 3-lobe difference measured ~1.35x, over cost cap).
 var focus=0.0;var stretched=0.0;if(dot(bMain,bMain)>0.0){let hJ=2.0/res.y;let bJx=lensMain(p+vec2<f32>(hJ,0.0),mp,radius,held,t);let bJy=lensMain(p+vec2<f32>(0.0,hJ),mp,radius,held,t);let F0=bMain*snellGain(bMain);
 let dFx=(bJx*snellGain(bJx)-F0)*(refrK/hJ);let dFy=(bJy*snellGain(bJy)-F0)*(refrK/hJ);
 let area=clamp(abs((1.0-dFx.x)*(1.0-dFy.y)-dFy.x*dFx.y),0.0,4.0);focus=clamp(area-1.0,0.0,2.0);stretched=clamp(1.0-area,0.0,1.0);}let sr=textureSampleLevel(readTexture,u_sampler,clamp(baseUV+spread,vec2<f32>(0.0),vec2<f32>(1.0)),0.0);let sg=textureSampleLevel(readTexture,u_sampler,baseUV,0.0);let sb=textureSampleLevel(readTexture,u_sampler,clamp(baseUV-spread,vec2<f32>(0.0),vec2<f32>(1.0)),0.0);let history=boundedLoad(clamp(uv-flow*0.35,vec2<f32>(0.0),vec2<f32>(1.0)),dims);
 let caustic=pow(clamp(abs(mesh)*length(bend)*9.0+ring*0.35+focus*1.0,0.0,1.0),2.0);let normal=normalize(vec3<f32>(-bend*5.0,1.0));let fresnel=0.04+0.96*pow(1.0-max(normal.z,0.0),5.0);var rgb=vec3<f32>(sr.r,sg.g,sb.b)*(1.0-0.3*stretched);rgb+=mix(vec3<f32>(0.05,0.82,0.94),vec3<f32>(1.0,0.48,0.08),0.5+0.5*sin(t*1.9+p.x*8.0))*caustic*(0.28+audio.y*0.4);rgb+=vec3<f32>(0.32,0.7,0.9)*fresnel*0.3;rgb=mix(rgb,history.rgb,clamp(history.a*0.12,0.0,0.16));let alpha=clamp(max(max(sr.a,sg.a),sb.a)*0.86+fresnel*0.12+caustic*0.16,0.0,1.0);let outColor=vec4<f32>(aces(rgb),alpha);textureStore(writeTexture,coord,outColor);textureStore(dataTextureA,coord,outColor);let depth=textureSampleLevel(readDepthTexture,non_filtering_sampler,baseUV,0.0).r;textureStore(writeDepthTexture,coord,vec4<f32>(clamp(depth-caustic*0.02,0.0,1.0),0.0,0.0,0.0));
}
