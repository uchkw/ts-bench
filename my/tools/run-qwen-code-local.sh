#!/bin/zsh

set -euo pipefail

# ts-bench runner for Qwen Code against a local-compatible provider.
# - Uses my/tools/switch_openai_env.sh to set OPENAI_* for qwen-code
# - Clones exercism-typescript into .benchwork/<run-id>-exercism-typescript via rsync
# - Initializes a tiny git repo inside the clone for agent workflows
# - Runs all selected exercises sequentially (parallel option removed)
#
# Usage:
#   ./run-qwen-code-local.sh <model> <server> <provider> [--timeout SEC] [--exercise <name|a,b,c>] [--docker-no-cache-build]
# Example:
#   ./run-qwen-code-local.sh qwen3-coder-30b-a3b-instruct-dwq-v2 gamma lmstudio

DEFAULT_MODEL="qwen3-coder-30b-a3b-instruct-dwq-v2"
DEFAULT_SERVER="localhost"
DEFAULT_LOCAL_PROVIDER_KIND="lmstudio"   # lmstudio | ollama | llamacpp | mlx

AGENT="qwen"
CLI_PROVIDER="local"                     # Important: set provider=local so qwen.ts loads OPENAI_* from env

print_help() {
  cat <<EOF
Usage:
  ./run-qwen-code-local.sh [<model>] [<server>] [<provider>] [options]

Positional args (optional):
  model     Default: ${DEFAULT_MODEL}
  server    Default: ${DEFAULT_SERVER}
  provider  Default: ${DEFAULT_LOCAL_PROVIDER_KIND} (lmstudio|ollama|llamacpp|mlx)

Options:
  -h, --help                Show this help and exit
  --timeout SEC             Per-exercise timeout in seconds (default: 600)
  --exercise name|a,b,c     Run only the specified exercise(s). When omitted, TOP_25_EXERCISES are used.
  --docker-no-cache-build   Rebuild Docker image without cache
  --no-docker               Run without Docker (default: Docker is enabled)
  --                        End of options; remaining args passed through to bun

Defaults added by this wrapper:
  --save-result             Enabled (results saved automatically)
  --show-progress           Enabled
  --verbose                 Enabled
  --docker                  Enabled (use --no-docker to disable)
  --exercism-path           Set to .benchwork/<run-id>-exercism-typescript

Notes:
  - Unknown flags are forwarded to bun (e.g., --result-dir, --result-name).
  - Workspace is prepared at .benchwork/<run-id>-exercism-typescript; logs in .benchwork/<run-id>/logs.
  - Results are saved by default (--save-result). Default dir: ./data/results

Examples:
  ./run-qwen-code-local.sh
  ./run-qwen-code-local.sh ${DEFAULT_MODEL} localhost lmstudio --timeout 900 --exercise two-fer,raindrops
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
LOCAL_PROVIDER_KIND=${3:-$DEFAULT_LOCAL_PROVIDER_KIND}
shift || true
shift || true
shift || true

TIMEOUT_SEC=600
EXERCISE=""
EXERCISE_SPECIFIED=0
DOCKER_NO_CACHE_BUILD=0
USE_DOCKER=1
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

RUN_ID_RAW="${AGENT}-${MODEL}-${LOCAL_PROVIDER_KIND}-${timestamp}"
RUN_ID="$(sanitize_segment "$RUN_ID_RAW")"
LOG_DIR="$BENCH_ROOT/$RUN_ID/logs"
mkdir -p "$LOG_DIR"

echo "Agent:     $AGENT"
echo "Provider:  $CLI_PROVIDER (local kind: $LOCAL_PROVIDER_KIND)"
echo "Model:     $MODEL"
echo "Server:    $SERVER"
echo "Timeout:   $TIMEOUT_SEC s"
echo "Run ID:    $RUN_ID"

# Configure OPENAI_* for qwen-code (source to set env in this shell)
if [[ -f "$SCRIPT_DIR/switch_openai_env.sh" ]]; then
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/switch_openai_env.sh" -s "$SERVER" -m "$MODEL" --provider "$LOCAL_PROVIDER_KIND"
else
  echo "Error: $SCRIPT_DIR/switch_openai_env.sh not found" >&2
  exit 1
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
if [[ -n "$SERVER" ]]; then
  echo "Warming up chat endpoint at $SERVER ..."
  # POST {"model": "...", "messages": [{"role": "user", "content": "hi"}]}
  # Use curl, ignore errors, timeout 10s
  curl -sS --max-time 100 -H "Content-Type: application/json" -X POST "$OPENAI_BASE_URL/chat/completions" -d "{\"model\":\"$OPENAI_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\".\"}],\"max_tokens\":1,\"temperature\":0}" >/dev/null || echo "Warmup failed: $MODEL on $SERVER" >> "$log_file"
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
  bun "$REPO_ROOT/src/index.ts" \
    --exercism-path "$exercism_rel" \
    --agent "$AGENT" \
    --provider "$CLI_PROVIDER" \
    --model "$MODEL" \
    ${BUN_EXERCISE_ARGS[@]:-} \
    ${USE_DOCKER:+--docker} \
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
