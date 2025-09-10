#!/bin/zsh

set -euo pipefail

# ts-bench runner for Codex agent.
# - Default provider: openai (model forced to gpt-5)
# - If provider=local, use my/tools/switch_openai_env.sh to set OPENAI_* for an OpenAI-compatible local server
# - Clones exercism-typescript into .benchwork/<run-id>-exercism-typescript via rsync
# - Initializes a tiny git repo inside the clone for agent workflows
# - Runs all selected exercises sequentially (parallel option removed)
# - NOTE: Does NOT use --docker (Codex does not behave correctly in Docker here)
#
# Usage:
#   ./run-codex.sh [<model>] [<server>] [<provider>] [--timeout SEC] [--exercise <name|a,b,c>]
# Examples:
#   ./run-codex.sh                 # defaults to provider=openai, model forced to gpt-5
#   ./run-codex.sh gpt-4o-mini     # provider=openai, model forced to gpt-5 (as required)
#   ./run-codex.sh qwen2.5 localhost local --exercise two-fer

DEFAULT_MODEL="gpt-5"  # Effective default becomes gpt-5 when provider=openai
DEFAULT_SERVER=""
DEFAULT_PROVIDER="openai"  # openai | lmstudio | ollama | llamacpp | mlx

AGENT="codex"
# For Codex, we always pass --provider openai to the CLI. When provider=local,
# we set OPENAI_* via switch_openai_env.sh so Codex talks to the local server.
CLI_PROVIDER="openai"

print_help() {
  cat <<EOF
Usage:
  ./run-codex.sh [<model>] [<server>] [<provider>] [options]

Positional args (optional):
  model     Default: ${DEFAULT_MODEL} (ignored when provider=openai; gpt-5 is forced)
  server    Default: ${DEFAULT_SERVER} (used only when provider!=openai)
  provider  Default: ${DEFAULT_PROVIDER} (openai|lmstudio|ollama|llamacpp|mlx)

Options:
  -h, --help                Show this help and exit
  --timeout SEC             Per-exercise timeout in seconds (default: 600)
  --exercise name|a,b,c     Run only the specified exercise(s). When omitted, TOP_25_EXERCISES are used.
  --                        End of options; remaining args passed through to bun

Defaults added by this wrapper:
  --save-result             Enabled (results saved automatically)
  --show-progress           Enabled
  --verbose                 Enabled
  --exercism-path           Set to .benchwork/<run-id>-exercism-typescript

Notes:
  - Unknown flags are forwarded to bun (e.g., --result-dir, --result-name).
  - When provider=openai, --model is set to gpt-5 (as required).
  - When provider=local, OPENAI_* env vars are set via switch_openai_env.sh.
  - Docker is not used for Codex; no --docker flag is attached.

Examples:
  ./run-codex.sh
  ./run-codex.sh ${DEFAULT_MODEL} localhost lmstudio --timeout 900 --exercise two-fer,raindrops
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
    --)
      shift; PASS_THROUGH_ARGS+=( "$@" ); break ;;
    *)
      # Keep unknown flags to pass through to bun (e.g., --save-result, --result-dir)
      PASS_THROUGH_ARGS+=( "$1" ); shift ;;
  esac
done

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

timestamp=$(date +%Y%m%d-%H%M%S)

# Sanitize a string for safe filesystem path segments (replace special chars and spaces with '-')
sanitize_segment() {
  echo "$1" | sed -E 's/[\\/:*?"<>|[:space:]]+/-/g; s/-+/-/g; s/^-//; s/-$//'
}

RUN_ID_RAW="${AGENT}-${MODEL}-${PROVIDER}-${timestamp}"
RUN_ID="$(sanitize_segment "$RUN_ID_RAW")"
LOG_DIR="$BENCH_ROOT/$RUN_ID/logs"
mkdir -p "$LOG_DIR"

echo "Agent:     $AGENT"
echo "Provider:  $PROVIDER (CLI provider: $CLI_PROVIDER)"
echo "Model:     $MODEL"
echo "Server:    $SERVER"
echo "Timeout:   $TIMEOUT_SEC s"
echo "Run ID:    $RUN_ID"

# Environment setup for local provider (openai-compatible server)
if [[ "$PROVIDER" != "openai" ]]; then
  if [[ -f "$SCRIPT_DIR/switch_openai_env.sh" ]]; then
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/switch_openai_env.sh" -s "$SERVER" -m "$MODEL" --provider "$PROVIDER"
  else
    echo "Error: $SCRIPT_DIR/switch_openai_env.sh not found" >&2
    exit 1
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
  echo "Warming up chat endpoint at $SERVER ..."
  # POST {"model": "...", "messages": [{"role": "user", "content": "hi"}]}
  # Use curl, ignore errors, timeout 10s
  curl -sS --max-time 10 -H "Content-Type: application/json" -X POST "$OPENAI_BASE_URL/chat/completions" \
      -d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"."}],"max_tokens":1,"temperature":0}' >/dev/null \
      || echo "Warmup failed: $MODEL on $SERVER" >> "$log_file"
  sleep 10
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
