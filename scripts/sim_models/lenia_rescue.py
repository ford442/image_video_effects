"""Numpy port of the rescued lenia.wgsl update rule (keep in sync with the WGSL).

Run: python3 scripts/sim_models/lenia_rescue.py  (~1-2 min). Prints, per slider combo, at steps 300 and
1200: field mean, mean per-step change, share of mid-range cells, high-frequency energy. Alive = mean in
~0.02..0.3 with change > 0.001; dead = mean 0; flooded = mean -> 1; speckle = hf ~ mean.
"""
import numpy as np, itertools, sys
N=112
PACK=0.006   # growth-packet amplitude
VISC=0.5     # viscosity: blend toward the 4-neighbour mean
PEAKS=np.array([0.5,1.0,0.667])
def params(p):
    R=8.0+3.5*p[0]; dt=0.05+0.10*p[1]; mu=0.135+0.035*p[3]; sig=mu*0.094
    return R,dt,mu,sig
def kernel(R):
    rr=int(np.ceil(R)); k=np.zeros((N,N))
    for y in range(-rr,rr+1):
        for x in range(-rr,rr+1):
            r=np.hypot(x,y)/R
            if r<=0 or r>=1: continue
            br=r*3; i=min(int(br),2); f=br-int(br)
            if f<=0 or f>=1: continue
            k[y%N,x%N]+=PEAKS[i]*np.exp(4-1/(f*(1-f)))
    return np.fft.fft2(k/k.sum())
def smooth_noise(x,y,e,R):
    # Smooth (≈R/2-scale) noise: per-pixel hash noise freezes into a speckle soup.
    k=1.6/R
    return 0.5+0.25*(np.sin(x*k*1.3+e*1.7+np.sin(y*k*0.9))+np.sin(y*k*1.1-e*2.3+np.sin(x*k*0.7)))
def hash2(x,y):
    return np.modf(np.sin(x*127.1+y*311.7)*43758.5453)[0]%1.0
def seed(R):
    yy,xx=np.mgrid[0:N,0:N].astype(float)
    cell=2.6*R; cx=np.floor(xx/cell); cy=np.floor(yy/cell)
    h=hash2(cx,cy); jx=hash2(cx+7,cy+3); jy=hash2(cx+1,cy+9)
    c=np.stack([(cx+0.25+0.5*jx)*cell,(cy+0.25+0.5*jy)*cell])
    d=np.hypot(xx-c[0],yy-c[1])/(cell*0.32)
    noise=smooth_noise(xx,yy,0.0,R)
    return np.where((h>0.2)&(d<1), noise*(1-d*d)*1.2, 0).clip(0,1)
yy0,xx0=np.mgrid[0:N,0:N]; uvx=(xx0+.5)/N; uvy=(yy0+.5)/N
def spore(R,time,U):
    # Empty neighbourhoods re-seed: each 2.6R cell drops a noisy blob once per ~3 s epoch.
    yy,xx=np.mgrid[0:N,0:N].astype(float); cell=2.6*R
    cx=np.floor(xx/cell); cy=np.floor(yy/cell)
    phase=time/3.0+hash2(cx+5,cy+2); epoch=np.floor(phase)
    fire=(hash2(cx+epoch*13.1,cy-epoch*7.7)>0.3)&((phase-epoch)<0.05)
    jx=hash2(cx+epoch,cy+3); jy=hash2(cx+1,cy+epoch)
    d=np.hypot(xx-(cx+0.25+0.5*jx)*cell,yy-(cy+0.25+0.5*jy)*cell)/(cell*0.32)
    noise=smooth_noise(xx,yy,epoch,R)
    return np.where(fire&(d<1)&(U<0.03),noise*(1-d*d)*1.2,0).clip(0,1)
def run(p,steps=1200):
    R,dt,mu,sig=params(p); FK=kernel(R); S=seed(R); prev=S; out=[]
    for t in range(steps):
        # Same order as the WGSL: potential from the previous field, viscosity on the previous
        # field, then growth, packets, and spores where the neighbourhood is empty.
        U=np.real(np.fft.ifft2(np.fft.fft2(S)*FK))
        Ssm=S+VISC*((np.roll(S,1,0)+np.roll(S,-1,0)+np.roll(S,1,1)+np.roll(S,-1,1))*0.25-S)
        time=t/60.0
        ph=(uvx*0.846+uvy*0.533)*(18+R)-time*(5+p[1]*10)
        packet=(0.5+0.5*np.sin(ph))**12*PACK
        S=np.clip(Ssm+dt*(2*np.exp(-0.5*((U-mu)/sig)**2)-1)+packet,0,1)
        S=np.maximum(S,spore(R,time,U))
        if t in (299,1199): out.append((S.mean(),np.abs(S-prev).mean(),((S>0.05)&(S<0.95)).mean(),np.abs(S-0.25*(np.roll(S,1,0)+np.roll(S,-1,0)+np.roll(S,1,1)+np.roll(S,-1,1))).mean()))
        prev=S
    if len(sys.argv)>1: np.save('lenia_final_%s.npy'%'_'.join(map(str,p)),S)
    return out
combos=[(0.5,0.5,0.5,0.5)]+[tuple(v if i==k else 0.5 for i in range(4)) for k in (0,1,3) for v in (0.0,1.0)]+[(0,0,0.5,1),(1,1,0.5,0)]
for p in combos:
    print(p,' | '.join('mean %.3f change %.4f mid %.2f hf %.4f'%o for o in run(p)),flush=True)
