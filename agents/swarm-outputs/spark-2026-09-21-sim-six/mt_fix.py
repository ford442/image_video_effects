import numpy as np, sys
N=160; rng=np.random.default_rng(1)
lum=np.tile(np.linspace(0,1,N),(N,1))
def R(x,dy,dx): return np.roll(np.roll(x,dy,0),dx,1)
def lap(x,s):
    e=R(x,s,0)+R(x,-s,0)+R(x,0,s)+R(x,0,-s); d=R(x,s,s)+R(x,-s,s)+R(x,s,-s)+R(x,-s,-s)
    return 0.2*e+0.05*d-x
def gs(a,b,la,lb,f,k):
    r=a*b*b
    return np.clip(a+(1.0*la-r+f*(1-a)),0,1),np.clip(b+(0.5*lb+r-(k+f)*b),0,1)
def run(p, steps=4000, extra=None):
    f1,k1=0.01+0.07*p[0],0.04+0.03*p[1]; f2,k2=0.02+0.04*p[2],0.05+0.015*p[3]
    a1=np.ones((N,N)); b1=lum*0.5+rng.random((N,N))*0.3
    a2=np.ones((N,N)); b2=lum*0.3+rng.random((N,N))*0.3
    for t in range(steps):
        F1,K1=f1,k1
        if extra: F1,K1=extra(a1,b1,a2,b2,f1,k1)
        n1=gs(a1,b1,lap(a1,1),lap(b1,1),F1,K1); n2=gs(a2,b2,lap(a2,2),lap(b2,2),f2,k2)
        a1,b1=n1; a2,b2=n2
        a1,b1=a1+(a2-a1)*0.01,b1+(b2-b1)*0.01
        a2,b2=a2+(a1-a2)*0.005,b2+(b1-b2)*0.005
    return b1,b2
if __name__=='__main__':
    for p in [(.5,.5,.5,.5),(0,0,0,0),(1,1,1,1),(.3,.7,.3,.7),(.7,.3,.7,.3)]:
        b1,b2=run(p)
        print(p,'b1 mean %.3f std %.3f jump %.3f | b2 mean %.3f std %.3f'%(b1.mean(),b1.std(),np.abs(b1-np.roll(b1,1,1)).mean(),b2.mean(),b2.std()))
