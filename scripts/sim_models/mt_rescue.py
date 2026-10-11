"""Numpy port of the rescued multi-turing.wgsl rule (keep in sync with the WGSL).

Run: python3 scripts/sim_models/mt_rescue.py  (~1-2 min). Prints b1 mean, b std per scale and the mean
neighbour jump at steps 120/600/1500. Patterns = std > 0.05; uniform = std -> 0; checkerboard = jump ~ 1.
"""
import numpy as np, sys
N=128
yy,xx=np.mgrid[0:N,0:N].astype(float)
lum=0.5+0.4*np.sin(xx/17)*np.cos(yy/23)   # stand-in for source luminance
def hash2(x,y): return np.modf(np.sin(x*127.1+y*311.7)*43758.5453)[0]%1.0
def lap(Z,s):
    # Karl Sims' 3x3 kernel (0.2 edge, 0.05 corner, -1 centre) at tap spacing s.
    adj=np.roll(Z,s,0)+np.roll(Z,-s,0)+np.roll(Z,s,1)+np.roll(Z,-s,1)
    dia=sum(np.roll(np.roll(Z,i,0),j,1) for i in (s,-s) for j in (s,-s))
    return 0.2*adj+0.05*dia-Z
def params(p):
    # Kill is an offset from the centre of the pattern band, which runs diagonally in (F, K).
    kc=lambda F: 0.064-0.35*max(0.05-F,0.0)
    F1=0.025+0.040*p[0]; K1=kc(F1)-0.0025+0.005*p[1]
    F2=0.030+0.030*p[2]; K2=kc(F2)-0.0015+0.003*p[3]
    return F1,K1,F2,K2
DA,DB,DT=1.0,0.5,1.0
def seed():
    # Sparse spots: an 8 px cell holds a spot with probability rising with luminance.
    cx=np.floor(xx/8); cy=np.floor(yy/8)
    on=hash2(cx,cy)<0.12+0.25*lum
    d=np.hypot(xx-(cx*8+4),yy-(cy*8+4))
    b=np.where(on&(d<2.5),0.5+0.5*hash2(xx,yy),0.0)
    return np.ones((N,N)),b
def run(p,steps=1500):
    F1,K1,F2,K2=params(p)
    a1,b1=seed(); a2,b2=seed()
    out=[]
    for t in range(steps):
        def step(a,b,s,F,K):
            r=a*b*b
            L=(lambda Z: lap(Z,1)) if s==1 else (lambda Z: 0.75*lap(Z,2)+0.25*lap(Z,1))
            return (np.clip(a+(DA*L(a)-r+F*(1-a))*DT,0,1), np.clip(b+(DB*L(b)+r-(K+F)*b)*DT,0,1))
        n1=step(a1,b1,1,F1,K1); n2=step(a2,b2,2,F2,K2)
        a1,b1=n1; a2,b2=n2
        c=0.002; b1=b1+(b2-b1)*c; b2=b2+(b1-b2)*c*0.5
        if t in (119,599,1499):
            nb=np.abs(np.roll(b1,1,1)-b1).mean()
            out.append((b1.mean(),b1.std(),b2.std(),nb))
    if len(sys.argv)>1: np.save('mt_%s.npy'%'_'.join(map(str,p)),np.stack([b1,b2]))
    return out
combos=[(0.5,)*4,(0,0,0,0),(1,1,1,1),(0,1,0,1),(1,0,1,0),(0,0.5,0.5,0.5),(1,0.5,0.5,0.5),(0.5,0,0.5,0.5),(0.5,1,0.5,0.5),(0.5,0.5,0,0.5),(0.5,0.5,1,0.5),(0.5,0.5,0.5,0),(0.5,0.5,0.5,1)]
for p in combos:
    print(p,' | '.join('b1 %.3f sd1 %.3f sd2 %.3f nbjump %.3f'%o for o in run(p)),flush=True)
