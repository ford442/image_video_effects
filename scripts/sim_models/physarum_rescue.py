"""Numpy port of the rescued physarum.wgsl rule (Eulerian agents, after gen-wasm-hls-physarum-swarm).

Sliders (WGSL mix ranges): x agent radius -> trail blur (vein width), y deposit opacity -> deposit,
z sense distance 3..10 px, w trail decay 0.95..0.995. Sensor angle fixed at 0.68 rad. Food = image red.

State per pixel (A / C): (trail, mx, my, hue).  |m| = agent mass density, m/|m| = heading.
Per step (mirrors the WGSL line for line):
  1. u   = speed * m / max(|m|, DIRG)                       (local agent velocity, px/step)
  2. gather at s = p - u (semi-Lagrangian, the same 4 loads a bilinear would use):
       mass  = bilinear(|m|)                                  (scalar average -> mass never cancels)
       heading = direction of the corner with the largest weight*|m|  (winner-take-all -> opposing streams do not annihilate;
                 a plain vector bilerp of m was tried first: it collapses into isolated hubs, giant-component share 0.17)
  3. J   = det(I - grad u)  (central differences of u)       (density Jacobian: converging flow piles up mass)
  4. heading = atan2(m_a), 3-sensor steer (trail + food*2.5), wander, mouse pull
  5. mass = clamp(max(|m_a|, FLOOR) * (1 + JC*(J-1)), FLOOR, CAP)   (floor = no annihilation, cap = no blow-up)
  6. trail = blur3x3(trail)*decay + K*dep*mass*(1-trail)*(1-decay)/0.04125      (deposit, soft-saturating)
Run:  python3 scripts/sim_models/physarum_rescue.py         (9 slider cases x 900 steps, N=128, ~20 s on 8 cores)
      python3 scripts/sim_models/physarum_rescue.py extras  (audio / mouse / food stress cases)
Network = giant component of the brightest quarter ~1.0 with cv > 0.15; collapse = few isolated hubs.
"""
import numpy as np, sys, time
from multiprocessing import Pool
N = 128
FLOOR, CAP, JC, JMIN, JMAX, DIRG = 0.07, 0.6, 0.6, 0.5, 2.0, 0.05
RHO0, K, WANDER, DECN = 0.15, 0.05, 0.15, 0.0275   # DECN = 1 - mix(0.95,0.995,0.5)  (default decay)
SPEED0, TURN0 = 1.5, 0.5

def bilerp(F, sx, sy):
    sx = np.mod(sx, N); sy = np.mod(sy, N)
    x0 = np.floor(sx).astype(int); y0 = np.floor(sy).astype(int)
    fx = sx - x0; fy = sy - y0
    x1 = (x0 + 1) % N; y1 = (y0 + 1) % N; x0 %= N; y0 %= N
    return F[y0, x0]*(1-fx)*(1-fy) + F[y0, x1]*fx*(1-fy) + F[y1, x0]*(1-fx)*fy + F[y1, x1]*fx*fy

def blur3(T):
    s = 0
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            s = s + np.roll(np.roll(T, i, 0), j, 1)
    return s / 9

def run(x, y, z, w, steps=900, seed=1, food=None, audio=(0, 0, 0), mouse=None, sample=()):
    sa = 0.68; blurmix = 0.25 + 0.75*x; dep = 0.3 + 2.0*y; sd = 3 + 7*z; dec = 0.95 + 0.045*w   # WGSL mix() ranges
    bass, mid, treble = audio
    turn = TURN0 + bass*3.0 + mid*1.5; speed = SPEED0 + treble*1.0; dep = dep*(1 + bass*2.0)
    dturn = min(turn*sa, 0.9)          # WGSL clamps the audio-boosted turn to 0.9 rad/step
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    T = np.zeros((N, N)); ang = rng.random((N, N))*6.28318
    mass = RHO0*(0.5 + rng.random((N, N)))                 # seed path (first frame, C == 0)
    mx = mass*np.cos(ang); my = mass*np.sin(ang)
    m0 = mass.sum(); F = np.zeros((N, N)) if food is None else food
    snaps = {}; Tprev = T; Mprev = (mx, my)
    for t in range(steps):
        m = np.hypot(mx, my); den = np.maximum(m, DIRG)
        ux = speed*mx/den; uy = speed*my/den
        sx = np.mod(xx-ux, N); sy = np.mod(yy-uy, N)
        x0 = np.floor(sx).astype(int); y0 = np.floor(sy).astype(int); fx = sx-x0; fy = sy-y0
        x1 = (x0+1) % N; y1 = (y0+1) % N; x0 %= N; y0 %= N
        ma = 0; bx = np.zeros((N, N)); by = np.zeros((N, N)); bs = np.full((N, N), -1.0)
        for yi, xi, wt in ((y0, x0, (1-fx)*(1-fy)), (y0, x1, fx*(1-fy)), (y1, x0, (1-fx)*fy), (y1, x1, fx*fy)):
            mm = m[yi, xi]; ma = ma + wt*mm; sc = wt*mm; upd = sc > bs
            bs = np.where(upd, sc, bs); bx = np.where(upd, mx[yi, xi], bx); by = np.where(upd, my[yi, xi], by)
        dux_dx = 0.5*(np.roll(ux, -1, 1) - np.roll(ux, 1, 1)); dux_dy = 0.5*(np.roll(ux, -1, 0) - np.roll(ux, 1, 0))
        duy_dx = 0.5*(np.roll(uy, -1, 1) - np.roll(uy, 1, 1)); duy_dy = 0.5*(np.roll(uy, -1, 0) - np.roll(uy, 1, 0))
        J = np.clip((1-dux_dx)*(1-duy_dy) - dux_dy*duy_dx, JMIN, JMAX)
        a = np.arctan2(by, bx)
        a = np.where(ma < 1e-6, rng.random((N, N))*6.28318, a)
        def sense(aa):
            px = np.floor(xx + np.cos(aa)*sd).astype(int) % N; py = np.floor(yy + np.sin(aa)*sd).astype(int) % N
            return T[py, px] + F[py, px]*1.5
        wF, wL, wR = sense(a), sense(a+sa), sense(a-sa)
        rnd = rng.random((N, N)) > 0.5
        da = np.where((wF > wL) & (wF > wR), 0.0,
             np.where((wF < wL) & (wF < wR), np.where(rnd, 1, -1)*dturn, np.where(wL > wR, dturn, -dturn)))
        a = a + da + WANDER*(rng.random((N, N)) - 0.5)
        if mouse is not None:
            mxp, myp, rad = mouse
            dx = mxp - xx; dy = myp - yy; d = np.hypot(dx, dy)
            des = np.arctan2(dy, dx); blend = np.clip(1 - d/rad, 0, 1)*(d < rad)*0.3
            dl = (des - a + np.pi) % (2*np.pi) - np.pi
            a = a + dl*blend
        mnew = np.clip(np.maximum(ma, FLOOR)*(1 + JC*(J-1)), FLOOR, CAP)
        Mprev = (mx, my)
        mx = mnew*np.cos(a); my = mnew*np.sin(a)
        Tprev = T
        Tn = (T + (blur3(T) - T)*blurmix)*dec
        T = Tn + K*dep*mnew*(1-Tn)*((1-dec)/DECN)
        if t+1 in sample: snaps[t+1] = T.copy()
    return dict(T=T, Tprev=Tprev, mx=mx, my=my, Mprev=Mprev, mass=mnew, m0=m0, snaps=snaps)

def label(mask):
    lab = np.zeros(mask.shape, int); cur = 0; sizes = []
    for i, j in zip(*np.nonzero(mask)):
        if lab[i, j]: continue
        cur += 1; st = [(i, j)]; lab[i, j] = cur; c = 0
        while st:
            a, b = st.pop(); c += 1
            for da in (-1, 0, 1):
                for db in (-1, 0, 1):
                    p, q = (a+da) % N, (b+db) % N
                    if mask[p, q] and not lab[p, q]: lab[p, q] = cur; st.append((p, q))
        sizes.append(c)
    return sorted(sizes, reverse=True)

def metrics(r):
    T = r['T']; s = r['snaps']
    mask = T > np.quantile(T, 0.75); sz = label(mask)   # vein mask = brightest quarter
    hd = np.abs(np.arctan2(r['my'], r['mx']) - np.arctan2(r['Mprev'][1], r['Mprev'][0])); hd = np.minimum(hd, 2*np.pi-hd)
    var = {t: float(v.var()) for t, v in s.items()}
    return dict(mean=T.mean(), std=T.std(), cv=T.std()/T.mean(), sat=(T > 0.95).mean(), mass=r['mass'].sum()/r['m0'],
                var_early=var.get(25, np.nan), var_mid=var.get(300, np.nan), var_end=T.var(),
                dTrel=np.abs(T-r['Tprev']).mean()/T.std(), dHead=hd.mean(), 
                ncomp=len(sz), giant=sz[0]/max(mask.sum(), 1))

def food_blobs():
    rr = np.random.default_rng(5); f = rr.random((N, N))
    for _ in range(6): f = blur3(f)
    f = (f - f.min())/(f.max() - f.min()); return np.clip((f - 0.5)*3, 0, 1)

CASES = [('default', (.5, .5, .5, .5))]
for i, n in enumerate(['AgentRadius', 'Deposit', 'SenseDist', 'TrailDecay']):
    for v in (0, 1):
        p = [.5, .5, .5, .5]; p[i] = v; CASES.append((f'{n}={v}', tuple(p)))
EXTRAS = [('audio b.5 m.5 t.5', dict(audio=(.5, .5, .5))), ('audio b1 m1 t1', dict(audio=(1, 1, 1))),
          ('mouse r=40', dict(mouse=(64, 64, 40))), ('food blobs', dict(food=food_blobs()))]

FOOD = None
def job(a):
    name, q, kw = a; t0 = time.time()
    r = run(*q, sample=(25, 300), **kw); return name, metrics(r), time.time()-t0, r['T']

if __name__ == '__main__':
    FOOD = 0.5 + 0.3*np.sin(np.mgrid[0:N, 0:N][1]/9.0)*np.cos(np.mgrid[0:N, 0:N][0]/13.0)   # stand-in image red channel
    jobs = [(n, q, {'food': FOOD}) for n, q in CASES] if 'extras' not in sys.argv else [(n, (.5, .5, .5, .5), kw) for n, kw in EXTRAS]
    with Pool(8) as p: res = p.map(job, jobs)
    print('%-18s %6s %6s %5s %5s %6s %8s %8s %8s %6s %6s %5s %6s' % ('case', 'mean', 'std', 'cv', 'sat', 'mass', 'var@25', 'var@300', 'var@1500', 'dT/std', 'dHead', 'ncomp', 'giant'))
    for name, m, dt, T in res:
        print('%-18s %6.3f %6.3f %5.2f %5.3f %6.2f %8.5f %8.5f %8.5f %6.3f %6.3f %5d %6.2f  (%.0fs)' % (name, m['mean'], m['std'], m['cv'], m['sat'], m['mass'], m['var_early'], m['var_mid'], m['var_end'], m['dTrel'], m['dHead'], m['ncomp'], m['giant'], dt))
    if '--png' in sys.argv:
        from PIL import Image
        ims = [(np.clip((T-T.min())/(T.max()-T.min()+1e-9), 0, 1)*255).astype(np.uint8) for _, _, _, T in res]
        while len(ims) % 3: ims.append(np.zeros_like(ims[0]))
        Image.fromarray(np.vstack([np.hstack(ims[i:i+3]) for i in range(0, len(ims), 3)])).save('physarum_final.png')
