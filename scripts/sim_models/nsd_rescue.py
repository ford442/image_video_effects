"""Numpy port of the rescued navier-stokes-dye.wgsl rule (keep in sync with the WGSL).

Run: python3 scripts/sim_models/nsd_rescue.py  (~1 min). Prints max/mean speed (px/step), dye mean,
dye coverage and mean |curl| at steps 60/300/600 with the cursor idle at the centre. Stable = bounded
speed (< VMAX), dye spreads, curl > 0.
"""
import numpy as np, sys
N=128
yy,xx=np.mgrid[0:N,0:N].astype(float)
def R(Z,dx,dy): return np.roll(np.roll(Z,-dy,0),-dx,1)   # Z at (x+dx, y+dy), torus
def bilerp(Z,sx,sy):
    sx=np.mod(sx,N); sy=np.mod(sy,N); x0=np.floor(sx).astype(int); y0=np.floor(sy).astype(int)
    fx=sx-x0; fy=sy-y0; x1=(x0+1)%N; y1=(y0+1)%N; x0%=N; y0%=N
    return Z[y0,x0]*(1-fx)*(1-fy)+Z[y0,x1]*fx*(1-fy)+Z[y1,x0]*(1-fx)*fy+Z[y1,x1]*fx*fy
def curl(vx,vy): return 0.5*((R(vy,1,0)-R(vy,-1,0))-(R(vx,0,1)-R(vx,0,-1)))
def div(vx,vy): return 0.5*((R(vx,1,0)-R(vx,-1,0))+(R(vy,0,1)-R(vy,0,-1)))
VMAX=6.0
def run(p,steps=600,mouse=(0.5,0.5),held=0.0):
    visc,turb,rip,cs=p
    damp=0.002+0.02*visc; vort=0.05+0.3*turb; push=0.3+2.0*rip
    vx=np.zeros((N,N)); vy=np.zeros((N,N)); dye=np.zeros((N,N)); hue=np.zeros((N,N))
    out=[]
    for t in range(steps):
        time=t/60
        # advect everything from p - v
        sx=xx-vx; sy=yy-vy
        avx,avy,ad,ah=(bilerp(Z,sx,sy) for Z in (vx,vy,dye,hue))
        # mouse source: radial push, always on (weak) and strong when held
        mxp,myp=mouse[0]*N,mouse[1]*N
        dxm=xx-mxp; dym=yy-myp; d2=(dxm**2+dym**2)/N**2; dm=np.sqrt(dxm**2+dym**2)+1e-4
        src=np.exp(-d2*900)*(0.08+held*0.25)
        # Idle: a jet whose heading meanders, so the source sheds curling plumes.
        # Held: HEAD's radial push away from the cursor.
        th=time*0.6+1.5*np.sin(time*0.23)
        jet=np.exp(-d2*900)*0.12*push
        fx=np.cos(th)*jet+dxm/dm*np.exp(-d2*900)*held*0.25*push
        fy=np.sin(th)*jet+dym/dm*np.exp(-d2*900)*held*0.25*push
        # vorticity confinement (from previous field)
        w=curl(vx,vy); aw=np.abs(w)
        gx=0.5*(R(aw,1,0)-R(aw,-1,0)); gy=0.5*(R(aw,0,1)-R(aw,0,-1)); gl=np.hypot(gx,gy)+1e-5
        cfx=gy/gl*w*vort; cfy=-gx/gl*w*vort
        # divergence damping: one gradient step on div (cheap stand-in for a pressure solve)
        dv=div(vx,vy)
        gdx=0.5*(R(dv,1,0)-R(dv,-1,0)); gdy=0.5*(R(dv,0,1)-R(dv,0,-1))
        # HEAD's filament runner / vortex ribbon: small travelling gains on speed
        ang=np.arctan2(avy,avx)
        fil=np.maximum(0,np.sin(ang*4-time*16))**12; rib=np.maximum(0,np.sin(np.abs(w)*12-time*10))**14
        gain=1+fil*turb*0.03+rib*turb*0.02
        nvx=(avx*gain+fx+cfx+0.25*gdx)*(1-damp); nvy=(avy*gain+fy+cfy+0.25*gdy)*(1-damp)
        sp=np.hypot(nvx,nvy); sc=np.minimum(1,VMAX/np.maximum(sp,1e-6)); nvx*=sc; nvy*=sc
        inj=np.exp(-d2*900)*(0.08+held*0.3)
        nd=np.clip(ad*(0.998-0.004*visc)+inj,0,1)
        nh=np.where(inj>1e-3, ad*ah/(ad+inj+1e-6)+inj*(time*0.05+cs)/(ad+inj+1e-6), ah)
        vx,vy,dye,hue=nvx,nvy,nd,nh
        if t in (59,299,599): out.append((np.hypot(vx,vy).max(),np.hypot(vx,vy).mean(),dye.mean(),(dye>0.1).mean(),np.abs(curl(vx,vy)).mean()))
    if len(sys.argv)>1: np.save('nsd_%s.npy'%'_'.join(map(str,p)),np.stack([vx,vy,dye,hue]))
    return out
for p in [(0.5,0.4,0.5,0.3),(0,0.4,0.5,0.3),(1,0.4,0.5,0.3),(0.5,0,0.5,0.3),(0.5,1,0.5,0.3),(0.5,0.4,0,0.3),(0.5,0.4,1,0.3),(0,1,1,0.3)]:
    print(p,' | '.join('vmax %.2f vmean %.3f dye %.3f cover %.2f curl %.3f'%o for o in run(p)),flush=True)
