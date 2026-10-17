import { Md5 } from 'ts-md5';

interface Env {
  LASTFM_API_KEY: string;
  LASTFM_API_SECRET: string;
  TELEMETRY_DB: D1Database;
}

const R2_BASE = 'https://pub-8a5464b225534730b481b262ffe4748b.r2.dev';
const CORS_HEADERS = { 'Access-Control-Allow-Origin': '*' };

function md5hex(input: string): string {
  return Md5.hashStr(input);
}

function buildSignature(params: Record<string, string>, secret: string): string {
  const keys = Object.keys(params)
    .filter(k => k !== 'format' && k !== 'callback')
    .sort();

  let str = '';
  for (const key of keys) str += key + params[key];
  str += secret;

  return md5hex(str);
}

// ── Telemetry ────────────────────────────────────────────────────────────────
// Schema (D1 `lastfm-telemetry`):
//   installs      (install_id PK, first_seen, last_seen, app_version)
//   counters      (name PK, value)
//   crash_reports (id, received_at, install_id, app_version, exception_type, message, stack_trace)

function isValidInstallId(id: unknown): id is string {
  return typeof id === 'string' && /^[a-f0-9]{32}$/i.test(id);
}

async function bumpCounter(db: D1Database, name: string, by: number): Promise<void> {
  await db
    .prepare(`INSERT INTO counters (name, value) VALUES (?, ?)
              ON CONFLICT(name) DO UPDATE SET value = value + ?`)
    .bind(name, by, by)
    .run();
}

async function handleTelemetry(request: Request, url: URL, env: Env): Promise<Response | null> {
  if (!url.pathname.startsWith('/telemetry/')) return null;
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  if (!isValidInstallId(body.installId)) {
    return new Response('Bad request', { status: 400 });
  }
  const installId  = body.installId;
  const appVersion = typeof body.appVersion === 'string' ? body.appVersion.slice(0, 32) : 'unknown';

  if (url.pathname === '/telemetry/ping') {
    const today = new Date().toISOString().slice(0, 10);
    await env.TELEMETRY_DB.batch([
      env.TELEMETRY_DB
        .prepare(
          `INSERT INTO installs (install_id, first_seen, last_seen, app_version)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(install_id) DO UPDATE SET last_seen = excluded.last_seen, app_version = excluded.app_version`,
        )
        .bind(installId, today, today, appVersion),
      env.TELEMETRY_DB.prepare(
        `INSERT INTO counters (name, value) VALUES ('ping_total', 1)
         ON CONFLICT(name) DO UPDATE SET value = value + 1`,
      ),
    ]);
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (url.pathname === '/telemetry/scrobble') {
    const count =
      typeof body.count === 'number' && Number.isInteger(body.count) && body.count > 0
        ? Math.min(body.count, 1000)
        : 1;
    await bumpCounter(env.TELEMETRY_DB, 'scrobble_total', count);
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (url.pathname === '/telemetry/crash') {
    const exceptionType = typeof body.exceptionType === 'string' ? body.exceptionType.slice(0, 200) : 'Unknown';
    const message       = typeof body.message === 'string' ? body.message.slice(0, 2000) : '';
    const stackTrace    = typeof body.stackTrace === 'string' ? body.stackTrace.slice(0, 8000) : '';
    await env.TELEMETRY_DB
      .prepare(
        `INSERT INTO crash_reports (received_at, install_id, app_version, exception_type, message, stack_trace)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind(new Date().toISOString(), installId, appVersion, exceptionType, message, stackTrace)
      .run();
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  return new Response('Not found', { status: 404 });
}

// ── Worker ───────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // GET /lastfm-scrobbler/* → proxy to R2. Some networks (corporate
    // firewalls, SSL-inspecting AVs) block *.r2.dev directly, but reach
    // this worker fine because it's served from a custom domain.
    if (request.method === 'GET' && url.pathname.startsWith('/lastfm-scrobbler/')) {
      const upstream = await fetch(`${R2_BASE}${url.pathname}${url.search}`);
      const headers  = new Headers(upstream.headers);
      headers.set('Access-Control-Allow-Origin', '*');
      if (url.pathname.endsWith('.json')) {
        headers.set('Cache-Control', 'no-cache, no-store, max-age=0');
      }
      return new Response(upstream.body, { status: upstream.status, headers });
    }

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    const telemetryResponse = await handleTelemetry(request, url, env);
    if (telemetryResponse) return telemetryResponse;

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    let formData: FormData;
    try {
      formData = await request.formData();
    } catch {
      return new Response('Bad request: expected form data', { status: 400 });
    }

    const params: Record<string, string> = {};
    let sign = false;

    for (const [key, value] of formData.entries()) {
      if (key === '_sign') {
        sign = value === '1';
        continue;
      }
      params[key] = value.toString();
    }

    params['api_key'] = env.LASTFM_API_KEY;

    if (sign) {
      params['api_sig'] = buildSignature(params, env.LASTFM_API_SECRET);
    }

    params['format'] = 'json';

    const body = new URLSearchParams(params);
    const upstream = await fetch('https://ws.audioscrobbler.com/2.0/', {
      method: 'POST',
      body,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });

    const json = await upstream.json() as Record<string, unknown>;

    // Inject the full auth URL so the C# client never needs to know the api_key
    if (params['method'] === 'auth.getToken' && typeof json['token'] === 'string') {
      json['_authUrl'] = `https://www.last.fm/api/auth/?api_key=${env.LASTFM_API_KEY}&token=${json['token']}`;
    }

    return Response.json(json, {
      headers: { 'Access-Control-Allow-Origin': '*' },
    });
  },
};
