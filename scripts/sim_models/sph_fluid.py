"""Numpy model of sph-fluid: weakly compressible SPH (WCSPH, Becker & Teschner 2007) on the sim ring.

This validates the CPU spec of the solver, not the WGSL. It mirrors the two simState passes of the
graph (public/shaders/sph-fluid-{density,force}.wgsl) one formula at a time, including the spatial
hash the GPU walks: particles are scattered into a G x G grid in a shuffled order (GPU scheduling),
each cell is a linked list in reverse scatter order, and a reader visits at most VISIT_CAP particles
per cell (bind_group1.json spatialHash.visitCap). A crowded cell is truncated exactly as on the GPU,
so the neighbour histogram below is the one the shader sees.

Units: positions in px and velocities in px/frame are stored (the hash works in working-size pixels);
the solver runs in kernel units, h = 0.98 * min(cell) px, one explicit step per frame (dt = 1).
  kernels (2D, h = 1)  W = 4/pi (1 - r^2)^3   grad W = -30/pi (1 - r)^2 r_hat   lap W = 40/pi (1 - r)
  density pass         rho_i = sum_j W_ij (self included);  omega_i = sum_j V0 grad W_ij x v_ij
  force pass           p = B ((rho/rho0)^7 - 1), clamped to >= 0 (Tait, free surface), B = rho0 c^2 / 7
                       a = -sum_j (p_i/rho_i^2 + p_j/rho_j^2) grad W_ij                 pressure
                         + nu sum_j v_ij / rho_j lap W_ij                                viscosity
                         - gamma sum_j 2 rho0/(rho_i + rho_j) C(r) r_hat                  cohesion (Akinci 2013)
                         + eps_v (N x omega),  N = eta/|eta|, eta = sum_j (|w_j|-|w_i|)/rho_j grad W   vorticity
                         + walls (+ tide / pointer / obstacle on the GPU)
                       v += a + eps_x sum_j 2/(rho_i + rho_j) v_ij W_ij (XSPH), |v| <= VMAX;  x += v
The aux record of particle i is simState[2i + 1] = (-1, -1, rho, omega): the (-1, -1) sentinel keeps it
out of the hash (a parked agent), so the density pass does not move a hashed position and the planner
may keep the hash for the force pass (`keepsHash`).

Sliders (zoom_params, 0..1):  x viscosity nu = mix(0.002, 0.03), eps_x = mix(0.03, 0.15)
                              y rest density rho0 = min(mix(3.4, 6.2), 8 / A_cell)   (h^-2; ~11-19 neighbours)
                              z pointer force, w obstacle strength (GPU-only drive terms)
A_cell is the hash cell's area in h^2 (1.04 for square cells, 1.85 at 1920 x 1080). The cap keeps the expected
per-cell occupancy at rest <= 8, half the hash's visit cap of 16, so compression has room before truncation.

Mach note: one explicit step per frame caps the sound speed near c = 0.6 h / frame, with |v| <= 0.5. At rest
and in gentle flows the fluid stays within a few percent of rho0 (the WCSPH regime). An impact at relative
speed v compresses it by about v / c (the water-hammer limit), so a violent splash compresses 40-50 %: the
fluid is springy there by construction. The violent cases are checked for stability, not compression.

Run:  python3 scripts/sim_models/sph_fluid.py      (prints 100-step stats per case)
Exit status is non-zero when a case leaves its tolerance:
  rest       bulk |rho - rho0| / rho0 (mean over the interior half) < 2 %, max(rho / rho0) - 1 < 8 % after
             step 10, no particle loses a neighbour to the visit cap, none has fewer than 4 neighbours
  noise      particle-scale velocity noise loses >= 80 % of its kinetic energy in 100 steps
  gentle     a strain impulse (Mach ~0.17) stays under 10 % compression and its KE never grows
  stable     a violent swirl stays finite, |v| <= VMAX, and its KE never grows
  obstacle   a bright disc pushes out >= 50 % of the fluid that started inside it
  control    an overfilled hash (occupancy ~18 > visit cap 16) must trip the truncation check
"""
import math
import sys
import time

import numpy as np

POLY6 = 4.0 / math.pi
SPIKY = -30.0 / math.pi
VISC_LAP = 40.0 / math.pi
COH = 32.0 / math.pi
VISIT_CAP = 16
C_SOUND = 0.60        # h / frame (one explicit step per frame; see the Mach note in the docstring)
VMAX = 0.5            # h / frame
GAMMA = 0.01          # cohesion (surface tension); Laplace compression of an R = 8 h droplet ~5 %
EPS_V = 0.002         # vorticity confinement
RHO_CLAMP = 1.4       # EOS input clamp: a pathological pile-up cannot produce an unbounded kick
KAPPA = 1.0           # rho_sum / number density of the seed pattern (calibrate() measures 1.003)
RHO_LO = 3.4          # rest density range (h^-2): ~11 to ~19 neighbours in the bulk
RHO_HI = 6.2
OCC_MAX = 8.0         # rest particles per hash cell, at most (visit cap is 16)
COVERAGE = 0.30       # active particles = COVERAGE * OCC_SEED * cells (GPU: the rest are parked)
OCC_SEED = 5.0
ACTIVE_MAX = int(COVERAGE * OCC_SEED * 128 * 128)   # 24576 on the GPU's 128 x 128 hash
WALL_K = 0.2          # wall penalty (h / frame^2) at the edge, fading to 0 at WALL_R
WALL_R = 1.5          # h
WALL_BOUNCE = 0.3
OBST_PUSH = 0.25      # obstacle: luma-gradient push (h / frame^2 per unit gradient)
OBST_DRAG = 0.1       # obstacle: drag inside bright regions
OBST_PROBE = 2.0      # h, half-width of the luma gradient probe
STEPS = 100


def mix(a, b, t):
    return a + (b - a) * t


def cohesion_spline(r):
    """Akinci C(r) on h = 1: repulsive below r = 0.5, attractive out to the kernel edge."""
    a = (1.0 - r) ** 3 * r ** 3
    return COH * np.where(r > 0.5, a, 2.0 * a - 1.0 / 64.0)


class Domain:
    def __init__(self, grid=48, cell_px=8.0, cell_px_y=None):
        self.g = grid
        self.cx = cell_px
        self.cy = cell_px if cell_px_y is None else cell_px_y
        self.res = np.array([grid * self.cx, grid * self.cy])
        self.h = 0.98 * min(self.cx, self.cy)
        self.a_cell = self.cx * self.cy / (self.h * self.h)


def params(dom, visc=0.5, rest=0.5, rho0=None):
    if rho0 is None:   # neighbour-count target, capped so the rest occupancy of a (possibly wide) cell is <= OCC_MAX
        rho0 = min(mix(RHO_LO, RHO_HI, rest), OCC_MAX / dom.a_cell)
    return dict(nu=mix(0.002, 0.03, visc), eps_x=mix(0.03, 0.15, visc), rho0=rho0,
                B=rho0 * C_SOUND * C_SOUND / 7.0, occ=rho0 * dom.a_cell)


def build_hash(dom, pos, rng):
    """Shuffled scatter, reverse-order lists, VISIT_CAP visible per cell. Returns (table, cell_of, overfull)."""
    g = dom.g
    c = np.clip(np.floor(pos / dom.res * g), 0, g - 1).astype(np.int64)
    cell = c[:, 1] * g + c[:, 0]
    n = len(pos)
    rank = np.empty(n, np.int64)
    rank[rng.permutation(n)] = np.arange(n)          # scatter order (GPU scheduling)
    # atomicExchange makes the last scattered particle the head: walk each cell in descending rank.
    order = np.lexsort((-rank, cell))
    sc = cell[order]
    first = np.searchsorted(sc, sc, side='left')
    slot = np.arange(n) - first
    keep = slot < VISIT_CAP
    table = -np.ones((g * g, VISIT_CAP), np.int64)
    table[sc[keep], slot[keep]] = order[keep]
    count = np.bincount(cell, minlength=g * g)
    return table, c, count


def neighbours(dom, table, c):
    g = dom.g
    cand = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx, ny = c[:, 0] + dx, c[:, 1] + dy
            ok = (nx >= 0) & (nx < g) & (ny >= 0) & (ny < g)
            ids = table[np.clip(ny, 0, g - 1) * g + np.clip(nx, 0, g - 1)]
            cand.append(np.where(ok[:, None], ids, -1))
    return np.concatenate(cand, axis=1)          # (N, 9 * VISIT_CAP), -1 = empty


def step(dom, prm, pos, vel, rng, drive=None):
    """One frame: hash build, density pass, force pass (keepsHash: same table). Returns stats too."""
    h = dom.h
    n = len(pos)
    table, c, count = build_hash(dom, pos, rng)
    cand = neighbours(dom, table, c)
    ii, kk = np.nonzero((cand >= 0) & (cand != np.arange(n)[:, None]))
    jj = cand[ii, kk]
    d = (pos[ii] - pos[jj]) / h                          # x_i - x_j, kernel units
    r2 = np.sum(d * d, axis=1)
    m = r2 < 1.0
    ii, jj, d, r2 = ii[m], jj[m], d[m], r2[m]            # the pairs inside the kernel (visit-capped)
    r = np.sqrt(np.maximum(r2, 1e-12))
    rhat = d / r[:, None]
    vh = vel / h
    vij = vh[jj] - vh[ii]

    def ssum(x):
        if x.ndim == 1:
            return np.bincount(ii, weights=x, minlength=n)
        return np.stack([np.bincount(ii, weights=x[:, k], minlength=n) for k in range(x.shape[1])], axis=1)

    # ── density pass ──
    w = POLY6 * (1.0 - r2) ** 3
    rho = POLY6 + ssum(w)
    gradw = np.where((r > 1e-5)[:, None], SPIKY * ((1.0 - r) ** 2)[:, None] * rhat, 0.0)
    v0 = 1.0 / prm['rho0']
    omega = v0 * ssum(gradw[:, 0] * vij[:, 1] - gradw[:, 1] * vij[:, 0])

    # ── force pass ──
    ratio = np.minimum(rho / prm['rho0'], RHO_CLAMP)
    press = np.maximum(prm['B'] * (ratio ** 7 - 1.0), 0.0)
    pr = press / (rho * rho)
    a_p = -ssum((pr[ii] + pr[jj])[:, None] * gradw)
    rhoj = rho[jj]
    a_v = prm['nu'] * ssum((VISC_LAP * (1.0 - r) / rhoj)[:, None] * vij)
    kij = 2.0 * prm['rho0'] / (rho[ii] + rhoj)
    a_c = -GAMMA * ssum((kij * cohesion_spline(r))[:, None] * rhat)
    eta = ssum(((np.abs(omega[jj]) - np.abs(omega[ii])) / rhoj)[:, None] * gradw)
    en = np.linalg.norm(eta, axis=1)
    nrm = np.where(en[:, None] > 1e-6, eta / np.maximum(en, 1e-6)[:, None], 0.0)
    a_w = EPS_V * np.stack([nrm[:, 1] * omega, -nrm[:, 0] * omega], axis=1)
    xs = ssum((2.0 / (rho[ii] + rhoj) * w)[:, None] * vij)

    # Walls: a penalty inside one h of each edge (the GPU adds tide / pointer / obstacle here).
    ph = pos / h
    resh = dom.res / h
    a_wall = WALL_K * (np.maximum(1.0 - ph / WALL_R, 0.0) ** 2 - np.maximum(1.0 - (resh - ph) / WALL_R, 0.0) ** 2)
    a = a_p + a_v + a_c + a_w + a_wall
    if drive is not None:
        a = a + drive(pos / h, vh)

    vh = vh + a + prm['eps_x'] * xs
    sp = np.linalg.norm(vh, axis=1)
    vh = np.where(sp[:, None] > VMAX, vh / np.maximum(sp, 1e-9)[:, None] * VMAX, vh)
    pos = pos + vh * h
    lo, hi = 0.5, dom.res - 0.5
    clamped = (pos < lo) | (pos > hi)
    pos = np.clip(pos, lo, hi)
    vh = np.where(clamped, -WALL_BOUNCE * vh, vh)     # inelastic bounce, not a dead stop (no pile-up)

    nbr = np.bincount(ii, minlength=n)
    # A particle lost neighbours to the cap iff one of its 3x3 cells holds more than VISIT_CAP.
    g = dom.g
    over = np.zeros(n, bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx, ny = c[:, 0] + dx, c[:, 1] + dy
            ok = (nx >= 0) & (nx < g) & (ny >= 0) & (ny < g)
            over |= ok & (count[np.clip(ny, 0, g - 1) * g + np.clip(nx, 0, g - 1)] > VISIT_CAP)
    return pos, vh * h, dict(rho=rho, nbr=nbr, occ_max=int(count.max()), truncated=int(over.sum()), omega=omega)


def sunflower(center, radius, m, phase=0.0):
    """Vogel spiral: m quasi-uniform points in a disc (what the GPU seeds on frame 0)."""
    k = np.arange(m) + 0.5
    rr = radius * np.sqrt(k / m)
    th = k * 2.39996322972865332 + phase
    return np.stack([center[0] + rr * np.cos(th), center[1] + rr * np.sin(th)], axis=1)


def seed_droplets(dom, prm, n_active):
    """Droplet layout of the GPU seed: 3 x 1 when wide, 1 x 3 when tall, else 2 x 2, sized for rest."""
    w, hgt = dom.res
    aspect = w / hgt
    cols, rows = (3, 1) if aspect >= 1.3 else ((1, 3) if aspect <= 0.77 else (2, 2))
    k = cols * rows
    m = -(-n_active // k)
    n_px = prm['rho0'] / KAPPA / (dom.h * dom.h)      # number density, px^-2
    radius = math.sqrt(m / (math.pi * n_px))
    pts = []
    for q in range(k):
        cx = (q % cols + 0.5) / cols * w
        cy = (q // cols + 0.5) / rows * hgt
        pts.append(sunflower((cx, cy), radius, m, phase=q))
    p = np.concatenate(pts)[:n_active]
    return p, radius


def calibrate():
    """rho_sum / number density for a sunflower disc at the default rest density: what KAPPA should be."""
    dom = Domain()
    prm = params(dom)
    n_px = prm['rho0'] / (dom.h * dom.h)
    m = 3000
    radius = math.sqrt(m / (math.pi * n_px))
    pos = sunflower(dom.res / 2, radius, m)
    vel = np.zeros_like(pos)
    _, _, st = step(dom, prm, pos, vel, np.random.default_rng(0))
    core = np.linalg.norm(pos - dom.res / 2, axis=1) < 0.5 * radius
    return float(st['rho'][core].mean() / prm['rho0'])


def run_case(visc=0.5, rest=0.5, steps=STEPS, start='rest', amp=0.0, seed=3, dom=None, drive=None,
             single=False, inside=None, rho0=None):
    """start: 'rest' (seeded at rest density), 'noise' (particle-scale white noise), 'squeeze' (a strain
    impulse: zero net linear and angular momentum), 'swirl' (a spin plus a shear wave). amp in h / frame."""
    dom = dom or Domain()
    prm = params(dom, visc, rest, rho0)
    rng = np.random.default_rng(seed)
    n_active = int(round(COVERAGE * OCC_SEED * dom.g * dom.g))
    if single:
        n_px = prm['rho0'] / KAPPA / (dom.h * dom.h)
        m = n_active // 3
        radius = math.sqrt(m / (math.pi * n_px))
        pos = sunflower(dom.res / 2, radius, m)
    else:
        pos, radius = seed_droplets(dom, prm, n_active)
    c = (pos - dom.res / 2) / (radius + 1e-9)
    if start == 'noise':
        vel = amp * dom.h * rng.standard_normal(pos.shape)
    elif start == 'squeeze':
        vel = amp * dom.h * np.stack([c[:, 0], -c[:, 1]], axis=1)
    elif start == 'swirl':
        vel = amp * dom.h * np.stack([-c[:, 1] + 0.5 * np.sin(2.0 * math.pi * c[:, 1]), c[:, 0]], axis=1)
    else:
        vel = np.zeros_like(pos)
    sp0 = np.linalg.norm(vel, axis=1) / dom.h
    ke = [0.5 * float(np.sum(sp0 * sp0))]
    comp, bulk, vmax = [], [], 0.0
    hist = None
    trunc = 0
    occ_max = 0
    lonely = 0
    in0 = int(inside(pos).sum()) if inside else 0
    for _ in range(steps):
        pos, vel, st = step(dom, prm, pos, vel, rng, drive)
        sp = np.linalg.norm(vel, axis=1) / dom.h
        ke.append(0.5 * float(np.sum(sp * sp)))
        vmax = max(vmax, float(sp.max()))
        ratio = st['rho'] / prm['rho0']
        interior = st['nbr'] >= np.quantile(st['nbr'], 0.5)
        bulk.append(float(np.mean(np.abs(ratio[interior] - 1.0))))
        comp.append(float(ratio.max() - 1.0))
        trunc = max(trunc, st['truncated'])
        occ_max = max(occ_max, st['occ_max'])
        hist = np.bincount(st['nbr'], minlength=40)
        lonely = int(hist[:4].sum())
    finite = bool(np.isfinite(pos).all() and np.isfinite(vel).all())
    return dict(ke=ke, comp=comp, bulk=bulk, vmax=vmax, hist=hist, trunc=trunc, occ_max=occ_max, lonely=lonely,
                finite=finite, n=len(pos), rho0=prm['rho0'], in0=in0, in1=int(inside(pos).sum()) if inside else 0)


def obstacle(dom):
    """A bright disc (radius 6 h) in the middle of the image: luma gradient push + drag, as on the GPU."""
    centre = dom.res / dom.h / 2

    def luma(ph):
        return 1.0 - np.clip((np.linalg.norm(ph - centre, axis=1) - 6.0) / 2.0, 0.0, 1.0)

    def drive(ph, vh):
        e = OBST_PROBE
        grad = np.stack([luma(ph + [e, 0]) - luma(ph - [e, 0]), luma(ph + [0, e]) - luma(ph - [0, e])], axis=1)
        return -OBST_PUSH * grad / (2.0 * e) - OBST_DRAG * luma(ph)[:, None] * vh

    return drive, lambda pos: np.linalg.norm(pos / dom.h - centre, axis=1) < 6.0


# (name, run_case kwargs, checks). Checks: 'rest' bulk < 2 %, compression < 8 %, no cap truncation, no
# particle under 4 neighbours; 'noise' KE(100) <= 20 % of KE(0); 'gentle' compression < 10 % and no KE
# growth; 'stable' finite, |v| <= VMAX, KE(100) <= 1.05 KE(0); 'obstacle' the bright disc loses >= 50 %
# of the fluid inside it; 'control' must trip the visit-cap check (proves the histogram can see it).
CASES = [
    ('rest default', {}, 'rest'),
    ('rest visc=0', {'visc': 0.0}, 'rest'),
    ('rest visc=1', {'visc': 1.0}, 'rest'),
    ('rest dens=0', {'rest': 0.0}, 'rest'),
    ('rest dens=1', {'rest': 1.0}, 'rest'),
    ('rest 16:9 cells', {'dom': 'wide'}, 'rest'),
    ('noise 0.05', {'start': 'noise', 'amp': 0.05}, 'noise'),
    ('squeeze 0.1', {'start': 'squeeze', 'amp': 0.1, 'single': True}, 'gentle'),
    ('swirl 0.25', {'start': 'swirl', 'amp': 0.25, 'single': True}, 'stable'),
    ('swirl visc=0', {'start': 'swirl', 'amp': 0.25, 'single': True, 'visc': 0.0}, 'stable'),
    ('obstacle', {'single': True, 'drive': 'obstacle'}, 'obstacle'),
    ('control occ ~18', {'rho0': 17.0}, 'control'),
]


def check(kind, r):
    problems = []
    if not r['finite'] or r['vmax'] > VMAX + 1e-6:
        problems.append('blow-up')
    if kind in ('rest', 'control'):
        if r['bulk'][-1] >= 0.02:
            problems.append('bulk>=2%')
        if max(r['comp'][10:]) >= 0.08:
            problems.append('compression>=8%')
        if r['trunc'] > 0:
            problems.append('visit-cap truncation')
        if r['lonely'] > 0:
            problems.append('%d particles under 4 neighbours' % r['lonely'])
    if kind == 'noise' and r['ke'][-1] > 0.2 * r['ke'][0]:
        problems.append('noise not damped')
    if kind == 'gentle':
        if max(r['comp'][10:]) >= 0.10:
            problems.append('compression>=10%')
        if r['ke'][-1] > max(r['ke'][:2]):
            problems.append('KE grew')
    if kind == 'stable' and r['ke'][-1] > 1.05 * r['ke'][0]:
        problems.append('KE grew')
    if kind == 'obstacle' and r['in1'] > 0.5 * r['in0']:
        problems.append('obstacle not displacing (%d -> %d inside)' % (r['in0'], r['in1']))
    return problems


def main():
    kappa = calibrate()
    print('calibration: sunflower rho_sum / number density = %.3f (KAPPA = %.3f)' % (kappa, KAPPA))
    print('100-step stats; bulk = mean |rho - rho0| / rho0 over the interior half, comp = max(rho / rho0) - 1 '
          'after step 10, KE in (h / frame)^2 units')
    bad = []
    print('%-16s %5s %5s %8s %7s %8s %8s %6s %6s %5s  %s' % (
        'case', 'N', 'rho0', 'bulk@100', 'comp', 'KE@0', 'KE@100', 'vmax', 'occMax', 'trunc', 'verdict'))
    for name, kw, kind in CASES:
        t0 = time.time()
        kw = dict(kw)
        if kw.get('dom') == 'wide':
            kw['dom'] = Domain(grid=48, cell_px=15.0, cell_px_y=8.44)   # 1920 x 1080 cells
        if kw.get('drive') == 'obstacle':
            kw['dom'] = Domain()
            kw['drive'], kw['inside'] = obstacle(kw['dom'])
        r = run_case(**kw)
        problems = check(kind, r)
        if kind == 'control':
            ok = any('truncation' in p for p in problems)
            verdict = 'ok (rejected: %s)' % ','.join(problems) if ok else 'FAIL control not rejected'
        else:
            ok = not problems
            verdict = 'ok' if ok else 'FAIL ' + ','.join(problems)
        if not ok:
            bad.append(name)
        print('%-16s %5d %5.2f %8.4f %7.4f %8.3f %8.3f %6.3f %6d %5d  %s  (%.1fs)' % (
            name, r['n'], r['rho0'], r['bulk'][-1], max(r['comp'][10:]), r['ke'][0], r['ke'][-1], r['vmax'],
            r['occ_max'], r['trunc'], verdict, time.time() - t0))
        nz = np.nonzero(r['hist'])[0]
        print('    neighbours (count:particles) ' + ' '.join('%d:%d' % (k, r['hist'][k]) for k in nz))
    if bad:
        print('sph_fluid: %d case(s) outside tolerance: %s' % (len(bad), ', '.join(bad)))
        return 1
    print('sph_fluid: all cases inside tolerance (CPU spec only; the WGSL is checked on SwiftShader)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
