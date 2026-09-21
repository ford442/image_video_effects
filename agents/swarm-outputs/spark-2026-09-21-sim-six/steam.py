import numpy as np, sys
H,Wd=120,160
def hash21(x,y): return np.modf(np.sin(x*127.1+y*311.7)*43758.5453)[0]%1.0
def nb(x):
    p=np.pad(x,((1,1),(1,1)),mode='edge'); return p[1:-1,:-2],p[1:-1,2:],p[:-2,1:-1],p[2:,1:-1]  # L R T(above) B
def run(new, steps=1800, p=(0.8,0.2,0.3,0.5)):
    fog=0.08+(1.15-0.08)*p[0]; ret=0.002+(0.038-0.002)*p[1]
    S=np.zeros((H,Wd)); D=np.zeros((H,Wd)); R=np.zeros((H,Wd))
    yy,xx=np.mgrid[0:H,0:Wd]
    nuc=hash21(np.floor(xx/1.0),np.floor(yy/1.0)+3.0)
    out=[]
    for t in range(steps):
        L,Rt,T,B=nb(S); avgS=(L+Rt+T+B)/4
        L2,R2,T2,B2=nb(D); avgD=(L2+R2+T2+B2)/4
        Tb=nb(R)[2]
        steam=S+(avgS-S)*0.045; steam+=(fog-steam)*ret
        drops=D+(avgD-D)*0.025; drops+=np.maximum(steam-0.46,0)*0.004
        if not new:
            run_=R+(Tb-R)*0.08+drops*0.0008
        else:
            # rivulet: sparse nucleation sites release heavy droplets as a running bead
            site=(nuc>0.9965)
            release=np.where(site&(drops>0.28),drops,0.0)
            carried=Tb*0.975                       # bead moves down one texel/frame
            run_=np.maximum(carried, R*0.90)+release
            pick=drops*np.minimum(run_,1)*0.25       # bead sweeps droplets on its track
            drops=drops-pick-release; run_=run_+pick*0.5
            track=np.clip(run_*2.0,0,0.85)
            steam=steam*(1-track); drops=drops*(1-track*0.8)
        run_=np.clip(run_*0.992,0,1)
        S=np.clip(steam,0,1.25); D=np.clip(drops*0.995,0,1); R=run_
        if t%300==299:
            out.append((t,S.mean(),D.mean(),R.mean(),(R>0.05).mean(),((S<0.5*fog)).mean()))
    return out
for m in (1,):
    for o in run(m): print('new' if m else 'head','t=%d steam %.3f drops %.3f runoff %.4f  runoffPixels %.3f  clearedPixels %.3f'%o)
