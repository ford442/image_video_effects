# Pipeline report — storage hardening

Branch `chore/storage-hardening-2026-11-07` from `origin/main` @ `33b191e1`. Run on the cloud VM on 2026-11-08 (the file name keeps
the requested date). Node v22.23.4 / npm 10.9.9 (`engines` asks for ≥ 24: `EBADENGINE` warning only), Python 3.13 locally
(the new CI job pins 3.12), `redis-server` available locally. Production, DreamHost and the external media hosts are unreachable from
this VM, so nothing here probes production (see [What I could not verify](#what-i-could-not-verify)).
Follows up the "Other things the run exposed" list in [`pipeline_report_2026-10-31.md`](pipeline_report_2026-10-31.md).

## Summary

* **All 16 pipeline rows are green except plain `npm ci`** (a blocked binary download; `--ignore-scripts` passes). The three failures that report 10-31 called pre-existing
  (`test:ci` ×2, `verify:toolchain-foundation` ×3 gates) no longer fail on current `main`: 1805 tests pass, 13/13 gates pass.
* **CI now runs the `storage_manager` suite** (new `storage-manager-tests` job). Locally 163 tests pass: 143 existing + 2 Redis-cache regressions + 18 rate-limit tests.
* **aiocache bug fixed.** `GET /api/shaders` under `REDIS_URL` returned 500; the regression tests fail on the old code with the original `'dict' object has no attribute 'loads'`.
* **Rate limiting no longer trusts a client-supplied `X-Forwarded-For`** (`TRUSTED_PROXIES`). The live run found a second hole behind it: **uvicorn's own `--proxy-headers` runs first and can bypass the new guard** (below). Fixed for `python -m storage_manager.app`; needs a launch-flag check for however production starts it.
* **`npm audit`: 17 → 15 findings** with a lockfile-only, non-breaking fix. The 2 critical and 1 high that remain are all dev-only and need semver-major bumps; triage below.
* **The 13 remote deletes are all stale**: 9 old hashed `main.*` bundle files and 4 orphaned `-sg.wgsl` shader copies. Nothing needs protecting, so the keep-list is unchanged.

## Pipeline table

| # | Step | Command | Exit | Key numbers |
|---|------|---------|------|-------------|
| 1 | Install | `npm ci` | **1** | 45 s. `onnxruntime-node` (`@huggingface/transformers`) install script died with `ECONNRESET` (binary download blocked), same as 10-31 |
| 1b | Install, scripts off | `npm ci --ignore-scripts` | 0 | with the updated lockfile; audit: 15 findings (12 moderate, 1 high, 2 critical) |
| 2 | Typecheck | `npm run typecheck` | 0 | 11 s |
| 2b | Typecheck scripts | `npm run typecheck:scripts` | 0 | 1 s |
| 3 | Lint | `npm run lint` | 0 | 17 s, 0 errors, **122 warnings** (ratchet 125) |
| 4 | Unit tests | `npm run test:ci` | 0 | 202 files, **1805 passed**, 1 skipped, 0 failed (61 s), run with the updated lockfile |
| 5 | Build | `npm run build` | 0 | 16 s, `main.10f4f2af.js` 1,044.86 kB (296.34 kB gz). Tracked files stayed clean afterwards (10-31 saw `README.md` / search index rewritten) |
| 6 | No client secrets | `npm run verify:no-client-secrets` | 0 | "no client secrets in build" |
| 7 | Bundle size | `npm run verify:bundle-size` | 0 | main **288.48 KiB gzip / 325.00 KiB budget** |
| 8 | Toolchain foundation | `npm run verify:toolchain-foundation` | 0 | **13/13 gates pass**; naga-wasm: 12 known-bad shaders still ratcheted, non-blocking |
| 9 | Shader sync (dry) | `npm run sync:shaders:dry` | 0 | 1428 definitions, 1369 tracked, 1335 already synced, **42 would upload**, 51 missing local WGSL; "Dry run: Yes" |
| 10 | Full deploy (dry) | `python3 tools/deploy/deploy.py --dry-run` | 0 | 2892 files / 156.2 MiB planned (2 always, 215 hash-changed, 2675 new), 1 skipped, **13 remote deletes** (explained below) |
| 11 | App-only deploy (dry) | `python3 tools/deploy/deploy_app_only.py --dry-run` | 0 | 1144 files / 121.4 MiB planned, 272 skipped, `shaders/` skipped, never deletes |
| 12 | Deploy tests | `pytest tools/deploy/test_deploy_dry_run.py tools/deploy/test_deploy_credentials.py` | 0 | 12 passed |
| 13 | storage_manager tests | `cd storage_manager && python -m pytest -q` | 0 | **163 passed**, also from the repo root; `STORAGE_REQUIRE_REDIS=1` run also 163, no skips |
| 14 | Live round trip | uvicorn + `redis-server` | – | all expected statuses, see [below](#local-round-trip-uvicorn--redis) |

**Zero network attempts in rows 10 and 11.** Both were re-run under a harness that replaces `socket.connect`, `connect_ex`,
`create_connection` and `getaddrinfo` with a counter that raises: **0 attempts each, exit 0**. As a control, the same harness
around a script doing `urllib.request.urlopen("http://example.com")` records 1 attempt, so a 0 is meaningful. No `.env.deploy`
exists on this VM, so no credentials were loaded. Row 9 only printed its dry-run plan.

Without Redis the suite is 140 passed + 3 skipped (the real-Redis tests); with `STORAGE_REQUIRE_REDIS=1` and no binary those 3 fail.

## 1. CI job for `storage_manager`

New job `storage-manager-tests` in `.github/workflows/ci.yml`: Python 3.12 (same as the other Python jobs), pip cache keyed on
`storage_manager/requirements.txt`, `apt-get install redis-server`, then `python -m pytest -q` in `storage_manager/`.
The real-Redis tests start their own `redis-server` on a free port, so a service container was not needed. The fixture moved to
`storage_manager/conftest.py`: it **skips cleanly** when the binary is missing, but **fails** when `STORAGE_REQUIRE_REDIS=1` (set in CI),
so a missing Redis can never silently drop the nonce-replay and cache tests. Verified locally in all three modes (above).
**Not verified:** the job has not run on GitHub yet (no Actions here), and I ran Python 3.13, not 3.12.

## 2. aiocache serializer bug

`state._create_cache_backend()` passed `serializer={"class": "aiocache.serializers.JsonSerializer"}`: that dict form is for
`caches.add()` only. `Cache(Cache.REDIS, ...)` stores it as-is and aiocache calls `.loads` on it. Fix: `serializer=JsonSerializer()`.
`tests/test_cache_backend.py` builds the cache through the production factory against a real `redis-server` and
(a) asserts the serializer has `loads`/`dumps`, (b) calls `GET /api/shaders` twice (second is served from Redis after the bucket object is deleted).
**Both fail on the old `state.py`** (`AttributeError: 'dict' object has no attribute 'loads'`) and pass now. My first draft of (b) failed for a
test-only reason (a bare `TestClient` opens a new event loop per request, which a pooled Redis connection cannot survive); fixed with `with TestClient(app)`.
Live, step 7 of the round trip below: 200 twice with the cache in Redis.
Note: if production sets `REDIS_URL`, `/api/shaders` has been returning 500 until this ships.

## 3. Rate limiting and `X-Forwarded-For`

`TRUSTED_PROXIES` (IPs/CIDRs, **default `127.0.0.1,::1`**): `RATE_LIMIT_IP_HEADER` is read only when `request.client.host` is trusted; then the
chain is walked right to left, skipping trusted hops, and the first untrusted hop is the client. Unparseable values never become bucket keys (they
fall back to the peer), `::ffff:a.b.c.d` is normalised, repeated header lines are one chain, bad config entries are skipped with a warning rather than trusted.
18 new tests (`tests/test_rate_limit_proxies.py`): 13 pure-function cases and 5 through the real middleware. Four of them fail under the old "first entry wins" logic.
Existing webhook tests used a forged `X-Forwarded-For` to isolate themselves; they now use a unique TCP peer instead. Documented in `storage_manager/README.md`.

**Found by the live run: uvicorn pre-empts this.** uvicorn's `--proxy-headers` (default on) rewrites `request.client` from `X-Forwarded-For` when the peer is in
`FORWARDED_ALLOW_IPS` (default `127.0.0.1`), before any middleware. Measured with 35 requests, a fresh forged header each:

| Server | Result |
|--------|--------|
| uvicorn default proxy handling, `TRUSTED_PROXIES=""` | 35 × 200 (never limited: uvicorn trusted the loopback peer) |
| `--no-proxy-headers`, `TRUSTED_PROXIES=""` | 30 × 200, 5 × 429 |
| `--no-proxy-headers`, default (loopback trusted), client forges the left entry, same real client | 30 × 200, 5 × 429 |
| `--no-proxy-headers`, default, 35 different real clients behind the proxy | 35 × 200 (separate buckets) |

With the default `127.0.0.1` both layers agree, so a loopback nginx behaves correctly either way. With `FORWARDED_ALLOW_IPS='*'` (common in Docker recipes) uvicorn would let
any client choose its bucket and `TRUSTED_PROXIES` could not stop it. `python -m storage_manager.app` now passes `proxy_headers=False`; the README says to start the CLI with `--no-proxy-headers`.

## 4. `npm audit` triage

**Count:** 17 findings today (13 moderate, 2 high, 2 critical), not the 21 in the 10-31 report (17 moderate, 2 high, 2 critical). I did not bisect why
(advisory database and lockfile have both moved). After the fix: **15 (12 moderate, 1 high, 2 critical)**.

**Runtime vs dev-only.** Every flagged package is `dev: true` in `package-lock.json`, and **none of `tinypool`, `fast-uri`, `vitest`, `libvips`, `@img/sharp` appears in any `build/**/*.js`**.
(`@huggingface/transformers` does ship and nests its own `sharp@0.35.5`; that is outside the affected range and is not flagged.) Note `dependencies` in `package.json` is *not* empty (React, CodeMirror, web-llm, …), so `--omit=dev` happens to print 0 here, but the table is what matters.

| Package | Sev | Shipped? | Fix | Decision |
|---------|-----|----------|-----|----------|
| `fast-uri` 3.1.3 (via `ajv`) | high (3 host-confusion advisories) | No, dev (ajv validates shader definitions; nothing in `src/` imports it) | `npm audit fix`, non-breaking | **Fixed:** 3.1.9 |
| `vitest` 3.2.7 (direct) | critical (rolled up from `tinypool`; its own advisory GHSA-82fw-gwwq-j7x9 is moderate, CVSS 5.9) | No, dev | `vitest@5.1.0`, **semver-major**; the advisory says 2.1.x and 3.x are unmaintained | **Accepted risk**, below |
| `tinypool` 1.1.1 (via vitest) | critical, CVSS 4.0 9.5 (GHSA-5gmw-xhrv-c9v3, GHSA-85c8-ppgw-ccpr) | No, dev | patched in 2.1.1; only reachable through vitest 5 | **Accepted risk**, below |
| `sharp` 0.34.5 (direct) | high (libvips / libheif / librsvg advisories) | No, dev | `sharp@0.35.5`; 0.x minor, so npm marks it major | **Accepted risk**, below |

Why accepted:
* **tinypool / vitest.** The tinypool advisory needs a prototype-pollution primitive somewhere else in the process to reach worker options; the advisory page says the attacker does not control tinypool's options directly. It runs only in `vitest run` on this repo's code, where any code able to pollute prototypes could already run arbitrary code. The vitest advisory needs `mockerPlugin`/`interceptorPlugin` registered on a Vite dev server bound to a reachable address; `vite.config.ts` uses neither, `test:ci` is `vitest run` (no listener), and no `@vitest/ui` or browser mode is installed.
* **sharp 0.34.5.** Used only by `scripts/generate-shader-thumbnails.js`, `scripts/lib/thumbnailFrameAnalysis.js` and Playwright specs, on PNGs the repo's own renderer produced. The advisories are about crafted HEIF/SVG input; not in the bundle.
* **Follow-ups (their own PRs, not "non-breaking"):** vitest 3 → 4.1.11+/5 (moves off an unmaintained line; needs the 202-file suite re-run), and sharp `^0.35.5` (run `scripts/generate-shader-thumbnails.test.js`).
* **Remaining 12 moderates** are all dev: the `typescript-eslint` chain (npm offers `8.36.0` as a "major" fix, which is a downgrade artefact; do not apply), the `minimatch`/`glob`/`test-exclude` chain under `@vitest/coverage-v8`, `@vitest/mocker` (vitest), `eslint-plugin-testing-library`, and `vite` (`server.fs.deny` bypass, which affects only the dev server; the patch release 6.4.5 is already in).

**Applied (lockfile only, `package.json` untouched): 15 dev-only bumps** — `fast-uri` 3.1.3 → 3.1.9, `vite` 6.4.4 → 6.4.5, `typescript-eslint` + 9 `@typescript-eslint/*` 8.71.2 → 8.72.1, `ignore` 7.0.12 → 7.0.14, `semver` 7.8.5 → 7.8.6.
npm 10 also strips the `libc` fields newer npm writes (which stop npm fetching both glibc and musl optional binaries), so I took only the bumped entries from npm's output; the committed diff is 73 insertions / 73 deletions of versions, hashes and ranges. After it: `npm ci --ignore-scripts`, `test:ci` (1805 passed) and `build` all pass, and `eslint` / `tsc` still pass.

## 5. The 13 remote deletes in `deploy.py --dry-run`

`deploy.py` has no remote listing offline: it deletes every path in the committed `.deploy_manifest.json` (231 entries, last committed 2026-10-26) that is **not in `build/`**
(`stale_manifest_entries`, run by `clean_remote` after all uploads, so the new `index.html` is on the server before the old files go). It is the same 13 as on 10-17 and 10-31.

| # | Path | Class | Why it would be deleted |
|---|------|-------|-------------------------|
| 1–3 | `static/js/main.d7ca0e24.js`, `.js.map`, `.js.LICENSE.txt` | stale hashed asset | An older build's entry bundle. Current `build/index.html` references `main.10f4f2af.js`; the old hash appears nowhere in `build/`. |
| 4–6 | `static/js/main.503c20e6.js`, `.js.LICENSE.txt`, `.js.map` | stale hashed asset | Same, older build. |
| 7–9 | `static/js/main.1ee74a77.js`, `.js.map`, `.js.LICENSE.txt` | stale hashed asset | Same, older build. |
| 10 | `shaders/spec-histogram-equalize-sg.wgsl` | orphaned, not a stale hash | A subgroup variant that no longer exists. |
| 11 | `shaders/pp-sharpen-sg.wgsl` | orphaned | Same. |
| 12 | `shaders/rd-on-video-pass1-sg.wgsl` | orphaned | Same. |
| 13 | `shaders/slime-mold-on-video-sg.wgsl` | orphaned | Same. |

Rows 10–13 are the ones that could have been "something to keep", so I checked: `-sg.wgsl` files are optional subgroup variants, but **no `-sg` file exists in `public/shaders/` or in git history**, none of the four ids appear in `shader_definitions/`
or `public/shader-lists/`, nothing in `src/` builds an `<id>-sg` URL (`ShaderScanner` only skips catalog ids ending in `-sg` when subgroups are unsupported, and there are none), and the four base shaders contain no `subgroup` code.
They are copies uploaded by an earlier build/tool that were then removed from the source.
**Conclusion: nothing must be preserved, so the keep-list (`PROTECTED_FILES = ['index.html']`) is unchanged and I added no test.**

Caveats, not blockers: (a) the manifest records what *deploy.py* uploaded, not what the server holds, so the real run's `remove()` swallows `IOError` for anything already absent; (b) browsers holding a cached old `index.html` will 404 on the deleted bundle until they reload (this is how the script has always worked); (c) the manifest tracks only 231 files while `build/` has ~2900, so the "2675 new" figure is inflated and the real run's remote-size shortcut (not evaluable offline) may skip many of them.

## Local round trip (uvicorn + Redis)

Real `uvicorn` serving the real app, a real `redis-server` for the response cache (DB 0) and nonces (DB 1), `WEBHOOK_SIGNING_SECRET` = 64 random hex chars, and **a directory standing in for the GCS bucket** (no GCP credentials here; GCS itself is unverified). Origin `https://test.1ink.us`. Token values redacted.

| Step | Request | Result |
|------|---------|--------|
| 1 | `GET /api/health` | 200 `{"status":"online","gcs_connected":true,…}` |
| 2 | `POST /upload-token {"action":"save_shader","name":"e2e-demo"}` | 200 `{"token":"v1.179…","expires_in":60}` |
| 3 | `POST /image-effects` + that token | **200** `{"status":"success","message":"Shader saved as e2e-demo","files":["image-effects/shaders/e2e-demo.wgsl"]}` |
| 4 | same token again, twice | **401** `token_already_used` ×2 |
| 5 | `/upload-token` with `Origin: https://evil.example` | 403 `origin_not_allowed` |
| 6 | `/image-effects`, no `Authorization` | 401 `missing_token` |
| 7 | `GET /api/shaders` twice with the cache in Redis | **200**, 200 (`["e2e-demo"]`); this was 500 before the fix |
| – | rate-limit runs | see the table in section 3 |

Redis afterwards: 1 cache key in DB 0 and 1 nonce key in DB 1 (nonces survive the shader-save cache flush, as in 10-31). The server log and bucket contain **0 occurrences** of the secret.
Bucket: `image-effects/shaders/e2e-demo.wgsl`, `shaders/_shaders.json`, `shaders/e2e-demo.wgsl`.

## What I could not verify

* **Production.** `storage.noahcohn.com`, `storage.1ink.us` and DreamHost are blocked from this VM. I do not know how production starts uvicorn, whether it sits behind nginx, or what its `FORWARDED_ALLOW_IPS` is.
* **The new CI job on GitHub**, and Python 3.12 (I ran 3.13).
* **GCS and the real (non-dry) deploy and sync paths.** Writes went to a directory/fake bucket; the 13 deletes were planned, not executed.
* **`aiocache` is unpinned** (`>=0.12.0`); I tested 0.12.3, the version pip resolves today. I did not test a 1.x release, whose `Cache` factory may differ.
* **Advisory text** for sharp's three libvips/libheif/librsvg advisories: the GitHub advisory API is closed to this session, so that row rests on the titles, the affected range and how the repo uses sharp. The tinypool and vitest rows were read from the public advisory pages.
* Multi-worker deployment, managed Redis, and a browser end to end: unchanged from 10-31.

## Needs Noah

1. **Check how production launches storage_manager, before deploying this.** Two things: (a) add `--no-proxy-headers` (or confirm `FORWARDED_ALLOW_IPS` is not `*`); (b) if the reverse proxy is **not on loopback** (separate container, load balancer), set `TRUSTED_PROXIES` to its address/CIDR. Until you do, every user shares one rate-limit bucket; before this change the header was trusted from anyone, so this *is* a behaviour change. Details in `storage_manager/README.md`.
2. If production sets `REDIS_URL`: `/api/shaders` has been 500ing; this fixes it, but the cache has never been exercised there.
3. Approve the first real deploy: the 13 deletes are explained above (9 stale bundle files, 4 orphaned `-sg` shaders). Say so if you want the old bundles kept for a grace period; the keep-list would need an entry.
4. Decide on the two semver-major follow-ups: vitest 3 → 4.1.11+/5 and sharp 0.34 → 0.35.5. I did not apply them (you asked for non-breaking only). They are the only remaining critical/high findings, and all are dev-only.
5. Watch the first run of `storage-manager-tests` on this PR; if it is red, the likely cause is `apt-get install redis-server` on the runner.
6. Still open from 10-31, unchanged by this branch: set `WEBHOOK_SIGNING_SECRET` (≥ 32 chars, `openssl rand -hex 32`) on the VPS; rotate the old `REACT_APP_WEBHOOK_SECRET` (it was public in every bundle until 10-26) including the `STORAGE_WEBHOOK_SECRET` CI secret; confirm whether another receiver already serves `/webhook/*`; set `REDIS_URL` if running more than one worker.
