#!/bin/zsh

# EXPERIMENTAL NOTICE (LM Studio proxy path)
# ---------------------------------------------------------------
# This script includes an opt-in compatibility path for LM Studio
# behind the flag: --enable-proxy-for-lmstudio.
# The proxy attempts to normalize request bodies (e.g. embeddings/
# responses input arrays) but may still have issues. Results and
# behavior can differ from OpenAI's API semantics.
# Use at your own discretion and monitor logs/proxy.out.log.

set -euo pipefail

# ts-bench runner for Codex agent.
# - Default provider: openai (model forced to gpt-5)
# - If provider != openai (lmstudio/ollama/llamacpp/mlx),
#   use my/tools/switch_openai_env.sh to set OPENAI_* for an OpenAI-compatible local server
# - Clones exercism-typescript into .benchwork/<run-id>-exercism-typescript via rsync
# - Initializes a tiny git repo inside the clone for agent workflows
# - Runs all selected exercises sequentially (parallel option removed)
# - NOTE: Does NOT use --docker (Codex does not behave correctly in Docker here)
#
# Usage:
#   ./run-codex.sh [<model>] [<server>] [<provider>] [--timeout SEC] [--exercise <name|a,b,c>] [--enable-proxy-for-lmstudio]
# Examples:
#   ./run-codex.sh                 # defaults to provider=openai, model forced to gpt-5
#   ./run-codex.sh gpt-4o-mini     # provider=openai, model forced to gpt-5 (as required)
#   ./run-codex.sh gpt-oss-20b localhost lmstudio --exercise two-fer
#   ./run-codex.sh gpt-oss:120b beta ollama --exercise raindrops --timeout 1200

DEFAULT_MODEL="gpt-5"  # Effective default becomes gpt-5 when provider=openai
DEFAULT_SERVER=""
DEFAULT_PROVIDER="openai"  # openai | lmstudio | ollama | llamacpp | mlx

AGENT="codex"
# Provider passed to the Node CLI
# - openai: cloud mode
# - local:  any non-openai provider (lmstudio/ollama/llamacpp/mlx)
CLI_PROVIDER="openai"

print_help() {
  cat <<EOF
Usage:
  ./run-codex.sh [<model>] [<server>] [<provider>] [options]

Positional args (optional):
  model     Default: ${DEFAULT_MODEL} (ignored when provider=openai; gpt-5 is forced)
  server    Default: localhost when provider!=openai (ignored for openai)
  provider  Default: ${DEFAULT_PROVIDER} (openai|lmstudio|ollama|llamacpp|mlx)

Options:
  -h, --help                Show this help and exit
  --timeout SEC             Per-exercise timeout in seconds (default: 600)
  --exercise name|a,b,c     Run only the specified exercise(s). When omitted, TOP_25_EXERCISES are used.
  --enable-proxy-for-lmstudio  Allow LM Studio runs via a local compatibility proxy (see my/doc/codex-lmstudio-issue.md)
  --                        End of options; remaining args passed through to bun

Defaults added by this wrapper:
  --save-result             Enabled (results saved automatically)
  --show-progress           Enabled
  --verbose                 Enabled
  --exercism-path           Set to .benchwork/<run-id>-exercism-typescript

Notes:
  - Unknown flags are forwarded to bun (e.g., --result-dir, --result-name).
  - When provider=openai, --model is set to gpt-5 (as required).
  - When provider!=openai, OPENAI_* env vars are set via switch_openai_env.sh (OpenAI-compatible local server).
  - Docker is not used for Codex; no --docker flag is attached.
  - IMPORTANT: lmstudio provider is blocked by default due to API incompatibility with Codex.
               Add --enable-proxy-for-lmstudio to run via a local compatibility proxy.
               Details: my/doc/codex-lmstudio-issue.md. Otherwise use provider=ollama.

Examples:
  ./run-codex.sh
  ./run-codex.sh gpt-oss-20b beta lmstudio --timeout 900 --exercise two-fer,raindrops
  ./run-codex.sh gpt-oss:120b gamma ollama --timeout 1200 --exercise raindrops
EOF
}

# Show help early if requested (before consuming positional args)
for a in "$@"; do
  case "$a" in
    --)
      break ;;
    -h|--help)
      print_help
      exit 0
      ;;
  esac
done

MODEL=${1:-$DEFAULT_MODEL}
SERVER=${2:-$DEFAULT_SERVER}
PROVIDER=${3:-$DEFAULT_PROVIDER}
shift || true
shift || true
shift || true

TIMEOUT_SEC=600
EXERCISE=""
EXERCISE_SPECIFIED=0
PASS_THROUGH_ARGS=()
ENABLE_LMSTUDIO_PROXY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      TIMEOUT_SEC="${2:-$TIMEOUT_SEC}"; shift 2 ;;
    --timeout=*)
      TIMEOUT_SEC="${1#*=}"; shift ;;
    --exercise)
      EXERCISE="${2:-}"; EXERCISE_SPECIFIED=1; shift 2 ;;
    --exercise=*)
      EXERCISE="${1#*=}"; EXERCISE_SPECIFIED=1; shift ;;
    --enable-proxy-for-lmstudio)
      ENABLE_LMSTUDIO_PROXY=1; shift ;;
    --)
      shift; PASS_THROUGH_ARGS+=( "$@" ); break ;;
    *)
      # Keep unknown flags to pass through to bun (e.g., --save-result, --result-dir)
      PASS_THROUGH_ARGS+=( "$1" ); shift ;;
  esac
done

# Abort unless explicitly enabled for LM Studio
if [[ "$PROVIDER" == "lmstudio" && "$ENABLE_LMSTUDIO_PROXY" != "1" ]]; then
  echo "WARNING: provider=lmstudio is blocked by default due to Codex API incompatibility." >&2
  echo "Add --enable-proxy-for-lmstudio to run via a local compatibility proxy." >&2
  echo "Details: my/doc/codex-lmstudio-issue.md. Otherwise use provider=ollama." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BENCH_ROOT="$REPO_ROOT/.benchwork"
mkdir -p "$BENCH_ROOT"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; }; }
require_cmd rsync
require_cmd bun

# Exercism dataset must exist
PRACTICE_DIR="$REPO_ROOT/exercism-typescript/exercises/practice"
if [[ ! -d "$PRACTICE_DIR" ]]; then
  echo "Error: $PRACTICE_DIR not found." >&2
  echo "  Initialize submodule: git submodule update --init --recursive" >&2
  echo "  or run: $REPO_ROOT/my/tools/reset-exercism-typescript.sh" >&2
  exit 1
fi

# Compute exercise list for run (only if explicitly specified)
EXERCISE_CSV=""
if [[ "$EXERCISE_SPECIFIED" == "1" ]]; then
  EXERCISE_CSV="$EXERCISE"
fi

# Default server handling for local providers
if [[ "$PROVIDER" != "openai" && -z "$SERVER" ]]; then
  SERVER="localhost"
fi

timestamp=$(date +%Y%m%d-%H%M%S)

# Sanitize a string for safe filesystem path segments (replace special chars and spaces with '-')
sanitize_segment() {
  echo "$1" | sed -E 's/[\\/:*?"<>|[:space:]]+/-/g; s/-+/-/g; s/^-//; s/-$//'
}

# Include server segment in RUN_ID when provider!=openai
SERVER_SEG="${SERVER:-none}"
RUN_ID_RAW="${AGENT}-${MODEL}-${PROVIDER}-${SERVER_SEG}-${timestamp}"
RUN_ID="$(sanitize_segment "$RUN_ID_RAW")"
LOG_DIR="$BENCH_ROOT/$RUN_ID/logs"
mkdir -p "$LOG_DIR"
export BENCH_RUN_ID="$RUN_ID"

echo "Agent:     $AGENT"
echo "Provider:  $PROVIDER (CLI provider: $CLI_PROVIDER)"
echo "Model:     $MODEL"
echo "Server:    $SERVER"
echo "Timeout:   $TIMEOUT_SEC s"
echo "Run ID:    $RUN_ID"

# Environment setup for local provider (OpenAI-compatible server)
if [[ "$PROVIDER" != "openai" ]]; then
  # Map to Node CLI provider:
  # - ollama -> local (use Codex --oss mode)
  # - lmstudio/llamacpp/mlx -> openai (use OpenAI-compatible mode)
  if [[ "$PROVIDER" == "ollama" ]]; then
    CLI_PROVIDER="local"
  else
    CLI_PROVIDER="openai"
  fi
  if [[ -f "$SCRIPT_DIR/switch_openai_env.sh" ]]; then
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/switch_openai_env.sh" -s "$SERVER" -m "$MODEL" --provider "$PROVIDER"
  else
    echo "Error: $SCRIPT_DIR/switch_openai_env.sh not found" >&2
    exit 1
  fi
  if [[ "$PROVIDER" == "ollama" ]]; then
    echo "Ollama OSS Base: ${OLLAMA_BASE_URL:-'(unset)'} (CODEX_OSS_BASE_URL=${CODEX_OSS_BASE_URL:-'(unset)'})"
  else
    echo "Base URL:  ${OPENAI_BASE_URL:-'(unset)'}"
  fi
fi

# Prepare single workspace and run sequentially

# Decide prewarm list:
# - If --exercise was specified, prewarm that list
# - Otherwise, prewarm TOP_25_EXERCISES from src/config/constants.ts
PREWARM_CSV=""
if [[ "$EXERCISE_SPECIFIED" == "1" ]]; then
  PREWARM_CSV="$EXERCISE_CSV"
else
  if [[ -f "$REPO_ROOT/src/config/constants.ts" ]]; then
    PREWARM_CSV=$(sed -n "s/^[[:space:]]*export const TOP_25_EXERCISES = '\(.*\)';[[:space:]]*$/\1/p" "$REPO_ROOT/src/config/constants.ts")
  fi
fi

IFS=',' read -A PREWARM_LIST <<< "$PREWARM_CSV"

workspace_dir="$BENCH_ROOT/${RUN_ID}-exercism-typescript"
log_file="$LOG_DIR/run.log"

# warmup chat endpoint
if [[ "$PROVIDER" != "openai" ]]; then
  # Optional LM Studio compatibility proxy to normalize /v1/embeddings payloads
  if [[ "$PROVIDER" == "lmstudio" && "$ENABLE_LMSTUDIO_PROXY" == "1" ]]; then
    # Derive target base without trailing /v1
    TARGET_BASE="${OPENAI_BASE_URL%/v1}"
    PROXY_PORT="61234"
    echo "Starting LM Studio compatibility proxy on :$PROXY_PORT -> $TARGET_BASE" | tee -a "$log_file"
    (PROXY_TARGET_BASE="$TARGET_BASE" PROXY_LISTEN_PORT="$PROXY_PORT" PROXY_VERBOSE=1 bun "$SCRIPT_DIR/openai_compat_proxy.ts" >"$LOG_DIR/proxy.out.log" 2>&1 & echo $! >"$LOG_DIR/proxy.pid")
    sleep 1
    if ! kill -0 "$(cat "$LOG_DIR/proxy.pid" 2>/dev/null)" 2>/dev/null; then
      echo "Failed to start proxy; aborting LM Studio run." | tee -a "$log_file"
      exit 3
    else
      export OPENAI_BASE_URL="http://127.0.0.1:${PROXY_PORT}/v1"
      echo "OPENAI_BASE_URL overridden to $OPENAI_BASE_URL (via proxy)" | tee -a "$log_file"
    fi
  fi

  if [[ "$PROVIDER" == "ollama" ]]; then
    base_ollama="${OLLAMA_BASE_URL:-${CODEX_OSS_BASE_URL%/v1}}"
    echo "Warming up Ollama endpoint at $SERVER (${base_ollama}) ..."
    # Lightweight health check for Ollama
    curl -sS --max-time 5 "${base_ollama}/api/version" >/dev/null \
      || curl -sS --max-time 5 "${base_ollama}/api/tags" >/dev/null \
      || {
        echo "Warmup failed (Ollama): $MODEL on $SERVER" | tee -a "$log_file"
        echo "  - Ensure 'ollama serve' is running on ${base_ollama}" | tee -a "$log_file"
        echo "  - Verify network name resolution to host" | tee -a "$log_file"
      }
    sleep 3
  else
    echo "Warming up chat endpoint at $SERVER (${OPENAI_BASE_URL}) ..."
    # POST {"model": "...", "messages": [{"role": "user", "content": "hi"}]}
    # Use curl, ignore errors, timeout 10s
    curl -sS --max-time 10 -H "Content-Type: application/json" -X POST "$OPENAI_BASE_URL/chat/completions" \
        -d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"."}],"max_tokens":1,"temperature":0}' >/dev/null \
        || {
          echo "Warmup failed: $MODEL on $SERVER" | tee -a "$log_file"
          echo "  - Check local LLM server is running (LM Studio/MLX/llamacpp)" | tee -a "$log_file"
          echo "  - Verify model name exists on the server" | tee -a "$log_file"
          echo "  - Endpoint should expose OpenAI-compatible /v1/chat/completions" | tee -a "$log_file"
        }
    sleep 10
  fi
fi

echo "Preparing workspace: $workspace_dir" | tee "$log_file"
rsync -a --exclude='.git' "$REPO_ROOT/exercism-typescript/" "$workspace_dir/"
(
  cd "$workspace_dir"
  git init -q
  git add -A
  git commit -q -m "baseline" || true
)

if [[ -n "$PREWARM_CSV" ]]; then
  # Pre-warm each exercise environment and add missing peer deps (limited set)
  for ex in ${PREWARM_LIST[@]}; do
    exdir="$workspace_dir/exercises/practice/$ex"
    if [[ -d "$exdir" ]]; then
      echo "Preparing exercise deps: $ex" | tee -a "$log_file"
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
        cd "$workspace_dir"
        git add "exercises/practice/$ex/package.json" \
                "exercises/practice/$ex/yarn.lock" 2>/dev/null || true
        git commit -q -m "prep($ex): add @babel/core" || true
      )
    fi
  done
else
  echo "No prewarm list resolved; skipping prewarm." | tee -a "$log_file"
fi

if [[ "$EXERCISE_SPECIFIED" == "1" ]]; then
  echo "Running: $EXERCISE_CSV" | tee -a "$log_file"
else
  echo "Running: default TOP_25_EXERCISES" | tee -a "$log_file"
fi

start_epoch=$(date +%s)
start_human=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Log start
{
  printf "### %s\n" "$MODEL"
  printf "Start: %s\n" "$start_human"
  printf "Server: %s\n" "$SERVER"
} >> "$log_file"

(
  cd "$REPO_ROOT"
  exercism_rel=".benchwork/${RUN_ID}-exercism-typescript"
  BUN_EXERCISE_ARGS=()
  if [[ "$EXERCISE_SPECIFIED" == "1" ]]; then
    BUN_EXERCISE_ARGS=( --exercise "$EXERCISE_CSV" )
  fi

  # Decide model to pass to CLI:
  # - provider=openai: force gpt-5 as requested
  # - provider=local: use provided MODEL (OPENAI_* env already set by switch_openai_env.sh)
  MODEL_TO_USE="$MODEL"
  if [[ "$PROVIDER" == "openai" ]]; then
    MODEL_TO_USE="gpt-5"
  fi

  bun "$REPO_ROOT/src/index.ts" \
    --exercism-path "$exercism_rel" \
    --agent "$AGENT" \
    --provider "$CLI_PROVIDER" \
    --model "$MODEL_TO_USE" \
    --result-name "$RUN_ID" \
    ${BUN_EXERCISE_ARGS[@]:-} \
    --save-result \
    --show-progress \
    --verbose \
    --timeout "$TIMEOUT_SEC" \
    ${PASS_THROUGH_ARGS[@]:-} \
    2>&1 | tee -a "$log_file"
)

end_epoch=$(date +%s)
end_human=$(date '+%Y-%m-%d %H:%M:%S %Z')
duration=$(( end_epoch - start_epoch ))
# Format duration as HH:MM:SS
hours=$(( duration / 3600 ))
mins=$(( (duration % 3600) / 60 ))
secs=$(( duration % 60 ))
duration_hms=$(printf '%02d:%02d:%02d' "$hours" "$mins" "$secs")

# Log end
{
  printf "End: %s\n" "$end_human"
  printf "Duration: %s\n\n" "$duration_hms"
} >> "$log_file"

echo "Logs: $LOG_DIR"

# Cleanup background proxy if started
if [[ -f "$LOG_DIR/proxy.pid" ]]; then
  PROXY_PID="$(cat "$LOG_DIR/proxy.pid" 2>/dev/null || echo '')"
  if [[ -n "$PROXY_PID" ]]; then
    kill "$PROXY_PID" 2>/dev/null || true
    rm -f "$LOG_DIR/proxy.pid" 2>/dev/null || true
  fi
fi
