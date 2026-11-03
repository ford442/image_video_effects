# Pipeline report — upload-token server half

Branch `chore/storage-upload-token-pipeline` from `origin/main` @ `00db5f72`. Run on the cloud VM on 2026-11-01
(the file name keeps the requested date). Node v22.23.4 / npm 10.9.9 (`engines` asks for ≥ 24: `EBADENGINE` warning only),
Python 3.13, `redis-server` available locally. Production and the external media hosts are unreachable from this VM,
so nothing here probes production (see [What I could not verify](#what-i-could-not-verify)).

## Summary

* The server half now exists: `POST /upload-token` and `POST /image-effects` (also under `/webhook/*`, where the
  client's default `STORAGE_VPS_URL` points) in `storage_manager/routes/webhook.py`.
* `storage_manager` suite: **143 passed** (104 existing + 39 new). The new suite includes a real `redis-server`.
* A live uvicorn + Redis run **found a real replay hole that all 37 first-draft unit tests missed** (below). Fixed and regression-tested.
* Of the 14 table rows, 11 are green. **3 are red and none is caused by this branch**: `npm ci` (a blocked binary download; passes with
  `--ignore-scripts`), and `test:ci` (2 tests) and `verify:toolchain-foundation` (3 sub-gates), both caused by shader data and contracts and
  both reproduced on a detached `origin/main` worktree.

## Pipeline table

| # | Step | Command | Exit | Key numbers |
|---|------|---------|------|-------------|
| 1 | Install | `npm ci` | **1** | 74 s. `onnxruntime-node` (`@huggingface/transformers`) install script died with `ECONNRESET` (binary download blocked) |
| 1b | Install, scripts off | `npm ci --ignore-scripts` | 0 | 17 s, 427 packages; audit reports 21 vulns (17 moderate, 2 high, 2 critical), not triaged |
| 2 | Typecheck | `npm run typecheck` | 0 | 18 s |
| 3 | Lint | `npm run lint` | 0 | 35 s, 0 errors, **123 warnings** (ratchet 125) |
| 4 | Unit tests | `npm run test:ci` | **1** | 193 files, 1610 tests: **1607 passed, 2 failed, 1 skipped** (79 s). Both failures pre-existing, see below |
| 5 | Build | `npm run build` | 0 | 45 s, `build/` 161 MB, `main.af10ef23.js` 1,033 kB (293 kB gz) |
| 6 | No client secrets | `npm run verify:no-client-secrets` | 0 | "no client secrets in build" |
| 7 | Bundle size | `npm run verify:bundle-size` | 0 | main **285.14 KiB gzip / 325.00 KiB budget** |
| 8 | Toolchain foundation | `npm run verify:toolchain-foundation` | **1** | **10/13 gates pass**; failed: `verify:shader-definitions`, `verify:prelude-migration`, `verify:naga-wasm:all`. All pre-existing |
| 9 | Shader sync (dry) | `npm run sync:shaders:dry` | 0 | 1412 definitions, 1364 tracked, 1286 up to date, **79 would upload**, 47 missing local WGSL; "Dry run: Yes" |
| 10 | Full deploy (dry) | `python3 tools/deploy/deploy.py --dry-run` | 0 | "no network connection opened, nothing written": 2853 files / 154.6 MiB planned, 1 skipped, **13 remote files would be deleted** |
| 11 | App-only deploy (dry) | `python3 tools/deploy/deploy_app_only.py --dry-run` | 0 | 1127 files / 120.1 MiB planned, 274 skipped, `shaders/` skipped |
| 12 | Deploy tests | `pytest tools/deploy/test_deploy_dry_run.py tools/deploy/test_deploy_credentials.py` | 0 | 12 passed |
| 13 | storage_manager tests | `cd storage_manager && python -m pytest -q` | 0 | **143 passed** (baseline 104 + 39 new) |

**Nothing uploaded in steps 9–11.** Beyond reading the "dry run" banners, I re-ran all three with `socket.connect`,
`connect_ex` and `getaddrinfo` patched to raise: 0 network attempts each, exit 0 (the deploy scripts need
`PYTHONPATH=tools/deploy` under that harness). No `.env.deploy` exists on this VM, so no credentials were loaded.

## End-to-end token round trip (local)

Real `uvicorn` on `127.0.0.1:7861` serving the real app, `WEBHOOK_SIGNING_SECRET` = 64 random hex chars, a real
`redis-server` for the nonce store, and a **directory standing in for the GCS bucket** (no GCP credentials here; GCS itself is
unverified). Origin `https://test.1ink.us`. Token values redacted.

| Step | Request | Result |
|------|---------|--------|
| 1 | `GET /api/health` | 200 `{"status":"online","gcs_connected":true,...}` |
| 2 | `POST /upload-token {"action":"save_shader","name":"e2e-demo"}` | 200 `{"token":"v1.1793551766.DTPI…","expires_at":"2026-11-01T16:49:26Z","expires_in":60}` |
| 3 | `POST /image-effects` + that token | **200** `{"status":"success","message":"Shader saved as e2e-demo","files":["image-effects/shaders/e2e-demo.wgsl"]}` |
| 4 | same token again, twice | **401** `token_already_used` ×2 |
| 5 | `/upload-token` with `Origin: https://evil.example` | 403 `origin_not_allowed` |
| 6 | `/image-effects`, no `Authorization` | 401 `missing_token` |
| 7 | fresh token, body `name` changed | 403 `token_mismatch`; the same token then succeeds for its own name (200): a mismatch does not burn it |
| 8 | `/webhook/upload-token` → `/webhook/image-effects` (`save_metadata`), then replay | 200, then 401 |
| 9 | replay the step-2 token after later saves had flushed the cache DB | 401 `token_already_used` |
| – | 35 `/upload-token` requests from one IP | 30 × 200, 5 × 429 |

Bucket afterwards: `image-effects/shaders/e2e-demo.wgsl`, `image-effects/metadata/cfg.json`, `shaders/e2e-demo.wgsl`,
`shaders/_shaders.json`. The server log and bucket contain **0 occurrences** of the secret, the issued token, or its signature;
the log carries only `{"event":"webhook_token_issued|webhook_write|webhook_token_rejected","action":...}`.

## What failed, and root cause

### 1. Replay hole found by the live run (mine; fixed)
First live run: step 4 returned **200** for a replayed `save_shader` token while a `save_metadata` token was correctly single-use,
and Redis held one nonce key where two were expected. Root cause: with Redis configured, `state.clear_cache_for_type()`, which every
shader save calls, falls through to aiocache `RedisBackend._clear(namespace=None)`, which is **`FLUSHDB`**. My nonces lived in the
same DB, so each shader save erased them and the token became reusable for the rest of its 60 s. I first suspected a key-prefix collision with the cache namespace; a
repro showed even a non-namespaced key was wiped, so a prefix change would not have fixed it.
Fix: nonces use their own logical DB (`WEBHOOK_REDIS_DB`, default `REDIS_DB + 1`), and the store refuses (503) if it equals the cache's DB.
Regression `test_redis_nonces_survive_a_cache_flush` runs against real Redis and **fails (replay → 200) if the nonce DB is pointed back at the cache's**.
Re-run live: step 9 above.

### 2. `npm ci` exit 1 — environment
`onnxruntime-node` postinstall download `ECONNRESET` (host blocked). Passes with `--ignore-scripts`, as `AGENTS.md` anticipates. (`AGENTS.md` names `sharp`; this time it was `onnxruntime-node`.)

### 3. `test:ci` — 2 failures, pre-existing on `origin/main` @ `00db5f72` (reproduced on a clean worktree)
* `shaderDefinitionSchema.test.ts`: `generative.json:gen-abyssal-geode-matrix` fails the schema. `verify:shader-definitions` names the cause: `shader_definitions/generative/gen-abyssal-geode-matrix.json`, `/workgroup_size: must NOT have fewer than 3 items`.
* `semanticIndex.test.ts` "covers every entry with an embedding": `index.vectors.every(Boolean)` is false. I did not pin down which entry lacks a vector; `public/shader-search-index.json` is regenerated by `npm run gen` during build.

### 4. `verify:toolchain-foundation` — 3 of 13 gates, pre-existing (same clean-worktree check)
* `verify:shader-definitions`: the `gen-abyssal-geode-matrix` entry above (1 of 1412 invalid).
* `verify:prelude-migration`: 17 shaders (`chroma-shift-grid`, `hex-mosaic`, `pp-bloom`, `neural-dreamscape`, …) no longer paste the header but are still in `src/contracts/prelude_migration.json` `pending`.
* `verify:naga-wasm:all`: `neural-dreamscape` now passes naga but is still in `knownFailures.ids`; the ratchet should drop to 21.

I did not fix these: they live in shader data and contracts owned by the shader-upgrade sessions, and `src/**` is off limits for this task.

### 5. Other things the run exposed (not fixed, no impact on this change)
* **`npm run build` rewrites tracked files** (`prebuild` → `npm run gen`): `README.md` catalog counts 1,398 → 1,399 and `public/shader-search-index.json`. `main`'s committed copies are stale. I reverted both so this PR stays scoped; `verify:generated-sync` / `verify:catalog-counts` passed only *after* that regeneration.
* **`cd storage_manager && python -m pytest` failed at baseline** (`ModuleNotFoundError: No module named 'storage_manager'`; only root-level runs worked). Added `storage_manager/conftest.py`; both invocations now pass.
* **No CI workflow runs the `storage_manager` tests** (`grep storage_manager .github/workflows` is empty). This suite only protects the change if someone runs it.
* **`state._create_cache_backend()` passes `serializer={"class": ...}` (a dict)**; with `REDIS_URL` set and aiocache 0.12.3, `GET /api/shaders` returns 500 (`'dict' object has no attribute 'loads'`). Reproduced on the live server. Only visible with Redis, which production may or may not use.
* **`test_sync_endpoints.py` leaves `state` damaged**: `patch("storage_manager.app.clear_cache_for_type")` plus the module proxy's `__delattr__` deletes the attribute from `state` for the rest of the session, so tests that run after it can hit `AttributeError`. My suite restores it in a fixture; the proxy itself is untouched.
* **Rate limiting trusts `X-Forwarded-For`** (`RATE_LIMIT_IP_HEADER`). If storage_manager is reachable without a proxy that overwrites that header, a client can pick its own bucket and the new webhook limit is bypassable.
* `scripts/bulk_upload_via_webhook.py` posted unauthenticated and would now get 401. I updated it to fetch a token (it compiles; it was not run against a server).
* `deploy.py --dry-run` plans to **delete 13 remote files** in a real run. Review before the first real deploy.

## What the token does and does not give you

A token limits one write to one `action`+`name` for 60 s, once. **It does not authenticate the caller**: anyone who can send an
allowed `Origin` header (trivially forged by a non-browser client) can request one. The real controls are the dedicated rate-limit
bucket (30/min/IP/method), the action allow-list, name sanitising (last path segment, `[A-Za-z0-9._-]`), a 25 MiB body cap, and the fact
that the secret never leaves the server. It removes "anyone who reads the JS can forge uploads forever"; it does not create "only real users can write".
If writes must be restricted to real users, that needs a login, captcha or similar on `/upload-token`, which does not exist here.

## What I could not verify

* **Production.** `storage.noahcohn.com`, `storage.1ink.us` and DreamHost are blocked from this VM. I do not know what answers `POST https://storage.noahcohn.com/webhook/image-effects` today, whether `/webhook/*` reaches this FastAPI app or another receiver (the repo's `weekly_plan.md` says the receiver "is not in this repo"), or whether nginx rewrites the `/webhook` prefix. The routes answer both `/x` and `/webhook/x` to cover either.
* **GCS.** Writes were exercised against a fake bucket (unit tests) and a directory (live run). No real bucket I/O.
* **Where uploaded files are served from.** The response `files` are bucket object paths (`image-effects/...`); the client builds `STATIC_NGINX_URL + files[0]`. Whether that host serves those objects is a deployment question this repo cannot answer.
* **Browser end to end.** No browser or GPU drove the real client against this server. The client contract was checked by reading `src/services/storage/webhook.ts` and its test, and CORS preflight was checked with curl (`Access-Control-Allow-Headers: authorization,content-type`).
* **Multi-worker deployment.** Cross-worker single-use was tested with two store instances on one Redis, not with real multi-process uvicorn.
* **Other Redis setups.** Only the local `redis-server` was used; managed or clustered Redis without logical DBs is unsupported by the `WEBHOOK_REDIS_DB` approach.
* The 21 `npm audit` findings and the real (non-dry) deploy and sync paths were not run.

## Needs Noah

1. Set `WEBHOOK_SIGNING_SECRET` (≥ 32 chars, `openssl rand -hex 32`) on the VPS running storage_manager and restart it. Until then both routes return 503.
2. Rotate the old `REACT_APP_WEBHOOK_SECRET`: it was in every bundle until 10-26 and is public. Remove it from `.env` files, CI secrets (`STORAGE_WEBHOOK_SECRET` in `ci.yml`) and hosting config.
3. Confirm whether production already runs a different receiver for `/webhook/*` outside this repo; if so this change is dormant until traffic is pointed at storage_manager, and that receiver needs the same token contract.
4. If storage_manager runs more than one worker, set `REDIS_URL` (and keep `WEBHOOK_REDIS_DB` off the cache's DB).
