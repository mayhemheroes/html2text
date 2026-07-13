#!/usr/bin/env bash
#
# mayhem/test.sh — RUN html2text's own test suite (upstream test/run_tests.py, executed via the
# Python-3 port mayhem/run_tests_py3.py — every upstream case + assertion preserved) and emit a
# CTRF (ctrf.io) summary. exit 0 iff failed==0. PATCH-grade oracle: each case asserts the exact
# golden Markdown (test/*.md) for its HTML fixture, so a no-op/neutered html2text FAILS here.
#
# Python-2-only cases (upstream .travis.yml runs the suite on py2.5-2.7 only; xrange/unichr/
# float-nesting code paths cannot run on the image's Python 3) are reported as SKIPPED — see the
# verified per-case list in mayhem/run_tests_py3.py.
#
# It does NOT compile — build.sh installed atheris into the in-image site dir and compiled the
# html2text_run_tests ELF wrapper. We only RUN the suite, routed through that compiled NON-system
# wrapper so the gate's sabotage check (neuter non-system binaries to exit(0)) actually perturbs
# the run (the CPython interpreter under /usr/bin would otherwise be spared).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"

SRC="${SRC:-/mayhem}"
cd "$SRC"

# Put the in-image site dir (atheris) and the html2text source tree on PYTHONPATH.
PY_PREFIX=/opt/toolchains/python
# shellcheck disable=SC1091
[ -f "$PY_PREFIX/env.sh" ] && source "$PY_PREFIX/env.sh"
export PYTHONPATH="$PY_PREFIX/site:$SRC${PYTHONPATH:+:$PYTHONPATH}"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/html2text_run_tests"
if [ ! -x "$RUNNER" ]; then
  echo "test.sh: $RUNNER missing/not executable — mayhem/build.sh must build it first" >&2
  emit_ctrf "run_tests" 0 1 0
  exit 1
fi

LOG="$(mktemp)"
"$RUNNER" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

# Parse the runner's summary line: "N passed, M failed, K skipped".
line="$(grep -E '^[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped' "$LOG" | tail -1)"
get() { echo "$line" | grep -oE "[0-9]+ $1" | grep -oE '^[0-9]+' | head -1; }
passed="$(get passed)";   passed="${passed:-0}"
failed="$(get failed)";   failed="${failed:-0}"
skipped="$(get skipped)"; skipped="${skipped:-0}"
rm -f "$LOG"

# If the runner could not run at all (no parseable summary), report a failure.
if [ "$(( passed + failed + skipped ))" -eq 0 ]; then
  emit_ctrf "run_tests" 0 1 0
  exit 1
fi
# A crash after a parseable line still counts as a failure.
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then
  failed=1
fi

emit_ctrf "run_tests" "$passed" "$failed" "$skipped"
