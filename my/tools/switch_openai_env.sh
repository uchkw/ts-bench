#!/bin/zsh

#
# OPENAI Environment Variable Switch Script
# -s for server name
# -p for port number (default: 1234)
# When --provider is specified, port setting is ignored
# and set as follows:
# lmstudio: 1234
# ollama: 11434
# llamacpp: 12345
# mlx: 12346
# -m for model name
#

# Note: This script sets environment variables, so please execute it as:
#       `source my/tools/switch_openai_env.sh ...`

usage() {
  cat <<'USAGE'
Usage:
  switch_openai_env.sh -s SERVER [-p PORT] -m MODEL
  switch_openai_env.sh -s SERVER -m MODEL [--provider PROVIDER]

Options:
  -s   Server name
  -p   Port number (default: 1234)
  -m   Model name
  --provider   Provider name
    lmstudio, ollama, llamacpp, mlx
  -h   Show this help
USAGE
}

server=""
port="1234"      # Default port
model_input=""
provider=""

OPTIND=1
while getopts ":s:p:m:h" opt; do
  case "$opt" in
    s) server="$OPTARG" ;;
    p) port="$OPTARG" ;;
    m) model_input="$OPTARG" ;;
    h) usage; return 0 ;;
    :) echo "Error: -$OPTARG requires an argument" >&2; usage; return 1 ;;
    \?)
      # Allow long options (e.g., --provider) to be parsed later
      # by breaking out of getopts loop without failing.
      break ;;
  esac
done

# Process long options (--provider) from remaining arguments
shift $((OPTIND - 1))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      if [[ -n "${2:-}" ]]; then
        provider="$2"
        shift 2
        continue
      else
        echo "Error: --provider requires an argument" >&2; usage; return 1
      fi
      ;;
    --provider=*)
      provider="${1#*=}"
      shift
      continue
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Error: invalid argument $1" >&2; usage; return 1
      ;;
  esac
done

if [[ -z "$server" ]]; then
  echo "Error: -s server name is required" >&2
  usage
  return 1
fi

if [[ -z "$model_input" ]]; then
  echo "Error: -m model name is required" >&2
  usage
  return 1
fi

# Override port when provider is specified (do nothing if not specified)
if [[ -n "$provider" ]]; then
  case "$provider" in
    lmstudio) port="1234" ;;
    ollama)   port="11434" ;;
    llamacpp) port="12345" ;;
    mlx)      port="12346" ;;
    *) echo "Error: Provider name must be one of lmstudio, ollama, llamacpp, mlx" >&2; usage; return 1 ;;
  esac
fi

# Port validity check (only numbers allowed)
if [[ ! "$port" == <-> ]]; then
  echo "Error: -p must specify a numeric port number (e.g., 1234)" >&2
  usage
  return 1
fi

# Determine hostname (localhost remains as is, don't append if already contains domain)
host="$server"
if [[ "$host" != *.* && "$host" != "localhost" ]]; then
  host="${host}.local"
fi

# Set environment variables (OpenAI-compatible base URL always uses /v1)
export OPENAI_MODEL="$model_input"
export OPENAI_BASE_URL="http://${host}:${port}/v1"
export OPENAI_API_KEY="sk-dummy"

# Codex --oss base (use OpenAI-compatible /v1 since Codex hits /chat/completions)
export CODEX_OSS_BASE_URL="http://${host}:${port}/v1"
export CODEX_OSS_PORT="$port"

# For Ollama warmup (/api/*) also expose base without /v1
if [[ "$provider" == "ollama" ]]; then
  export OLLAMA_BASE_URL="http://${host}:${port}"
fi

echo "Switched:"
echo "  OPENAI_MODEL       = ${OPENAI_MODEL}"
echo "  OPENAI_BASE_URL    = ${OPENAI_BASE_URL}"
echo "  OPENAI_API_KEY     = ${OPENAI_API_KEY}"
echo "  CODEX_OSS_BASE_URL = ${CODEX_OSS_BASE_URL}"
echo "  CODEX_OSS_PORT     = ${CODEX_OSS_PORT}"
if [[ -n "${OLLAMA_BASE_URL:-}" ]]; then
  echo "  OLLAMA_BASE_URL     = ${OLLAMA_BASE_URL}"
fi
