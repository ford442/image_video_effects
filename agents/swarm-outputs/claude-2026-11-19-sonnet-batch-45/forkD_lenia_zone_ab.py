import sys; sys.argv=[sys.argv[0]]
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import forkD_lenia_model as m
from PIL import Image
N=224; m.N=N
yy,xx=np.mgrid[0:N,0:N]; m.uvx=(xx+.5)/N; m.uvy=(yy+.5)/N
p=(0.5,0.5,0.5,0.5); R,dt,mu,sig=m.params(p)
k=1.0/(3.0*R); X=xx.astype(float); Y=yy.astype(float); T=9.0
zone=0.5+0.25*(np.sin(X*k*1.1+T*0.045+np.sin(Y*k*0.8))+np.sin(Y*k*0.9-T*0.037+np.sin(X*k*1.3)))
print('zone range',zone.min(),zone.max(),'period px',2*np.pi/(k*1.1))
muL=mu+(zone-0.5)*0.02
outs={}
for name,mo in (('uniform',mu),('zones',muL)):
    S=None
    # run() returns stats only; reimplement to keep final field
    R,dt,_,_=m.params(p); FK=m.kernel(R); S=m.seed(R)
    mu_a=mo if np.ndim(mo) else np.full((N,N),mo); sg=mu_a*0.094
    for t in range(700):
        U=np.real(np.fft.ifft2(np.fft.fft2(S)*FK))
        Ssm=S+m.VISC*((np.roll(S,1,0)+np.roll(S,-1,0)+np.roll(S,1,1)+np.roll(S,-1,1))*0.25-S)
        time=t/60.0
        ph=(m.uvx*0.846+m.uvy*0.533)*(18+R)-time*(5+p[1]*10)
        pk=(0.5+0.5*np.sin(ph))**12*m.PACK
        S=np.clip(Ssm+dt*(2*np.exp(-0.5*((U-mu_a)/sg)**2)-1)+pk,0,1)
        S=np.maximum(S,m.spore(R,time,U))
    outs[name]=S
    print(name,'mean %.3f mid %.2f'%(S.mean(),((S>0.05)&(S<0.95)).mean()))
def img(a): return Image.fromarray((np.clip(a,0,1)*255).astype(np.uint8))
w=Image.new('L',(N*3+8,N))
w.paste(img(outs['uniform']),(0,0)); w.paste(img(outs['zones']),(N+4,0)); w.paste(img((zone-zone.min())/(zone.max()-zone.min())),(2*N+8,0))
w=w.resize((w.width*2,w.height*2),Image.NEAREST); w.save('forkD_lenia_zone_ab.png')
# local mean field by quadrant to quantify regime differences
for nm,a in outs.items():
    q=[a[i*N//2:(i+1)*N//2,j*N//2:(j+1)*N//2].mean() for i in range(2) for j in range(2)]
    print(nm,'quadrant means',np.round(q,3))
