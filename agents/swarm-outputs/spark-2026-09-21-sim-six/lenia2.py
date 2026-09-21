import numpy as np, sys
N=128
lum=np.tile(np.linspace(0,1,N),(N,1))   # dark left -> bright right
def ss(e0,e1,x):
    t=np.clip((x-e0)/(e1-e0),0,1); return t*t*(3-2*t)
def run(mode, steps=1500, seed=3, p=(0.5,0.5,0.5,0.5)):
    rng=np.random.default_rng(seed)
    radius=3+p[0]*10; gr=0.008+p[1]*0.085; thr=0.18+(0.72-0.18)*p[3]
    nr=int(radius*0.5+1)
    offs=[(y,x,1/(1+x*x+y*y)) for y in range(-nr,nr+1) for x in range(-nr,nr+1) if (x,y)!=(0,0)]
    ws=sum(w for *_,w in offs)
    S=np.zeros((N,N)); S[40:60,40:60]=rng.random((20,20)); S[70:90,80:110]=rng.random((20,30))
    yy,xx=np.mgrid[0:N,0:N]; uvx=(xx+.5)/N; uvy=(yy+.5)/N
    hist=[]; prev=S.copy()
    for t in range(steps):
        time=t/60
        dp=np.round(np.array([np.cos(time*1.17),np.sin(time*1.17*0+time*0.83)])*(1+p[1]*3)).astype(int)
        A=np.roll(np.roll(S,dp[1],0),dp[0],1)   # advected sample
        avg=sum(np.roll(np.roll(A,-y,0),-x,1)*w for y,x,w in offs)/ws
        center=A
        n=np.array([1,0.63]);n/=np.linalg.norm(n)
        ph=(uvx*n[0]+uvy*n[1])*(18+radius)-time*(5+p[1]*10)
        packet=(0.5+0.5*np.sin(ph))**12*0.025
        g=np.exp(-0.5*((avg-0.5)/0.15)**2)*2-1
        if mode in ('nutrient','contnut'): g=g+(lum-0.5)*0.9
        c=np.clip(center+gr*g+packet,0,1)
        S=c if mode.startswith('cont') else ss(thr*0.5,max(thr,0.01),c)
        if t%300==299: hist.append((t,S.mean(),S[:,:N//3].mean(),S[:,-N//3:].mean(),S.std(), np.abs(S-prev).mean()))
        prev=S.copy()
    return hist
for m in sys.argv[1:]:
    print(m); [print('  t=%d mean %.3f  darkThird %.3f  brightThird %.3f  std %.3f  change/frame %.4f'%h) for h in run(m)]
