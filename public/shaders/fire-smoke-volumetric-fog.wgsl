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
fn aces(x: vec3f) -> vec3f {
  let a=2.51; let b=0.03; let c=2.43; let d=0.59; let e=0.14;
  return clamp((x*(a*x+vec3f(b)))/(x*(c*x+vec3f(d))+vec3f(e)),vec3f(0.0),vec3f(1.0));
}
fn stateAt(p: vec2i,d: vec2i)->vec4f{return textureLoad(dataTextureC,clamp(p,vec2i(0),d-vec2i(1)),0);}
fn hash21(p:vec2f)->f32{return fract(sin(dot(p,vec2f(127.1,311.7)))*43758.5453);}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid:vec3u){
  let du=textureDimensions(dataTextureC); if(gid.x>=du.x||gid.y>=du.y){return;}
  let p=vec2i(gid.xy); let d=vec2i(du); let uv=(vec2f(gid.xy)+0.5)/vec2f(du);
  let dt=clamp((1.0 / 60.0),0.0,0.033); let audio=plasmaBuffer[0].xyz;
  let heatGain=0.5+2.5*u.zoom_params.x; let smokeGain=0.3+2.0*u.zoom_params.y;
  let fogDepth=0.4+2.6*u.zoom_params.z; let turb=u.zoom_params.w;
  let c=stateAt(p,d); let rise=vec2f(c.w*0.35,(0.3+c.y)*1.4)*dt*vec2f(du);
  let adv=stateAt(p-vec2i(round(rise)),d); let n=stateAt(p+vec2i(0,1),d); let s=stateAt(p-vec2i(0,1),d);
  let e=stateAt(p+vec2i(1,0),d); let w=stateAt(p-vec2i(1,0),d); let avg=(n+s+e+w)*0.25;
  var density=mix(adv.x,avg.x,0.025+0.055*turb); var temp=mix(adv.y,avg.y,0.035);
  var soot=mix(adv.z,avg.z,0.018); var momentum=mix(adv.w,avg.w,0.04);
  momentum+=(n.x-s.x+w.x-e.x)*0.1*turb+(hash21(vec2f(p)+u.config.x)-0.5)*0.035*turb;
  let aspect=u.config.zw.x/max(u.config.zw.y,1.0);
  let mp=u.zoom_config.yz;
  let q=(uv-mp)*vec2f(aspect,1.0); let held=step(0.5,u.zoom_config.w);
  let source=held*exp(-dot(q,q)*300.0);
  temp+=source*(0.055+audio.z*0.12)*heatGain; density+=source*(0.02+audio.x*0.07)*smokeGain;
  soot+=source*(0.012+audio.y*0.035); momentum+=source*(audio.y-audio.z)*0.08;
  let clicks=min(u32(max(u.config.y,0.0)),50u);
  for(var i=0u;i<clicks;i=i+1u){
    let event=u.ripples[i]; let age=u.config.x-event.z;
    if(age>=0.0&&age<1.8){let cp=event.xy;let cq=(uv-cp)*vec2f(aspect,1.0);
      let ring=exp(-pow((length(cq)-(0.03+age*0.2))*60.0,2.0))*exp(-age*1.7);
      density+=ring*(0.018+audio.x*0.04);temp+=ring*(0.025+audio.z*0.07);soot+=ring*0.012;momentum+=ring*0.04;}
  }
  density=clamp(density*exp(-dt*(0.25+0.2/smokeGain)),0.0,2.5);
  temp=clamp(temp*exp(-dt*(0.75+0.2/heatGain)),0.0,2.5); soot=clamp(soot*exp(-dt*0.18),0.0,2.0);
  momentum=clamp(momentum*exp(-dt*1.4),-1.5,1.5); textureStore(dataTextureA,p,vec4f(density,temp,soot,momentum));
  let scene=textureSampleLevel(readTexture,u_sampler,clamp(uv+vec2f(momentum,temp)*vec2f(1.0,-1.0)/vec2f(du)*6.0,vec2f(0.0),vec2f(1.0)),0.0).rgb;
  var trans=1.0; var volume=vec3f(0.0);
  for(var j=0;j<7;j++){let z=(f32(j)+0.5)/7.0;let layer=density*(0.45+0.75*hash21(vec2f(p)+vec2f(f32(j)*19.0,u.config.x*2.0)));
    let absorb=exp(-layer*fogDepth*0.18);let flame=mix(vec3f(5.2,0.35,0.03),vec3f(5.5,2.2,0.28),smoothstep(0.15,1.4,temp));
    let smoke=vec3f(0.10,0.115,0.14)*(0.6+soot);volume+=trans*(flame*temp*temp*(1.0-z)*0.06+smoke*layer*0.13);trans*=absorb;}
  volume+=density*vec3f(audio.x*0.09,audio.y*0.05,audio.z*0.08);
  textureStore(writeTexture,p,vec4f(aces(scene*trans+volume),clamp(1.0-trans,0.0,1.0)));
}
