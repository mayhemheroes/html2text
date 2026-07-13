#!/usr/bin/env bash
#
# mayhem/build.sh — build the html2text Atheris fuzz harness launcher + its standalone
# reproducer, and prepare the project's own test suite runner. Runs inside the commit image
# (mayhem/Dockerfile) as `mayhem` in /mayhem. Python adaptation of the C/C++ template.
#
# What it does (must be idempotent + air-gapped on re-run — SPEC §6.2 item 9 / §6.5):
#   1. Populate / reuse an in-image wheelhouse under /opt/toolchains/python (HOME-independent),
#      then install atheris OFFLINE from that wheelhouse into a fixed site dir on PYTHONPATH.
#      The first (CI, online) build fills the wheelhouse; the air-gapped PATCH re-run resolves
#      entirely from it (pip --no-index --find-links). html2text itself has no runtime deps and
#      is exercised as its editable source tree (repo root on PYTHONPATH).
#   2. Compile launcher.c -> the ELF Mayhem target `html2text_fuzzer` (Atheris is a Python
#      script; Mayhem needs an ELF cmd, and the gate needs DWARF < 4 — hence a compiled wrapper).
#   3. Build the same launcher as the standalone (run-once) reproducer `html2text_fuzzer-standalone`.
#   4. Compile the ELF suite-runner wrapper `html2text_run_tests` (so the sabotage oracle bites).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# The base image exports the build contract (CC, SANITIZER_FLAGS, DEBUG_FLAGS, ...). The
# launcher is a thin C exec wrapper; the fuzzed code is Python, instrumented by Atheris at
# import time, so $SANITIZER_FLAGS on the wrapper mainly keeps the contract overridable
# (an explicit empty SANITIZER_FLAGS builds it with no sanitizers).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

SRC="${SRC:-/mayhem}"
cd "$SRC"

# ── Python toolchain caches at a FIXED, $HOME-independent prefix (SPEC §6.2 item 8) ──
PY_PREFIX=/opt/toolchains/python
WHEELHOUSE="$PY_PREFIX/wheelhouse"
SITE="$PY_PREFIX/site"
mkdir -p "$WHEELHOUSE" "$SITE"

PY="$(command -v python3)"

# 1) Wheelhouse: download every runtime dependency ONCE (online). On the air-gapped re-run the
#    directory is already populated, so pip never reaches the network. atheris ships a prebuilt
#    manylinux wheel for this CPython.
PKGS=(atheris)
need_download=0
"$PY" -c "import os,glob,sys; sys.exit(0 if glob.glob(os.path.join('$WHEELHOUSE','atheris-*.whl')) else 1)" || need_download=1
if [ "$need_download" -eq 1 ]; then
  echo ">> populating wheelhouse (online) at $WHEELHOUSE"
  "$PY" -m pip download --dest "$WHEELHOUSE" "${PKGS[@]}"
else
  echo ">> wheelhouse already populated — reusing $WHEELHOUSE (air-gapped re-run path)"
fi

# 2) Install the deps into the fixed site dir, OFFLINE from the wheelhouse. --no-index +
#    --find-links guarantees no PyPI access (works on the air-gapped re-run). Idempotent: once
#    the site dir holds atheris we SKIP the reinstall. html2text itself stays the editable
#    source tree (repo root on PYTHONPATH) so a PATCH agent's edits to html2text.py take
#    effect with no reinstall.
if "$PY" -c "import os,glob,sys; sys.exit(0 if glob.glob(os.path.join('$SITE','atheris*')) else 1)"; then
  echo ">> deps already installed in $SITE — skipping (idempotent re-run)"
else
  echo ">> installing deps (offline) into $SITE"
  "$PY" -m pip install --no-index --find-links="$WHEELHOUSE" --target "$SITE" "${PKGS[@]}"
fi

# html2text is a single top-level module at the repo root, so the repo root goes on PYTHONPATH.
PYRUN="$SITE:$SRC"

# Record the site dir + interpreter for test.sh / the launcher to consume.
cat > "$PY_PREFIX/env.sh" <<EOF
export PYTHONPATH="$PYRUN\${PYTHONPATH:+:\$PYTHONPATH}"
export PYTHON_BIN="$PY"
EOF

# Sanity: the harness imports must resolve offline now.
PYTHONPATH="$PYRUN" "$PY" -c 'import atheris, html2text; print("imports OK: html2text", html2text.__version__)'

# 3) Compile the ELF launcher target + the standalone reproducer (DWARF < 4 via $DEBUG_FLAGS).
#    The launcher execs $PY on the harness; PYTHONPATH is baked into the env the binary inherits
#    at run time (the Dockerfile sets ENV PYTHONPATH), so the Python side finds atheris + html2text.
HARNESS="$SRC/mayhem/fuzz-html2text.py"
echo ">> compiling html2text_fuzzer (+ standalone) with DEBUG_FLAGS=$DEBUG_FLAGS"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -DPYTHON="\"$PY\"" -DHARNESS="\"$HARNESS\"" \
    "$SRC/mayhem/launcher.c" -o "$SRC/html2text_fuzzer"
# The standalone reproducer is the same launcher: libFuzzer runs a single input file once when
# the harness is given a file path (no fuzzing loop) — exactly the run-once reproducer contract.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -DPYTHON="\"$PY\"" -DHARNESS="\"$HARNESS\"" \
    "$SRC/mayhem/launcher.c" -o "$SRC/html2text_fuzzer-standalone"

# 4) The suite runs through a compiled NON-system ELF wrapper so the gate's anti-reward-hack
#    sabotage check (which neuters non-system binaries to exit(0)) actually bites the suite.
$CC $DEBUG_FLAGS -DPYTHON="\"$PY\"" -DRUNNER="\"$SRC/mayhem/run_tests_py3.py\"" \
    "$SRC/mayhem/run_tests.c" -o "$SRC/html2text_run_tests"

echo ">> build.sh complete"
ls -la "$SRC/html2text_fuzzer" "$SRC/html2text_fuzzer-standalone" "$SRC/html2text_run_tests"
