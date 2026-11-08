"""Numpy model of physarum-agents: Jones (2010) Lagrangian physarum on the sim ring.

This validates the CPU spec of the rule, not the WGSL. It mirrors the three graph nodes line for
line (public/shaders/physarum-agents-{diffuse,step,render}.wgsl; render changes no state):

  diffuse  T  = blur3x3(T_prev) * keep                       (dataC -> dataA, every texel)
  step     per agent (simState[i] = (x, y, heading, spare)):
             sense   F, L, R = T + FOOD_W * food at  p + SO * dir(h), dir(h +- SA)   (nearest texel)
             steer   F > L and F > R: keep;  F < L and F < R: +-RA at random;  else toward the larger
             wander  h += WANDER * (u - 0.5)
             move    p += SS * dir(h), wrapped onto the torus
             deposit A[texel(p)] = C[texel(p)] + dep          (C is the diffused field, A its copy)

The deposit is the one subtle part. Storage textures have no atomics and WGSL has no f32 atomics,
so agents that land on the same texel race, and the last writer wins. Every agent on a texel writes
the same value (C(texel) + dep), so the race has a single, deterministic result: "at most one deposit
per texel per frame". The model mirrors that by de-duplicating texel indices before depositing;
a plain np.add.at would give a busy texel N deposits and disagree with the GPU at high density.

Sliders (WGSL mix ranges, all zoom_params 0..1):
  x sense angle   SA = mix(0.25, 1.00) rad; turn RA = 1.5 * SA (RA > SA: Jones' reticulated regime)
  y sense dist    SO = mix(3, 18) * s px
  z move speed    SS = mix(0.5, 2.5) * s px / frame
  w persistence   keep = mix(0.80, 0.985); dep = DEP0 * (1 - keep) / (1 - 0.8925)   (steady trail scale ~ const)
s is the scale that keeps agents per s^2 equal to this model's 0.25: s = clamp(sqrt(0.25 * W*H / agents), 1, 3).
The model runs at s = 1 (N = 128, 4096 agents); the "scale" case runs s = 2 (N = 256, 16384 agents).

Run:  python3 scripts/sim_models/physarum_agents.py          (slider sweep + extras, prints a table)
Exit status is non-zero when any case leaves its tolerance:
  network:  giant-component share of the brightest quarter >= 0.80 and trail cv > 0.15
  collapse: fewer than 3 % of texels above half the max trail (a few isolated hubs) fails
  dedup:    no texel gains more than one deposit in a step ("shared" = texels with 2+ agents last step,
            i.e. where a non-deduplicated model would disagree with the GPU)
  control:  the same rule with steering off (a random walk) must FAIL the network check
"""
import sys
import time

import numpy as np

TAU = 6.28318530718
FOOD_W = 0.6        # food (image red) weight in the sensor sum
WANDER = 0.12       # rad of random wander per step
DEP0 = 0.4          # deposit at the default persistence (keep = 0.8925)
TRAIL_CAP = 8.0     # the WGSL clamps the trail so a hub cannot run away
STEPS = 500


def mix(a, b, t):
    return a + (b - a) * t


def params(x, y, z, w, s=1.0, bass=0.0):
    sa = mix(0.25, 1.00, x)
    keep = mix(0.80, 0.985, w)
    dep = DEP0 * (1.0 - keep) / (1.0 - mix(0.80, 0.985, 0.5)) * (1.0 + 1.5 * bass)
    return dict(sa=sa, ra=1.5 * sa, so=mix(3.0, 18.0, y) * s, ss=mix(0.5, 2.5, z) * s * (1.0 + 0.4 * bass),
                keep=keep, dep=dep)


def blur3(t):
    acc = np.zeros_like(t)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            acc += np.roll(np.roll(t, dy, 0), dx, 1)
    return acc / 9.0


def sense(field, food, x, y, h, dist, n):
    sx = np.floor(np.mod(x + np.cos(h) * dist, n)).astype(np.int64)
    sy = np.floor(np.mod(y + np.sin(h) * dist, n)).astype(np.int64)
    return field[sy, sx] + FOOD_W * food[sy, sx]


def run(slider=(0.5, 0.5, 0.5, 0.5), n=128, agents=4096, steps=STEPS, seed=1, food=None, bass=0.0,
        mouse=None, s=1.0, steer=True):
    p = params(*slider, s=s, bass=bass)
    rng = np.random.default_rng(seed)
    food = np.zeros((n, n)) if food is None else food
    if mouse is not None:   # held pointer: an attractant bump the sensors see (WGSL zoom_config.yz, .w > 0.5)
        mx, my, rad = mouse
        yy, xx = np.mgrid[0:n, 0:n].astype(float)
        food = food + 1.5 * np.exp(-((xx - mx) ** 2 + (yy - my) ** 2) / (rad * rad))
    x = rng.random(agents) * n
    y = rng.random(agents) * n
    h = rng.random(agents) * TAU
    T = np.zeros((n, n))
    max_hits = 0
    shared = 0
    for _ in range(steps):
        C = np.minimum(blur3(T) * p['keep'], TRAIL_CAP)        # diffuse -> dataA, copied to dataC
        f = sense(C, food, x, y, h, p['so'], n)
        l = sense(C, food, x, y, h + p['sa'], p['so'], n)
        r = sense(C, food, x, y, h - p['sa'], p['so'], n)
        coin = np.where(rng.random(agents) < 0.5, 1.0, -1.0)
        turn = np.where((f > l) & (f > r), 0.0,
               np.where((f < l) & (f < r), coin * p['ra'],
               np.where(l > r, p['ra'], -p['ra'])))
        if not steer:   # negative control: a pure random walk must not pass as a network
            turn = coin * p['ra'] * (rng.random(agents) < 0.5)
        h = np.mod(h + turn + WANDER * (rng.random(agents) - 0.5), TAU)
        x = np.mod(x + np.cos(h) * p['ss'], n)
        y = np.mod(y + np.sin(h) * p['ss'], n)
        idx = np.floor(y).astype(np.int64) * n + np.floor(x).astype(np.int64)
        uniq, hits = np.unique(idx, return_counts=True)        # last-writer-wins == one deposit per texel
        shared = int((hits > 1).sum())                         # texels np.add.at would have over-deposited
        A = C.copy().ravel()
        A[uniq] = np.minimum(C.ravel()[uniq] + p['dep'], TRAIL_CAP)
        max_hits = max(max_hits, int((A - C.ravel() > p['dep'] * 1.0001).sum()))
        T = A.reshape(n, n)
    return T, max_hits, shared


def label(mask):
    n = mask.shape[0]
    lab = np.zeros(mask.shape, np.int64)
    sizes = []
    cur = 0
    for i, j in zip(*np.nonzero(mask)):
        if lab[i, j]:
            continue
        cur += 1
        stack = [(i, j)]
        lab[i, j] = cur
        count = 0
        while stack:
            a, b = stack.pop()
            count += 1
            for da in (-1, 0, 1):
                for db in (-1, 0, 1):
                    pa, pb = (a + da) % n, (b + db) % n
                    if mask[pa, pb] and not lab[pa, pb]:
                        lab[pa, pb] = cur
                        stack.append((pa, pb))
        sizes.append(count)
    return sorted(sizes, reverse=True)


def metrics(T):
    mask = T > np.quantile(T, 0.75)
    sizes = label(mask)
    return dict(mean=float(T.mean()), cv=float(T.std() / max(T.mean(), 1e-9)),
                giant=sizes[0] / max(int(mask.sum()), 1) if sizes else 0.0, ncomp=len(sizes),
                hot=float((T > 0.5 * T.max()).mean()))


def food_stand_in(n):
    g = np.mgrid[0:n, 0:n].astype(float)
    return np.clip(0.5 + 0.35 * np.sin(g[1] / (n / 14.0)) * np.cos(g[0] / (n / 9.0)), 0.0, 1.0)


def cases():
    out = [('default', {})]
    for i, name in enumerate(['SenseAngle', 'SenseDist', 'MoveSpeed', 'Persistence']):
        for v in (0.0, 1.0):
            q = [0.5, 0.5, 0.5, 0.5]
            q[i] = v
            out.append((f'{name}={v:g}', {'slider': tuple(q)}))
    out += [('bass=1', {'bass': 1.0}), ('mouse', {'mouse': (64.0, 64.0, 12.0)}), ('no food', {'food': 'none'}),
            ('scale s=2', {'n': 256, 'agents': 16384, 's': 2.0}),
            ('control: no steer', {'steer': False, 'expect_fail': True})]
    return out


def main():
    bad = []
    print('%-18s %7s %6s %6s %6s %6s %6s %6s  %s' % (
        'case', 'mean', 'cv', 'giant', 'ncomp', 'hot', 'shared', 'dedup', 'verdict'))
    for name, kw in cases():
        t0 = time.time()
        kw = dict(kw)
        n = kw.get('n', 128)
        expect_fail = kw.pop('expect_fail', False)
        food = kw.pop('food', None)
        food = np.zeros((n, n)) if food == 'none' else food_stand_in(n)
        T, hits, shared = run(food=food, **kw)
        m = metrics(T)
        problems = []
        if m['giant'] < 0.80:
            problems.append('giant<0.80')
        if m['cv'] <= 0.15:
            problems.append('cv<=0.15')
        if m['hot'] < 0.03:
            problems.append('collapse')
        if hits > 0:
            problems.append('double deposit')
        if expect_fail:   # the metrics must reject a random walk, or they prove nothing
            verdict = 'ok (rejected: %s)' % ','.join(problems) if problems else 'FAIL control passed as a network'
            if not problems:
                bad.append(name)
        else:
            verdict = 'ok' if not problems else 'FAIL ' + ','.join(problems)
            if problems:
                bad.append(name)
        print('%-18s %7.3f %6.2f %6.2f %6d %6.3f %6d %6d  %s  (%.1fs)' % (
            name, m['mean'], m['cv'], m['giant'], m['ncomp'], m['hot'], shared, hits, verdict, time.time() - t0))
    if bad:
        print('physarum_agents: %d case(s) outside tolerance: %s' % (len(bad), ', '.join(bad)))
        return 1
    print('physarum_agents: all cases inside tolerance (CPU spec only; the WGSL is checked on SwiftShader)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
