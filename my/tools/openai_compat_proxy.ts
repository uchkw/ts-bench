// EXPERIMENTAL / IN-PROGRESS:
// This proxy is a temporary workaround to improve LM Studio compatibility with Codex CLI.
// It may still have issues and does not guarantee identical semantics to OpenAI's API.
// Use only with `--enable-proxy-for-lmstudio` and monitor proxy.out.log for behavior.
//
// Lightweight OpenAI API compatibility proxy for LM Studio
// - Normalizes request bodies for endpoints that may receive array inputs from Codex
//   (e.g., /v1/embeddings, /v1/responses). Arrays are converted into a single string.
// - Pass-through for all other routes.
//
// Env vars:
//   PROXY_TARGET_BASE   (required) e.g. http://beta.local:1234
//   PROXY_LISTEN_PORT   (optional) default: 61234
//   PROXY_VERBOSE       (optional) "1" to log requests

type Json = Record<string, unknown>;

const targetBase = process.env.PROXY_TARGET_BASE;
if (!targetBase) {
  console.error("[proxy] PROXY_TARGET_BASE is required (e.g., http://beta.local:1234)");
  process.exit(1);
}

const listenPort = Number(process.env.PROXY_LISTEN_PORT || 61234);

function joinUrl(base: string, pathAndQuery: string): string {
  const baseUrl = base.endsWith('/') ? base.slice(0, -1) : base;
  const suffix = pathAndQuery.startsWith('/') ? pathAndQuery : `/${pathAndQuery}`;
  return `${baseUrl}${suffix}`;
}

function matchPath(pathname: string, bases: string[]): boolean {
  return bases.some((p) => pathname === p || pathname.startsWith(p + '/'));
}

function shouldNormalizeInput(pathname: string): boolean {
  // Normalize input for embeddings and responses endpoints
  return (
    matchPath(pathname, ['/v1/embeddings', '/embeddings']) ||
    matchPath(pathname, ['/v1/responses', '/responses'])
  );
}

function toStringInputArray(arr: any[]): string {
  const mapped = arr.map((item) => {
    if (typeof item === 'string') return item;
    if (item && typeof item === 'object' && 'text' in item && typeof (item as any).text === 'string') {
      return (item as any).text as string;
    }
    try { return JSON.stringify(item); } catch { return String(item); }
  });
  return mapped.join('\n');
}

async function handleNormalizeInput(req: Request, targetUrl: string, verbose: boolean): Promise<Response> {
  try {
    const contentType = req.headers.get('content-type') || '';
    if (!contentType.includes('application/json')) {
      // Non-JSON -> just pass through
      if (verbose) console.log(`[proxy] pass-through (non-json) ${req.method} ${new URL(req.url).pathname}`);
      return fetch(targetUrl, {
        method: req.method,
        headers: req.headers,
        body: req.body,
      });
    }

    const data = (await req.json()) as Json;
    let input = (data as any)?.input;
    let changed = false;
    if (Array.isArray(input)) {
      // Convert array input to single string (join by newline)
      (data as any).input = toStringInputArray(input);
      changed = true;
    } else if (input != null && typeof input !== 'string') {
      try {
        (data as any).input = JSON.stringify(input);
      } catch {
        (data as any).input = String(input);
      }
      changed = true;
    } else if (input == null && Array.isArray((data as any).inputs)) {
      // Some clients might use `inputs`
      (data as any).input = toStringInputArray((data as any).inputs as any[]);
      delete (data as any).inputs;
      changed = true;
    }

    if (verbose) console.log(`[proxy] input normalized=${changed}`);

    const headers = new Headers(req.headers);
    headers.delete('content-length');

    return fetch(targetUrl, {
      method: req.method,
      headers,
      body: JSON.stringify(data),
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    });
  }
}

const server = Bun.serve({
  port: listenPort,
  async fetch(req) {
    const url = new URL(req.url);
    const pathAndQuery = url.pathname + url.search;
    const targetUrl = joinUrl(targetBase!, pathAndQuery);
    const verbose = process.env.PROXY_VERBOSE === '1';
    if (verbose) console.log(`[proxy] ${req.method} ${url.pathname}`);

    // Normalize `input` for embeddings/responses endpoints
    if (req.method === 'POST' && shouldNormalizeInput(url.pathname)) {
      return handleNormalizeInput(req, targetUrl, verbose);
    }

    // Pass-through for the rest
    const headers = new Headers(req.headers);
    return fetch(targetUrl, {
      method: req.method,
      headers,
      body: req.body,
    });
  },
});

console.log(`[proxy] OpenAI compat proxy listening on http://127.0.0.1:${listenPort}`);
console.log(`[proxy] Forwarding to ${targetBase}`);
