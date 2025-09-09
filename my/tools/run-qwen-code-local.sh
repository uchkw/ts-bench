#!/bin/zsh

set -euo pipefail

# Parallel ts-bench runner for Qwen Code against a local-compatible provider.
# - Uses my/tools/switch_openai_env.sh to set OPENAI_* for qwen-code
# - Clones exercism-typescript into .benchwork/<run-id>-<shard>-exercism-typescript via rsync
# - Initializes a tiny git repo inside each clone for agent workflows
# - Splits exercises into N shards and runs them concurrently
#
# Usage:
#   ./run-qwen-code-local.sh <model> <server> <provider> [--parallel N] [--timeout SEC] [--exercise <name|a,b,c>] [--docker-no-cache-build]
# Example:
#   ./run-qwen-code-local.sh qwen3-coder-30b-a3b-instruct-dwq-v2 gamma lmstudio --parallel 4

DEFAULT_MODEL="qwen3-coder-30b-a3b-instruct-dwq-v2"
DEFAULT_SERVER="localhost"
DEFAULT_LOCAL_PROVIDER_KIND="lmstudio"   # lmstudio | ollama | llamacpp | mlx

AGENT="qwen"
CLI_PROVIDER="local"                     # Important: set provider=local so qwen.ts loads OPENAI_* from env

MODEL=${1:-$DEFAULT_MODEL}
SERVER=${2:-$DEFAULT_SERVER}
LOCAL_PROVIDER_KIND=${3:-$DEFAULT_LOCAL_PROVIDER_KIND}
shift || true
shift || true
shift || true

PARALLEL=1
TIMEOUT_SEC=600
EXERCISE=""
DOCKER_NO_CACHE_BUILD=0
USE_DOCKER=1
PASS_THROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parallel)
      PARALLEL="${2:-$PARALLEL}"; shift 2 ;;
    --parallel=*)
      PARALLEL="${1#*=}"; shift ;;
    --timeout)
      TIMEOUT_SEC="${2:-$TIMEOUT_SEC}"; shift 2 ;;
    --timeout=*)
      TIMEOUT_SEC="${1#*=}"; shift ;;
    --exercise)
      EXERCISE="${2:-}"; shift 2 ;;
    --exercise=*)
      EXERCISE="${1#*=}"; shift ;;
    --docker-no-cache-build)
      DOCKER_NO_CACHE_BUILD=1; shift ;;
    --no-docker)
      USE_DOCKER=0; shift ;;
    --)
      shift; PASS_THROUGH_ARGS+=( "$@" ); break ;;
    *)
      # Keep unknown flags to pass through to bun (e.g., --save-result, --result-dir)
      PASS_THROUGH_ARGS+=( "$1" ); shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTAINER_NAME="ts-bench-container"
BENCH_ROOT="$REPO_ROOT/.benchwork"
mkdir -p "$BENCH_ROOT"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; }; }
require_cmd rsync
require_cmd bun
if [[ "$USE_DOCKER" == "1" ]]; then
  require_cmd docker
fi

if [[ "$USE_DOCKER" == "1" ]]; then
  # Ensure image
  if [[ "$DOCKER_NO_CACHE_BUILD" == "1" ]]; then
    echo "Rebuilding Docker image '$CONTAINER_NAME' with --no-cache..."
    ( cd "$REPO_ROOT" && docker build --no-cache -t "$CONTAINER_NAME" . )
  else
    if ! docker image inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
      echo "Docker image '$CONTAINER_NAME' not found. Building..."
      ( cd "$REPO_ROOT" && docker build -t "$CONTAINER_NAME" . )
    fi
  fi
fi

# Exercism dataset must exist
PRACTICE_DIR="$REPO_ROOT/exercism-typescript/exercises/practice"
if [[ ! -d "$PRACTICE_DIR" ]]; then
  echo "Error: $PRACTICE_DIR not found." >&2
  echo "  Initialize submodule: git submodule update --init --recursive" >&2
  echo "  or run: $REPO_ROOT/my/tools/reset-exercism-typescript.sh" >&2
  exit 1
fi

# Compute exercise list (comma-separated)
EXERCISE_CSV=""
if [[ -n "$EXERCISE" ]]; then
  EXERCISE_CSV="$EXERCISE"
else
  EXERCISE_CSV=$(cd "$PRACTICE_DIR" && ls -1d */ 2>/dev/null | sed 's:/$::' | sort | tr '\n' ',' | sed 's/,$//')
fi

if [[ -z "$EXERCISE_CSV" ]]; then
  echo "No exercises found." >&2
  exit 1
fi

# Split into shards
IFS=',' read -A EX_LIST <<< "$EXERCISE_CSV"
TOTAL=${#EX_LIST[@]}
if (( PARALLEL > TOTAL )); then PARALLEL=$TOTAL; fi

timestamp=$(date +%Y%m%d-%H%M%S)
RUN_ID="${AGENT}-${MODEL}-${LOCAL_PROVIDER_KIND}-${timestamp}"
LOG_DIR="$BENCH_ROOT/$RUN_ID/logs"
mkdir -p "$LOG_DIR"

echo "Agent:     $AGENT"
echo "Provider:  $CLI_PROVIDER (local kind: $LOCAL_PROVIDER_KIND)"
echo "Model:     $MODEL"
echo "Server:    $SERVER"
echo "Parallel:  $PARALLEL shards"
echo "Timeout:   $TIMEOUT_SEC s"
echo "Run ID:    $RUN_ID"

shard_ranges=()
base=$(( TOTAL / PARALLEL ))
rem=$(( TOTAL % PARALLEL ))
start=1
for (( i=1; i<=PARALLEL; i++ )); do
  size=$base
  (( i <= rem )) && size=$(( size + 1 ))
  end=$(( start + size - 1 ))
  if (( size > 0 )); then
    shard_ranges+=("$start:$end")
  fi
  start=$(( end + 1 ))
done

# Configure OPENAI_* for qwen-code (source to set env in this shell)
if [[ -f "$SCRIPT_DIR/switch_openai_env.sh" ]]; then
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/switch_openai_env.sh" -s "$SERVER" -m "$MODEL" --provider "$LOCAL_PROVIDER_KIND"
else
  echo "Error: $SCRIPT_DIR/switch_openai_env.sh not found" >&2
  exit 1
fi

pids=()
for (( s=1; s<=${#shard_ranges[@]}; s++ )); do
  range=${shard_ranges[$s]}
  s_start=${range%%:*}
  s_end=${range##*:}
  # zsh array slice and join to CSV
  shard_list=${(j:,:)${(@)EX_LIST[$s_start,$s_end]}}
  shard_dir="$BENCH_ROOT/${RUN_ID}-p${s}-exercism-typescript"
  log_file="$LOG_DIR/shard-${s}.log"

  (
    set -euo pipefail
    echo "[shard $s] Preparing workspace: $shard_dir" | tee "$log_file"
    rsync -a --exclude='.git' "$REPO_ROOT/exercism-typescript/" "$shard_dir/"
    (
      cd "$shard_dir"
      git init -q
      git add -A
      git commit -q -m "baseline" || true
    )

    # Pre-warm each exercise environment and add missing peer deps
    IFS=',' read -A _EXS <<< "$shard_list"
    for ex in ${_EXS[@]}; do
      exdir="$shard_dir/exercises/practice/$ex"
      if [[ -d "$exdir" ]]; then
        echo "[shard $s] Preparing exercise deps: $ex" | tee -a "$log_file"
        (
          cd "$exdir"
          corepack enable >/dev/null 2>&1 || true
          corepack yarn >/dev/null 2>&1 || true
          # Ensure @babel/core for babel-jest peer requirement
          if ! node -e 'try{const p=require("./package.json");process.exit(p.devDependencies&&p.devDependencies["@babel/core"]?0:1)}catch{process.exit(1)}'; then
            corepack yarn add -D @babel/core@^7 >/dev/null 2>&1 || true
          fi
        )
        # Commit prewarm changes so later git reset keeps them
        (
          cd "$shard_dir"
          git add "exercises/practice/$ex/package.json" \
                  "exercises/practice/$ex/yarn.lock" 2>/dev/null || true
          git commit -q -m "prep($ex): add @babel/core" || true
        )
      fi
    done

    echo "[shard $s] Running: $shard_list" | tee -a "$log_file"
    (
      cd "$REPO_ROOT"
      exercism_rel=".benchwork/${RUN_ID}-p${s}-exercism-typescript"
      bun "$REPO_ROOT/src/index.ts" \
        --exercism-path "$exercism_rel" \
        --agent "$AGENT" \
        --provider "$CLI_PROVIDER" \
        --model "$MODEL" \
        --exercise "$shard_list" \
        ${USE_DOCKER:+--docker} \
        --show-progress \
        --verbose \
        --timeout "$TIMEOUT_SEC" \
        ${PASS_THROUGH_ARGS[@]:-} \
        2>&1 | tee -a "$log_file"
    )
  ) &
  pids+=( $! )
done

fail=0
idx=1
for pid in ${pids[@]}; do
  if ! wait "$pid"; then
    echo "Shard $idx failed." >&2
    fail=1
  else
    echo "Shard $idx completed."
  fi
  idx=$((idx+1))
done

echo "Logs: $LOG_DIR"
exit $fail
