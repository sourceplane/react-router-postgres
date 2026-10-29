#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, migrates, deploys (dry),
# serves, and reads its database through the template's own query path: the
# page loaders' RPC calls over the Worker's BOOKS_SERVICE self-binding.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree,
# and that its own plan converges in the right order. This proves it WORKS,
# by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its PR merges), install with the
#      lockfile the product ships, render the wrangler fixtures (which must
#      change nothing: both renders are committed), typecheck, lint, test,
#      build. The landing itself is checked in the build box with `orun
#      validate` and `orun plan` alone (`checks: local`), and its PR runs
#      `plan` alone (an `orun/BASE-*` branch), so THIS is where a product those
#      steps refuse is caught: before the tag, not after a build has merged it;
#   2. a Postgres of its own on a random port, with Supabase's roles — the
#      database a Supabase project would be: `postgres` a login role WITHOUT
#      superuser or BYPASSRLS, `anon` and `authenticated` with the Data API's
#      default grants (testing/lib/local-postgres.sh) — and a stand-in for the
#      ONE Supabase Management API endpoint the migration runner calls
#      (testing/lib/fake-supabase-api.py), connected as `postgres`;
#   3. the db-migrate lane's own steps, rendered by `orun plan` for a push to
#      main and run IN THE TREE THE RUNNER STAGES for the job: install, build
#      @saas/db, apply — the `books` table, the template's nine books, and
#      row-level security on every table in `public` — then apply again, which
#      must apply nothing, and the pull-request profile's offline plan. The
#      library is there before the app serves a single request;
#   4. the web lane's own steps for stage, rendered for a pull request (the
#      verify profile carries deploy-dry-run; the deploy profile does not) and
#      run in its staged job tree: install, `verify-app-structure` (the
#      committed wrangler.deploy.jsonc must exist BEFORE the build, in a tree
#      with no build output), `build-app` — which re-renders BOTH configs from
#      the stage wiring document it is handed, as the deploy does — then
#      `verify-build-output` and `deploy-dry-run`, which must bind HYPERDRIVE
#      to the stage id and BOOKS_SERVICE to the stage Worker itself;
#   5. the built Worker under `wrangler dev` with the deploy config and the
#      stage Worker's name — so the self-binding resolves to itself, as it
#      does deployed — its HYPERDRIVE binding pointed at that Postgres. Eight
#      concurrent first requests to the library; the component's OWN
#      `smokeCommand`, verbatim; every route the product promises (the library
#      under the product's name, a genre sorted, a book with its related books,
#      a cover and the client assets, a 404, `/api/health`, which only the
#      Worker answers); a book added behind the app's back that the next render
#      lists; and the health check refusing a table opened to the Data API.
#      (wrangler dev's local binding has no query cache; a real Hyperdrive
#      serves a plain read from its cache for up to a minute);
#   6. the Data API's view of the same database: every table in `public` has
#      row-level security, and `anon` and `authenticated` — granted everything
#      Supabase grants them — read none of the books and can write none, while
#      the app, as the table's owner and nothing more, reads them all.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered tokens, create a real Supabase project and Hyperdrive config
# (Terraform is validated, not applied, in this repository), deploy for real
# and probe workers.dev. That is a bootstrap against a workspace
# (BOOTSTRAP.md); everything short of it is here.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, psql and a
# PostgreSQL server install (initdb, pg_ctl), and the network for
# `pnpm install` (or a warm store). A few minutes: three installs, two builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"
# shellcheck source=lib/local-postgres.sh
source "$here/lib/local-postgres.sh"

for bin in orun node pnpm python3 git curl psql; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done
pg_bin >/dev/null || { echo "e2e.test.sh needs a PostgreSQL server install (initdb, pg_ctl)" >&2; exit 1; }

scratch="$(mktemp -d)"
pgdir="$(mktemp -d)"
dev_pid=""
api_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So each
# server is started as its own process group (setsid) and the group stopped.
stop_group() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$pid" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$pid" 2>/dev/null || true
}
cleanup() {
  stop_group "$dev_pid"
  stop_group "$api_pid"
  pg_down "$pgdir"
  [ -n "$pgdir" ] && [ -d "$pgdir" ] && rm -rf "$pgdir"
  [ -n "$scratch" ] && [ -d "$scratch" ] && rm -rf "$scratch"
}
trap cleanup EXIT
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step — what the product's Checks
# workflow ran on a pull request before the product carried ci.yml alone —
# run here at once on the whole tree.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

# One job of a plan, written out as the runner would run it: each `run:` step
# (the `use:` actions are setup-node and setup-pnpm, which this machine has)
# as a numbered script, the job's env, and the component path the steps run
# in. Steps are picked BY ID when given, else every `run:` step in order.
extract_job() { # PLAN JOB-ID OUT-DIR [STEP-ID…]
  python3 - "$@" <<'PY'
import json, pathlib, sys
plan, jid, out, *want = sys.argv[1:]
job = next((j for j in json.load(open(plan))["jobs"] if j["id"] == jid), None)
if job is None:
    sys.exit(f"the plan has no job {jid}")
out = pathlib.Path(out); out.mkdir(parents=True)
steps = [s for s in job["steps"] if s.get("run")]
if want:
    by = {s["id"]: s for s in steps}
    missing = [w for w in want if w not in by]
    if missing:
        sys.exit(f"{jid} has no step(s) {missing}")
    steps = [by[w] for w in want]
for i, s in enumerate(steps):
    (out / f"{i:02d}.sh").write_text(s["run"])
    (out / f"{i:02d}.id").write_text(s["id"])
(out / "path").write_text(job.get("path") or ".")
with (out / "env").open("w") as f:
    for k, v in (job.get("env") or {}).items():
        f.write(f"export {k}={json.dumps(v)}\n")
PY
}
run_job() { # STEPS-DIR WORK-TREE ENV LOG-PREFIX
  local steps="$1" work="$2" envname="$3" logp="$4" s id
  for s in "$steps"/[0-9][0-9].sh; do
    id="$(cat "${s%.sh}.id")"
    echo "   ▸ $id"
    if ! (cd "$work/$(cat "$steps/path")" && source "$steps/env" && export ORUN_ENVIRONMENT="$envname" \
          && bash -e "$s") > "$logp-$id.log" 2>&1; then
      echo "FAIL: the lane's $id step" >&2; tail -40 "$logp-$id.log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"

# ── 1. the product's own pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
s01="$(git -C "$tree" rev-parse HEAD~1)"
at01="$scratch/at-01/$repo"
git -C "$tree" worktree add -q "$at01" "$s01"
checks "$at01" "$scratch/checks.log"
dirty="$(git -C "$at01" status --porcelain)"
[ -z "$dirty" ] || { echo "FAIL: the checks changed tracked files — a committed wrangler config is not its fixture render:" >&2; echo "$dirty" >&2; exit 1; }
echo "   the checks left the tree as committed (wire:fixture rendered both committed wrangler configs)"

# ── 2. a database, and the one API the migration runner calls ──────────────
echo "── a local Postgres and the Supabase Management API stand-in"
pgurl="$(pg_up "$pgdir" "$(free_port)")" || { echo "FAIL: Postgres did not start" >&2; exit 1; }
api_port="$(free_port)"
ref="localproject"
setsid python3 "$here/lib/fake-supabase-api.py" "$api_port" "$pgurl" --ref "$ref" > "$scratch/api.log" 2>&1 < /dev/null &
api_pid=$!
for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$api_port/" && break; sleep 0.3; done
# Said out loud rather than found later as the runner's bare "fetch failed":
# the stand-in must be up, and stay up, before a lane is pointed at it.
api_up() { kill -0 "$api_pid" 2>/dev/null && curl -s -o /dev/null "http://127.0.0.1:$api_port/"; }
api_up || { echo "FAIL: the Management API stand-in is not answering on :$api_port" >&2; cat "$scratch/api.log" >&2; exit 1; }
echo "   $pgurl; the API on :$api_port"

# The two plans the lanes below run from, each in the product's own tree: a
# push to main at the 01-product commit (the db-migrate lane's APPLY profile),
# and a pull request over the finished product against an empty base (the web
# lane's VERIFY profile, which carries deploy-dry-run, and db-migrate's PLAN).
(cd "$at01" && orun plan --intent intent.yaml --trigger github-push-main --env stage --output "$scratch/plan-main.json") > "$scratch/plan-main.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-main.log" >&2; exit 1; }
git -C "$tree" worktree remove --force "$at01"
mkdir -p "$scratch/pr"
git clone -q "$tree" "$scratch/pr/$repo"
prtree="$scratch/pr/$repo"
git -C "$prtree" checkout -q --orphan empty
git -C "$prtree" rm -rqf .
git -C "$prtree" -c user.email=t@example.invalid -c user.name=t commit -qm empty --allow-empty
git -C "$prtree" checkout -q main
(cd "$prtree" && orun plan --intent intent.yaml --trigger github-pull-request --base empty --head HEAD --env stage \
   --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan-pr.log" >&2; exit 1; }
# This tier runs the bootstrap floor, newer than the orun the product's CI
# pins, and both read the per-edge `modeRules`: on a pull request — which
# applies and deploys nothing — the infrastructure edges that order a push to
# main are advisory, so no lane waits on another. (placement.test.sh checks
# the push to main's order.)
python3 - "$scratch/plan-pr.json" <<'PY'
import json, sys
jobs = {j["component"]: j for j in json.load(open(sys.argv[1]))["jobs"] if j["environment"] == "stage"}
chain = ["supabase", "cloudflare-hyperdrive", "db-migrate", "web"]
for a, b in zip(chain, chain[1:]):
    ja, jb = jobs[a], jobs[b]
    if ja["id"] in (jb.get("dependsOn") or []) or ja["id"] not in (jb.get("advisoryDependsOn") or []):
        sys.exit(f"FAIL: on a pull request {b}@stage must name {a}@stage as advisory, not wait on it")
print("   pull request: " + " → ".join(chain) + ", every edge advisory")
PY

# ── 3. the db-migrate lane, in its staged job tree ─────────────────────────
echo "── the stage db-migrate lane: install, build @saas/db, apply — then apply again, and the PR's plan"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate" \
  install-dependencies build-db-package "Migration Apply"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate-again" "Migration Apply"
extract_job "$scratch/plan-pr.json" db-migrate.stage.migrate "$scratch/steps-migrate-plan" "Migration Plan"
# Staged from the fresh clone (a CI checkout: no build output, no
# node_modules); its migrations are the 01-product commit's, byte for byte.
mwork="$prtree/.orun/runs/e2e/db-migrate.stage.migrate/work"
python3 "$here/lib/stage-job.py" "$prtree" "$mwork"
# The component's secretEnv, as the lane resolves it: the supabase apply's
# published credentials and the brokered access token. SUPABASE_API_URL is
# the one value no lane has — it points the runner at the stand-in.
export SUPABASE_ACCESS_TOKEN=e2e-token SUPABASE_PROJECT_REF="$ref" SUPABASE_DB_PASSWORD=postgres \
       SUPABASE_DB_URL="$pgurl" SUPABASE_API_URL="http://127.0.0.1:$api_port"
api_up || { echo "FAIL: the Management API stand-in stopped before the lane ran" >&2; cat "$scratch/api.log" >&2; exit 1; }
run_job "$scratch/steps-migrate" "$mwork" stage "$scratch/migrate" \
  || { echo "   the stand-in's log:" >&2; tail -20 "$scratch/api.log" >&2; exit 1; }
applied() { python3 -c "import json,sys;t=open(sys.argv[1]).read();print(' '.join(json.loads(t[t.index('{'):t.rindex('}')+1])['applied']))" "$1"; }
want="000_control_baseline 010_books 020_books_seed 030_row_level_security"
[ "$(applied "$scratch/migrate-Migration Apply.log")" = "$want" ] \
  || { echo "FAIL: the first apply applied '$(applied "$scratch/migrate-Migration Apply.log")', not '$want'" >&2; exit 1; }
echo "   applied $want"
run_job "$scratch/steps-migrate-again" "$mwork" stage "$scratch/migrate-again"
[ -z "$(applied "$scratch/migrate-again-Migration Apply.log")" ] \
  || { echo "FAIL: a second apply applied '$(applied "$scratch/migrate-again-Migration Apply.log")'" >&2; exit 1; }
echo "   a second apply applied nothing (the ledger holds $(psql "$pgurl" -XAtc 'select count(*) from _migrations.applied') migrations)"
table="$(psql "$pgurl" -XAtc "select to_regclass('public.books') is not null, (select relrowsecurity from pg_class where oid = to_regclass('public.books')), pg_get_userbyid((select relowner from pg_class where oid = to_regclass('public.books'))), (select count(*) from books), (select last_value from books_id_seq)")"
[ "$table" = "t|t|postgres|9|9" ] \
  || { echo "FAIL: after the migrations books should exist, with RLS, owned by postgres, the nine seeded books, the id sequence at 9 — got '$table'" >&2; exit 1; }
echo "   books exists before the app serves: row-level security on, owned by postgres, the template's nine books, the id sequence past them"
run_job "$scratch/steps-migrate-plan" "$mwork" stage "$scratch/migrate-plan"
[ "$(applied "$scratch/migrate-plan-Migration Plan.log")" = "$want" ] \
  || { echo "FAIL: the pull request's offline plan did not verify every migration" >&2; exit 1; }
echo "   the pull request's plan step verifies every migration's checksum offline"
unset SUPABASE_ACCESS_TOKEN SUPABASE_PROJECT_REF SUPABASE_DB_PASSWORD SUPABASE_DB_URL SUPABASE_API_URL
rm -rf "$mwork"

# ── 4. the web lane's steps, for stage ─────────────────────────────────────
echo "── the stage web lane: install, verify-app-structure, build-app, verify-build-output, deploy-dry-run"
extract_job "$scratch/plan-pr.json" web.stage.verify-deploy "$scratch/steps-web" \
  install-workspace-dependencies verify-app-structure build-app verify-build-output deploy-dry-run
work="$prtree/.orun/runs/e2e/web.stage.verify-deploy/work"
# The job's private tree, staged as orun stages it — no build output, no
# node_modules: under stack-tectonic 0.19.0 the job installs inside it.
python3 "$here/lib/stage-job.py" "$prtree" "$work"
[ ! -e "$work/apps/web/build" ] && [ -f "$work/apps/web/wrangler.jsonc" ] && [ -f "$work/apps/web/wrangler.deploy.jsonc" ] \
  || { echo "FAIL: the staged tree is not a fresh checkout with both committed wrangler configs" >&2; exit 1; }
echo "   staged: $(realpath --relative-to="$prtree" "$work") — no build output, both committed wrangler configs"
# The stage wiring document, as the cloudflare-hyperdrive apply publishes it
# and the lane resolves it (secretEnv WIRING_CLOUDFLARE_HYPERDRIVE_STAGE).
hd_id="e2e0000000000000000000000000c0de"
export WIRING_CLOUDFLARE_HYPERDRIVE_STAGE="{\"hyperdrive_id\":\"$hd_id\",\"hyperdrive_name\":\"stg-$repo-stage\"}"
run_job "$scratch/steps-web" "$work" stage "$scratch/web"
unset WIRING_CLOUDFLARE_HYPERDRIVE_STAGE
for cfg in wrangler.jsonc wrangler.deploy.jsonc; do
  grep -q "\"id\": \"$hd_id\"" "$work/apps/web/$cfg" && grep -q "\"service\": \"$repo-web-stage\"" "$work/apps/web/$cfg" \
    && grep -q "\"name\": \"$repo-web-stage\"" "$work/apps/web/$cfg" \
    || { echo "FAIL: build-app did not re-render $cfg from the stage wiring document, its self-binding the stage Worker" >&2; exit 1; }
done
dry="$scratch/web-deploy-dry-run.log"
grep -Eq "env\.HYPERDRIVE \($hd_id\) +Hyperdrive Config" "$dry" && grep -Eq "env\.BOOKS_SERVICE \($repo-web-stage#BooksService\) +Worker" "$dry" \
  || { echo "FAIL: the dry run does not bind HYPERDRIVE to the stage id and BOOKS_SERVICE to the stage Worker itself" >&2; tail -20 "$dry" >&2; exit 1; }
[ "$(node -e 'const fs=require("fs");process.stdout.write(String(fs.readdirSync(process.argv[1]).length))' "$work/node_modules")" -gt 0 ] && [ ! -L "$work/node_modules" ] \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
echo "   the staged build ran inside its own tree; the dry run binds the stage Hyperdrive id it was handed and the stage Worker's own BooksService"

# ── 5. serve it over the migrated, empty database ──────────────────────────
echo "── wrangler dev over the built Worker, its HYPERDRIVE binding on the local Postgres"
[ ! -e "$work/apps/web/.dev.vars" ] || { echo "FAIL: the staged tree carries a .dev.vars" >&2; exit 1; }
port="$(free_port)"
(cd "$work/apps/web" && CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE="$pgurl" \
   exec setsid pnpm exec wrangler dev --config wrangler.deploy.jsonc --ip 127.0.0.1 --port "$port" \
   --show-interactive-dev-session=false) > "$scratch/dev.log" 2>&1 < /dev/null &
dev_pid=$!
url="http://127.0.0.1:$port"
# Ready when the Worker answers its database check — which reads, and never
# writes, so the page's first request is still to come.
for _ in $(seq 1 90); do
  curl -s -o /dev/null "$url/api/health" && break
  kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
  sleep 1
done
curl -s -o /dev/null "$url/api/health" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
[ "$(psql "$pgurl" -XAtc 'select count(*) from books')" = 9 ] \
  || { echo "FAIL: the library does not hold the nine seeded books before the first page request" >&2; exit 1; }

echo "   ▸ eight concurrent first requests to the library"
python3 - "$url" <<'PY' || { echo "FAIL: the concurrent first requests; wrangler dev said:" >&2; tail -40 "$scratch/dev.log" >&2; exit 1; }
import concurrent.futures, sys, urllib.request
base = sys.argv[1]
def get(_):
    with urllib.request.urlopen(base + "/", timeout=120) as r:
        return r.status, r.read().decode()
with concurrent.futures.ThreadPoolExecutor(8) as pool:
    results = list(pool.map(get, range(8)))
bad = [(s, b.count('class="book-card ')) for s, b in results
       if s != 200 or b.count('class="book-card ') != 9 or "Demo Mode" in b or "</html>" not in b]
if bad:
    sys.exit(f"  ✕ {len(bad)} of 8 first requests did not render the nine books from the database: {bad[:3]}")
print("   all 8 rendered the nine books from the database, none in the template's demo mode")
PY
grep -q '\[BooksService\] Books found in database' "$scratch/dev.log" \
  || { echo "FAIL: the page's loader did not reach the database through the BooksService entrypoint" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }
echo "   the loaders called the BooksService entrypoint over the self-binding, and it read the database"

echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the product" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ every route the product promises, and the library reading the database"
python3 - "$url" "$values" "$pgurl" <<'PY' || { echo "FAIL: the routes; wrangler dev said:" >&2; tail -40 "$scratch/dev.log" >&2; exit 1; }
import html, http.client, json, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
base, values, pgurl = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
name = values["productname"]
problems = []
def bad(m): problems.append(m)

def req(path, method="GET"):
    # A request whose CONNECTION drops (not one that answers an error) is
    # asked again, twice at most, and says so: `wrangler dev` on a loaded
    # machine has dropped one.
    for attempt in range(3):
        try:
            r = urllib.request.Request(base + path, method=method)
            with urllib.request.urlopen(r, timeout=60) as resp:
                return resp.status, {k.lower(): v for k, v in resp.headers.items()}, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read()
        except (http.client.RemoteDisconnected, ConnectionResetError) as e:
            if attempt == 2:
                raise
            print(f"   ({method} {path}: the connection dropped ({e.__class__.__name__}) — asking again)")
            time.sleep(1)
def psql(sql):
    return subprocess.run(["psql", pgurl, "-XAtc", sql], capture_output=True, text=True, check=True).stdout.strip()
def text(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()
def titles(page):
    return [text(t) for t in re.findall(r'<h3 class="text-lg font-serif[^"]*">(.*?)</h3>', page, re.S)]

# ── the library, under the product's own name ─────────────────────────────
s, _, body = req("/"); page = body.decode()
if s != 200:
    bad(f"/ answered {s}")
title = re.search(r"<title>(.*?)</title>", page, re.S)
if not title or html.unescape(title.group(1)) != name:
    bad(f"the page's <title> is {title and title.group(1)!r}, not {name!r}")
h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
if not h1 or text(h1.group(1)) != name:
    bad(f"the library's heading is {h1 and text(h1.group(1))!r}, not {name!r}")
if "My Library" in page:
    bad("the page still carries the baseline's name")
want = sorted(psql("select title from books").splitlines())
if sorted(titles(page)) != want:
    bad(f"the library lists {sorted(titles(page))}, not the database's {want}")
for genre in ("Literary Fiction", "Historical Fiction", "Science Fiction & Fantasy"):
    if f'/genre/{urllib.parse.quote(genre)}' not in page:
        bad(f"the sidebar does not link the genre {genre!r}")

# ── a genre, sorted, and a book with its related books ────────────────────
s, _, body = req("/genre/" + urllib.parse.quote("Science Fiction & Fantasy") + "?sort=title_desc")
if s != 200 or titles(body.decode()) != ["The Left Hand of Darkness", "The Fifth Season"]:
    bad(f"the genre page sorted by title descending answered {s} {titles(body.decode())}")
s, _, body = req("/book/3"); page = body.decode()
h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
if s != 200 or not h1 or text(h1.group(1)) != "The Fifth Season" or "N.K. Jemisin" not in page \
        or "The Left Hand of Darkness" not in page:
    bad(f"/book/3 answered {s} {h1 and text(h1.group(1))!r}, without its author or its related book")

# ── what only the Worker answers ──────────────────────────────────────────
s, h, body = req("/api/health")
want_health = {"ok": True, "source": "database", "database": "reachable", "schema": "migrated", "books": 9}
if s != 200 or json.loads(body) != want_health or h.get("cache-control") != "no-store":
    bad(f"/api/health answered {s} {body[:160]!r} ({h.get('cache-control')})")

# ── a cover, the client assets and the not-found page ─────────────────────
s, h, body = req("/images/books/jane-eyre.jpg")
if s != 200 or h.get("content-type") != "image/jpeg" or not body:
    bad(f"a cover answered {s} {h.get('content-type')}")
_, _, home = req("/")
assets = sorted(set(re.findall(r'(?:src|href)="(/assets/[^"]+\.(?:js|css))"', home.decode())))
if not assets:
    bad("the page links no client assets")
for path in assets[:4]:
    s, h, body = req(path)
    if s != 200 or not body:
        bad(f"{path} answered {s}")
s, _, _ = req("/no-such-page")
if s != 404:
    bad(f"/no-such-page answered {s}, not 404")

# ── the library reads the database (locally on every request: no cache) ──
psql("insert into books (title, author, description, image_url, genre) values "
     "('Kindred', 'Octavia E. Butler', 'A writer is pulled back in time.', '/images/books/jane-eyre.jpg', 'Science Fiction & Fantasy')")
s, _, body = req("/")
listed = titles(body.decode())
if s != 200 or "Kindred" not in listed or len(listed) != 10:
    bad(f"a book added behind the app's back is not on the next render ({s}, {len(listed)} books)")
new_id = psql("select id from books where title = 'Kindred'")
if new_id != "10":
    bad(f"the added book took id {new_id}, not 10 — the seed did not move the sequence past its ids")
s, _, body = req(f"/book/{new_id}")
if s != 200 or "Octavia E. Butler" not in body.decode():
    bad(f"/book/{new_id} answered {s}")

# ── the health check refuses a table opened to the Data API ──────────────
psql("alter table books disable row level security")
s, _, body = req("/api/health")
if s != 503 or json.loads(body).get("schema") != "no row-level security":
    bad(f"with row-level security off /api/health answered {s} {body[:120]!r}, not 503")
psql("alter table books enable row level security")
psql("delete from books where title = 'Kindred'")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   / as {name!r} (title, heading, the database's nine books, the genres); a genre sorted; a book "
      f"with its related books; /api/health; a cover and {len(assets)} client asset(s); a 404; a book added "
      f"behind its back listed on the next render; the health check refusing a table opened to the Data API")
PY

# ── 6. what Supabase's Data API would see ──────────────────────────────────
echo "── the Data API's roles (anon, authenticated) against the same database"
psql "$pgurl" -X -q -v ON_ERROR_STOP=1 -At > "$scratch/rls.out" 2> "$scratch/rls.err" <<'SQL' \
  || { echo "FAIL: the row-level security checks" >&2; cat "$scratch/rls.err" >&2; exit 1; }
SELECT 'app role: superuser=' || rolsuper || ' bypassrls=' || rolbypassrls FROM pg_roles WHERE rolname = current_user;
SELECT 'public tables without RLS: ' || count(*) FILTER (WHERE NOT c.relrowsecurity) || ' of ' || count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
SELECT 'not owned by the app: ' || count(*) FILTER (WHERE pg_get_userbyid(c.relowner) <> current_user)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
SELECT 'app sees books: ' || count(*) FROM books;
SET ROLE anon;
SELECT 'anon sees books: ' || count(*) FROM books;
RESET ROLE;
SET ROLE authenticated;
SELECT 'authenticated sees books: ' || count(*) FROM books;
RESET ROLE;
SQL
sed 's/^/   /' "$scratch/rls.out"
grep -qx "app role: superuser=false bypassrls=false" "$scratch/rls.out" \
  && grep -qE "^public tables without RLS: 0 of [1-9][0-9]*$" "$scratch/rls.out" \
  && grep -qx "not owned by the app: 0" "$scratch/rls.out" \
  || { echo "FAIL: the app's role, the tables' owner or their row-level security is not what Supabase's would be" >&2; exit 1; }
app_rows="$(sed -n 's/^app sees books: //p' "$scratch/rls.out")"
[ "${app_rows:-0}" = 9 ] || { echo "FAIL: the app sees ${app_rows:-0} books, not the nine seeded" >&2; exit 1; }
for line in "anon sees books: 0" "authenticated sees books: 0"; do
  grep -qx "$line" "$scratch/rls.out" || { echo "FAIL: expected '$line'" >&2; exit 1; }
done
# A write through the Data API's roles is refused by row-level security.
for role in anon authenticated; do
  if psql "$pgurl" -X -q -At -c "SET ROLE $role; INSERT INTO books (title, author) VALUES ('$role', '$role')" > "$scratch/rls-write.log" 2>&1; then
    echo "FAIL: $role wrote a book through row-level security" >&2; exit 1
  fi
  grep -q "row-level security" "$scratch/rls-write.log" \
    || { echo "FAIL: $role's write was refused for another reason:" >&2; cat "$scratch/rls-write.log" >&2; exit 1; }
done
echo "   anon and authenticated, granted what Supabase grants them, read the $app_rows books as 0 and write none"

echo "e2e.test.sh: ok"
