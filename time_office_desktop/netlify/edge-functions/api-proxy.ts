/**
 * Netlify Edge Function: API Proxy with Automatic Failover
 *
 * Intercepts all /api/* requests from the browser and proxies them
 * to the backend servers. Tries primary first, falls back to secondary.
 *
 * Backend candidates (in priority order):
 *   1. http://115.244.240.22:8084  (Public Primary)
 *   2. http://182.66.233.66:8084   (Public Secondary)
 */

const BACKENDS = [
  'http://182.66.233.66:8084',   // Primary public IP
  'http://115.244.240.22:8084',  // Secondary / fallback
];

const TIMEOUT_MS = 6000;

export default async (request: Request): Promise<Response> => {
  const url = new URL(request.url);
  const apiPath = url.pathname + url.search; // e.g. /api/time-office/dashboard?date=2026-09-26

  // Forward all original headers except host
  const forwardHeaders = new Headers(request.headers);
  forwardHeaders.delete('host');

  // Try each backend in order
  for (let i = 0; i < BACKENDS.length; i++) {
    const targetUrl = `${BACKENDS[i]}${apiPath}`;

    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

      const body =
        request.method !== 'GET' && request.method !== 'HEAD'
          ? await request.clone().arrayBuffer()
          : undefined;

      const backendRes = await fetch(targetUrl, {
        method: request.method,
        headers: forwardHeaders,
        body,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      // Add CORS headers so browser is happy
      const responseHeaders = new Headers(backendRes.headers);
      responseHeaders.set('Access-Control-Allow-Origin', '*');
      responseHeaders.set('X-Proxied-Backend', BACKENDS[i]);
      responseHeaders.set('X-Backend-Index', String(i));

      return new Response(backendRes.body, {
        status: backendRes.status,
        statusText: backendRes.statusText,
        headers: responseHeaders,
      });
    } catch (err) {
      console.warn(`[Edge Proxy] Backend ${i + 1} (${BACKENDS[i]}) failed:`, err);
      // Try next backend
      if (i === BACKENDS.length - 1) {
        // All backends exhausted
        return new Response(
          JSON.stringify({
            error: 'All backend servers are currently unreachable.',
            tried: BACKENDS,
          }),
          {
            status: 503,
            headers: {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          }
        );
      }
    }
  }

  // Should never reach here
  return new Response('Proxy error', { status: 500 });
};

// Only intercept /api/* paths
export const config = {
  path: '/api/*',
};
