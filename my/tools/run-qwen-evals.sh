#!/bin/zsh

set -euo pipefail

#
# run-qwen-evals.sh
#
# 1) Fetch model IDs from a local OpenAI-compatible server using get-api-models.sh
# 2) Filter Qwen models (by regex, default: /qwen/i)
# 3) For each model, invoke run-qwen-code-local.sh to run the benchmark
#
# Defaults target the host 'gamma' with provider 'lmstudio'.
# Unknown flags are forwarded to run-qwen-code-local.sh (e.g., --timeout, --exercise, --result-dir, --no-docker).
#
# Usage examples:
#   ./run-qwen-evals.sh                       # uses server=gamma, provider=lmstudio
#   ./run-qwen-evals.sh -s gamma --provider lmstudio
#   ./run-qwen-evals.sh --list-only           # just print matched models
#   ./run-qwen-evals.sh --limit 2 --dry-run   # show first 2 commands without running
#

usage() {
  cat <<'USAGE'
Usage:
  run-qwen-evals.sh [options] [-- ...pass-through-to-runner]

Options:
  -s, --server NAME         Server name (default: gamma)
  -p, --port NUM            Port for get-api-models (ignored if --provider is set)
  --provider KIND           One of: lmstudio, ollama, llamacpp, mlx (default: lmstudio)
  -l, --list FILE           Use explicit model list file (one model id per line). Skips discovery.
  --match REGEX             Regex to select models (default: qwen)
  --skip REGEX              Regex to exclude models (default: none)
  --limit N                 Limit number of models to run (default: unlimited)
  --list-only               Only list matched models and exit
  --dry-run                 Print commands but do not run
  --stop-on-failure         Stop at the first failing model
  -h, --help                Show this help

Notes:
  - Unknown flags after options are forwarded to run-qwen-code-local.sh.
  - Each selected model is invoked as:
      run-qwen-code-local.sh <model> <server> <provider> [pass-through args]
  - Default: --save-result is enabled by the runner.
  - The --parallel option is not supported; execution is sequential per model.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; }; }

GET_SCRIPT="$SCRIPT_DIR/get-api-models.sh"
RUN_SCRIPT="$SCRIPT_DIR/run-qwen-code-local.sh"
if [[ ! -x "$GET_SCRIPT" ]]; then
  echo "Error: $GET_SCRIPT not found or not executable" >&2
  exit 1
fi
if [[ ! -x "$RUN_SCRIPT" ]]; then
  echo "Error: $RUN_SCRIPT not found or not executable" >&2
  exit 1
fi

SERVER="gamma"
PROVIDER="lmstudio"
PORT=""
LIST_FILE=""
MATCH_REGEX="qwen"
SKIP_REGEX=""
LIMIT=0
LIST_ONLY=0
DRY_RUN=0
STOP_ON_FAILURE=0
PASS_THROUGH_ARGS=()

# Short options first
OPTIND=1
while getopts ":s:p:l:h" opt; do
  case "$opt" in
    s) SERVER="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    l) LIST_FILE="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Error: -$OPTARG requires an argument" >&2; usage; exit 1 ;;
    \?)
      # allow long opts after this
      break ;;
  esac
done

shift $((OPTIND - 1))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      [[ -n "${2:-}" ]] || { echo "Error: --server requires an argument" >&2; usage; exit 1; }
      SERVER="$2"; shift 2; continue ;;
    --server=*)
      SERVER="${1#*=}"; shift; continue ;;
    --port)
      [[ -n "${2:-}" ]] || { echo "Error: --port requires an argument" >&2; usage; exit 1; }
      PORT="$2"; shift 2; continue ;;
    --port=*)
      PORT="${1#*=}"; shift; continue ;;
    --provider)
      [[ -n "${2:-}" ]] || { echo "Error: --provider requires an argument" >&2; usage; exit 1; }
      PROVIDER="$2"; shift 2; continue ;;
    --provider=*)
      PROVIDER="${1#*=}"; shift; continue ;;
    --list)
      [[ -n "${2:-}" ]] || { echo "Error: --list requires an argument" >&2; usage; exit 1; }
      LIST_FILE="$2"; shift 2; continue ;;
    --list=*)
      LIST_FILE="${1#*=}"; shift; continue ;;
    --match|--models-regex)
      [[ -n "${2:-}" ]] || { echo "Error: $1 requires an argument" >&2; usage; exit 1; }
      MATCH_REGEX="$2"; shift 2; continue ;;
    --match=*|--models-regex=*)
      MATCH_REGEX="${1#*=}"; shift; continue ;;
    --skip|--skip-regex)
      [[ -n "${2:-}" ]] || { echo "Error: $1 requires an argument" >&2; usage; exit 1; }
      SKIP_REGEX="$2"; shift 2; continue ;;
    --skip=*|--skip-regex=*)
      SKIP_REGEX="${1#*=}"; shift; continue ;;
    --limit)
      [[ -n "${2:-}" ]] || { echo "Error: --limit requires an argument" >&2; usage; exit 1; }
      LIMIT="$2"; shift 2; continue ;;
    --limit=*)
      LIMIT="${1#*=}"; shift; continue ;;
    --list-only)
      LIST_ONLY=1; shift; continue ;;
    --dry-run)
      DRY_RUN=1; shift; continue ;;
    --stop-on-failure)
      STOP_ON_FAILURE=1; shift; continue ;;
    # --save-result is default-on in the runner; no special handling needed here
    --help|-h)
      usage; exit 0 ;;
    --)
      shift; PASS_THROUGH_ARGS+=( "$@" ); break ;;
    *)
      # Pass-through to runner (e.g., --timeout, --exercise, --result-dir)
      PASS_THROUGH_ARGS+=( "$1" ); shift ;;
  esac
done

# Validate port if provided
if [[ -n "$PORT" && ! "$PORT" == <-> ]]; then
  echo "Error: --port must be numeric (e.g., 1234)" >&2
  usage
  exit 1
fi

if (( LIST_ONLY == 0 )); then
  echo "Server:    $SERVER"
  echo "Provider:  $PROVIDER${PORT:+ (port $PORT for discovery)}"
  if [[ -n "$LIST_FILE" ]]; then
    echo "Source:    list-file ($LIST_FILE)"
  else
    echo "Filter:    match=/$MATCH_REGEX/i${SKIP_REGEX:+, skip=/$SKIP_REGEX/i}"
  fi
  echo "Limit:     ${LIMIT:-0}"
  [[ "$DRY_RUN" == "1" ]] && echo "Mode:      dry-run"
fi

typeset -a FILTERED
FILTERED=()

if [[ -n "$LIST_FILE" ]]; then
  # Use explicit list file; ignore discovery and regex filters
  if [[ ! -f "$LIST_FILE" ]]; then
    echo "Error: list file not found: $LIST_FILE" >&2
    exit 1
  fi
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw%$'\r'}"
    # Trim leading/trailing whitespace
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    FILTERED+=( "$line" )
  done < "$LIST_FILE"
else
  # Build discovery command
  discovery=( "$GET_SCRIPT" -s "$SERVER" )
  if [[ -n "$PROVIDER" ]]; then
    discovery+=( --provider "$PROVIDER" )
  elif [[ -n "$PORT" ]]; then
    discovery+=( -p "$PORT" )
  fi

  # Retrieve models
  set +e
  resp=$(${=discovery} 2>&1)
  disc_rc=$?
  set -e
  if (( disc_rc != 0 )); then
    echo "Error: model discovery failed (exit $disc_rc)" >&2
    echo "$resp" >&2
    exit $disc_rc
  fi

  # Filter Qwen models
  typeset -a MODELS
  MODELS=()
  while IFS=$'\n' read -r line; do
    id="${line//$'\r'/}"
    [[ -z "$id" ]] && continue
    if ! echo "$id" | egrep -qi -- "$MATCH_REGEX"; then
      continue
    fi
    if [[ -n "$SKIP_REGEX" ]] && echo "$id" | egrep -qi -- "$SKIP_REGEX"; then
      continue
    fi
    MODELS+=( "$id" )
  done <<< "$resp"

  # De-duplicate while preserving order
  typeset -A SEEN
  for m in "${MODELS[@]}"; do
    if [[ -z "${SEEN[$m]:-}" ]]; then
      SEEN[$m]=1
      FILTERED+=( "$m" )
    fi
  done
fi

if (( ${#FILTERED[@]} == 0 )); then
  echo "No models matched regex: $MATCH_REGEX" >&2
  exit 1
fi

if (( LIMIT > 0 )) && (( LIMIT < ${#FILTERED[@]} )); then
  FILTERED=( ${FILTERED[1,$LIMIT]} )
fi

if (( LIST_ONLY == 1 )); then
  for m in "${FILTERED[@]}"; do
    echo "$m"
  done
  exit 0
else
  echo "Matched models (${#FILTERED[@]}):"
  for m in "${FILTERED[@]}"; do
    echo "  - $m"
  done
fi

ok_models=()
fail_models=()
idx=1
total=${#FILTERED[@]}

for model in "${FILTERED[@]}"; do
  echo "\n=== [$idx/$total] Running model: $model ==="
  cmd=( "$RUN_SCRIPT" "$model" "$SERVER" "$PROVIDER" ${PASS_THROUGH_ARGS[@]:-} )
  echo "> ${=cmd}"
  if (( DRY_RUN == 1 )); then
    ok_models+=( "$model" )
    idx=$((idx+1))
    continue
  fi

  set +e
  "${cmd[@]}"
  run_status=$?
  set -e
  if (( run_status == 0 )); then
    ok_models+=( "$model" )
  else
    echo "Model failed: $model (exit $run_status)" >&2
    fail_models+=( "$model" )
    if (( STOP_ON_FAILURE == 1 )); then
      break
    fi
  fi
  idx=$((idx+1))
done

echo "\nSummary:"
echo "  Succeeded: ${#ok_models[@]}"
for m in "${ok_models[@]:-}"; do
  echo "    - $m"
done
echo "  Failed:    ${#fail_models[@]}"
for m in "${fail_models[@]:-}"; do
  echo "    - $m"
done

(( ${#fail_models[@]} == 0 )) || exit 1
exit 0
