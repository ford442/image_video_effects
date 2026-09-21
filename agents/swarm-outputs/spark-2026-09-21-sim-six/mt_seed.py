import numpy as np
from mt_fix import lap, gs
N=96; rng=np.random.default_rng(2)
def run(p,steps=2500):
    f1,k1=0.01+0.07*p[0],0.04+0.03*p[1]; f2,k2=0.02+0.04*p[2],0.05+0.015*p[3]
    seed=(rng.random((N,N))<0.02).astype(float)
    a1=np.ones((N,N)); b1=seed*0.5; a2=np.ones((N,N)); b2=seed*0.5
    for t in range(steps):
        n1=gs(a1,b1,lap(a1,1),lap(b1,1),f1,k1); n2=gs(a2,b2,lap(a2,2),lap(b2,2),f2,k2)
        a1,b1=n1; a2,b2=n2
        a1,b1=a1+(a2-a1)*0.01,b1+(b2-b1)*0.01; a2,b2=a2+(a1-a2)*0.005,b2+(b1-b2)*0.005
    return b1,b2
for p in [(.5,.5,.5,.5),(.3,.7,.3,.7),(.35,.6,.4,.6),(.2,.8,.2,.8)]:
    b1,b2=run(p); print(p,'b1 mean %.3f std %.3f | b2 mean %.3f std %.3f'%(b1.mean(),b1.std(),b2.mean(),b2.std()))
