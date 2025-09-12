#!/bin/zsh

set -euo pipefail

#
# get-api-models.sh
#
# Query an OpenAI-compatible server for available models via GET /v1/models.
# Server/port/provider handling mirrors my/tools/switch_openai_env.sh.
#
# Usage examples:
#   ./get-api-models.sh -s <hostname> --provider lmstudio
#   ./get-api-models.sh -s localhost -p 1234
#

usage() {
  cat <<'USAGE'
Usage:
  get-api-models.sh -s SERVER [-p PORT]
  get-api-models.sh -s SERVER [--provider PROVIDER]

Options:
  -s   Server name (e.g., <hostname>, localhost)
  -p   Port number (default: 1234; ignored if --provider is set)
  --provider   Provider kind to derive port
    lmstudio (1234), ollama (11434), llamacpp (12345), mlx (12346)
  -h   Show this help

Notes:
  - If SERVER has no dot and is not 'localhost', '.local' is appended.
  - Authorization uses OPENAI_API_KEY if set, otherwise 'sk-dummy'.
USAGE
}

server=""
port="1234"      # Default port
provider=""

OPTIND=1
while getopts ":s:p:h" opt; do
  case "$opt" in
    s) server="$OPTARG" ;;
    p) port="$OPTARG" ;;
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
    --provider)
      if [[ -n "${2:-}" ]]; then
        provider="$2"; shift 2; continue
      else
        echo "Error: --provider requires an argument" >&2; usage; exit 1
      fi ;;
    --provider=*)
      provider="${1#*=}"; shift; continue ;;
    --)
      shift; break ;;
    *)
      echo "Error: invalid argument $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$server" ]]; then
  echo "Error: -s server name is required" >&2
  usage
  exit 1
fi

# If provider is specified, override port (match switch_openai_env.sh)
if [[ -n "$provider" ]]; then
  case "$provider" in
    lmstudio) port="1234" ;;
    ollama)   port="11434" ;;
    llamacpp) port="12345" ;;
    mlx)      port="12346" ;;
    *) echo "Error: Provider must be one of: lmstudio, ollama, llamacpp, mlx" >&2; usage; exit 1 ;;
  esac
fi

# Validate port (digits only)
if [[ ! "$port" == <-> ]]; then
  echo "Error: -p must be a numeric port (e.g., 1234)" >&2
  usage
  exit 1
fi

# Determine try order for hostnames
api_key="${OPENAI_API_KEY:-sk-dummy}"
tries=()
if [[ "$server" == "localhost" ]]; then
  tries+=("localhost")
elif [[ "$server" == *.* ]]; then
  tries+=("$server")
else
  tries+=("${server}.local" "$server")
fi

last_exit=0
last_err=""
for host in "${tries[@]}"; do
  base_url="http://${host}:${port}"
  set +e
  resp=$(curl -sS \
    --connect-timeout 2 --max-time 10 \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    "${base_url}/v1/models" 2>&1)
  curl_exit=$?
  set -e

  if (( curl_exit == 0 )); then
    if command -v jq >/dev/null 2>&1; then
      echo "$resp" | jq -r 'def as_array: if type=="array" then . else [.] end; (.data // .) | as_array | .[] | (.id // .)'
    else
      echo "$resp" | sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p'
    fi
    exit 0
  fi

  last_exit=$curl_exit
  last_err=$resp
done

echo "Request failed (exit ${last_exit}) after trying: ${tries[*]}" >&2
echo "$last_err" >&2
exit $last_exit
