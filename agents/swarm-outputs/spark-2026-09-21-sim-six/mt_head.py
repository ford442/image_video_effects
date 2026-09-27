import numpy as np
N=128; rng=np.random.default_rng(1)
lum=np.tile(np.linspace(0,1,N),(N,1))
def lap(x,s):
    return np.roll(x,s,0)+np.roll(x,-s,0)+np.roll(x,s,1)+np.roll(x,-s,1)-4*x
def gs(a,b,la,lb,f,k,DA=1.0,DB=0.5,DT=1.0):
    r=a*b*b
    return np.clip(a+(DA*la-r+f*(1-a))*DT,0,1),np.clip(b+(DB*lb+r-(k+f)*b)*DT,0,1)
a1=np.ones((N,N)); b1=lum*0.5+rng.random((N,N))*0.3
a2=np.ones((N,N)); b2=lum*0.3+rng.random((N,N))*0.3
f1,k1=0.01+0.07*.5,0.04+0.03*.5; f2,k2=0.02+0.04*.5,0.05+0.015*.5
for t in range(3000):
    # HEAD: laplacian at scale s samples texel*s (s=1 and 2)
    n1=gs(a1,b1,lap(a1,1),lap(b1,1),f1,k1); n2=gs(a2,b2,lap(a2,2),lap(b2,2),f2,k2)
    a1,b1=n1; a2,b2=n2
    a1,b1=a1+(a2-a1)*0.01,b1+(b2-b1)*0.01
    a2,b2=a2+(a1-a2)*0.005,b2+(b1-b2)*0.005
    if t in (10,100,1000,2999):
        cb=np.abs(b1-np.roll(b1,1,1)).mean()
        print(t,'b1 mean %.3f std %.3f  pixel-to-pixel jump %.3f  b2 mean %.3f std %.3f'%(b1.mean(),b1.std(),cb,b2.mean(),b2.std()))
np.save('mt_head_b1.npy',b1)
