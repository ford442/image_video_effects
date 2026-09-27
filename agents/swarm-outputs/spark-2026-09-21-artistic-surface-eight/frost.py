import numpy as np
H,W=90,160; rng=np.random.default_rng(1)
fr=np.zeros((H,W)); wa=np.zeros((H,W))
yy,xx=np.mgrid[0:H,0:W]; u=(xx+.5)/W; v=(yy+.5)/H
crystal=rng.random((H,W))*0.6+0.2  # stand-in for facet/branch mix
edge=np.minimum(np.minimum(u,1-u),np.minimum(v,1-v))
seed=np.clip((0.03-(edge+rng.random((H,W))*0.025))/0.03,0,1); seed=seed*seed*(3-2*seed)
freeze=0.002+0.5*0.04; mx,my=0.5,0.5; heatR=0.04+0.5*0.18
def sh(a,dy,dx): return np.pad(a,1,mode='edge')[1+dy:1+dy+H,1+dx:1+dx+W]
for f in range(900):
    N,S,E,Wt=sh(fr,1,0),sh(fr,-1,0),sh(fr,0,1),sh(fr,0,-1)
    above=sh(wa,-1,0)
    water=np.maximum(wa*0.94,above*0.992)
    frontier=np.maximum(np.maximum(N,S),np.maximum(E,Wt))
    grows=rng.random((H,W))<(0.15+crystal*0.7)*(1-np.clip(water*4,0,1))
    new=np.maximum(seed*0.3,np.where((frontier>0.02)&grows,frontier*0.5,0))
    f0=np.where(fr<0.005,new,fr)
    alive=f0>=0.005
    f1=np.clip(f0+freeze*(1-np.clip(water*3,0,0.9)),0,1)
    md=np.hypot(u-mx,v-my); t=np.clip((md-heatR)/(heatR*0.2-heatR),0,1); heat=t*t*(3-2*t)
    lap=(N+S+E+Wt)*0.25-f1
    f2=np.clip(f1*(1-heat*0.9)-lap*heat*2,0,1)
    water=np.where(alive,np.clip(water+np.maximum(f1-f2,0)*1.6,0,1),water)
    fr=np.where(alive,f2,0); wa=water
    if f in (60,300,899):
        print(f, 'frost cover %.2f'%(fr>0.3).mean(), 'water>0.1 %.3f'%(wa>0.1).mean(),
              'water below cursor col %.2f'%wa[60:,75:85].mean())
