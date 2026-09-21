import numpy as np, sys
N=96
def nb(x):  # n,s,e,w with clamp-to-edge
    p=np.pad(x,((1,1),(1,1)),mode='edge')
    return [p[2:,1:-1],p[:-2,1:-1],p[1:-1,2:],p[1:-1,:-2]]
def run(ring, steps=900, wet=.5, dif=.5, evap=.8):
    yy,xx=np.mgrid[0:N,0:N]; r=np.hypot(yy-N/2,xx-N/2)
    W=(r<25)*0.9; P=(r<25)*0.5
    dt=1/60
    for t in range(steps):
        Ws=nb(W); Ps=nb(P)
        aw=sum(Ws)/4; ap=sum(Ps)/4
        water=np.clip(W+(aw-W)*(0.035+0.18*wet),0,1)
        pig=np.maximum(P+(ap-P)*(0.012+0.16*dif*(0.2+water)),0)
        if ring:
            k=0.12
            fin=sum(np.maximum(wn-W,0)*(W>0.01)*pn for wn,pn in zip(Ws,Ps))
            fout=sum(np.maximum(W-wn,0)*(wn>0.01) for wn in Ws)*P
            pig=np.maximum(pig+k*(fin-fout),0)
        pig*=np.exp(-dt*(0.08+0.42*evap))
        W=np.clip(water*np.exp(-dt*(0.14+0.75*evap)),0,1); P=pig
    prof=[P[N//2, N//2+d] for d in (0,10,18,22,25,28,32)]
    return P.sum(), W.max(), prof
for m in (0,1):
    s,w,prof=run(m); print('ring' if m else 'head','total pigment %.1f  maxWater %.3f  profile centre->out'%(s,w),' '.join('%.3f'%v for v in prof))
