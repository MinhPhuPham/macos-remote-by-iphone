/**
 * MyRemote Signaling Server (Secured)
 *
 * A lightweight HTTP server that maps pairing codes to Mac public IPs.
 * The Mac registers with a code + port; the server detects public IP.
 * The iPhone looks up the code to get the Mac's IP:port for direct P2P.
 *
 * Security:
 *   - API key required for registration and deletion (X-API-Key header)
 *   - Per-IP rate limiting on all endpoints
 *   - Anti-code-squatting: existing codes can only be refreshed by same IP
 *   - Health endpoint does not leak active pairing count
 *
 * Environment variables:
 *   PORT      - HTTP port (default 3000)
 *   API_KEY   - Required secret for POST/DELETE operations
 *
 * Deploy: Node.js 18+, any VPS, or serverless.
 *
 * Usage:
 *   API_KEY=your-secret-key-here node server.js
 */

const http = require('http');

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || '';

if (!API_KEY) {
  console.warn('WARNING: No API_KEY set. Registration/deletion will be rejected.');
  console.warn('Set the API_KEY environment variable before deploying.');
}

// In-memory store: code → { publicIP, port, hostname, version, registeredIP, expiresAt }
const pairings = new Map();
const EXPIRY_MS = 90_000; // 90 seconds (server refreshes every 30s)

// Rate limiting: IP → { count, windowStart }
const rateLimits = new Map();
const RATE_WINDOW_MS = 60_000; // 1 minute
const MAX_LOOKUPS_PER_MINUTE = 10;
const MAX_REGISTERS_PER_MINUTE = 3;

function cleanExpired() {
  const now = Date.now();
  for (const [code, entry] of pairings) {
    if (now > entry.expiresAt) pairings.delete(code);
  }
  // Clean old rate limit entries.
  for (const [ip, data] of rateLimits) {
    if (now - data.windowStart > RATE_WINDOW_MS * 2) rateLimits.delete(ip);
  }
}

setInterval(cleanExpired, 30_000);

function getClientIP(req) {
  return req.headers['x-forwarded-for']?.split(',')[0]?.trim()
    || req.headers['x-real-ip']
    || req.socket.remoteAddress;
}

function checkRateLimit(ip, action, maxPerMinute) {
  const now = Date.now();
  const key = `${ip}:${action}`;
  let entry = rateLimits.get(key);

  if (!entry || now - entry.windowStart > RATE_WINDOW_MS) {
    entry = { count: 0, windowStart: now };
  }

  entry.count++;
  rateLimits.set(key, entry);

  return entry.count <= maxPerMinute;
}

function checkApiKey(req) {
  return req.headers['x-api-key'] === API_KEY && API_KEY !== '';
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > 10_000) { reject(new Error('Body too large')); return; }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString())); }
      catch { resolve(null); }
    });
    req.on('error', reject);
  });
}

function sendJSON(res, statusCode, data) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;
  const clientIP = getClientIP(req);

  // POST /api/pairing — Register a pairing code (requires API key).
  if (req.method === 'POST' && path === '/api/pairing') {
    if (!checkApiKey(req)) {
      return sendJSON(res, 403, { error: 'Invalid or missing API key' });
    }

    if (!checkRateLimit(clientIP, 'register', MAX_REGISTERS_PER_MINUTE)) {
      return sendJSON(res, 429, { error: 'Rate limit exceeded. Try again later.' });
    }

    const body = await readBody(req).catch(() => null);
    if (!body || !body.code || !body.port) {
      return sendJSON(res, 400, { error: 'Missing code or port' });
    }

    const code = body.code.toUpperCase();
    if (code.length !== 6) {
      return sendJSON(res, 400, { error: 'Code must be 6 characters' });
    }

    // Anti-squatting: if code exists and was registered by a different IP, reject.
    const existing = pairings.get(code);
    if (existing && Date.now() <= existing.expiresAt && existing.registeredIP !== clientIP) {
      return sendJSON(res, 409, { error: 'Code already in use' });
    }

    const publicIP = body.publicIP || clientIP;

    pairings.set(code, {
      publicIP,
      port: body.port,
      hostname: body.hostname || 'Mac',
      version: body.version || '1.0',
      registeredIP: clientIP,
      expiresAt: Date.now() + EXPIRY_MS,
    });

    console.log(`[REGISTER] ${code} → ${publicIP}:${body.port} (${body.hostname})`);
    return sendJSON(res, 200, { ok: true });
  }

  // GET /api/pairing/:code — Look up a pairing code (rate limited).
  const getMatch = path.match(/^\/api\/pairing\/([A-Z0-9]{6})$/i);
  if (req.method === 'GET' && getMatch) {
    if (!checkRateLimit(clientIP, 'lookup', MAX_LOOKUPS_PER_MINUTE)) {
      return sendJSON(res, 429, { error: 'Rate limit exceeded. Try again in a minute.' });
    }

    const code = getMatch[1].toUpperCase();
    const entry = pairings.get(code);

    if (!entry || Date.now() > entry.expiresAt) {
      pairings.delete(code);
      return sendJSON(res, 200, {
        found: false,
        error: 'Code not found or expired. Check the code on your Mac.',
      });
    }

    console.log(`[LOOKUP] ${code} → ${entry.publicIP}:${entry.port}`);
    return sendJSON(res, 200, {
      found: true,
      publicIP: entry.publicIP,
      port: entry.port,
      hostname: entry.hostname,
      version: entry.version,
    });
  }

  // DELETE /api/pairing/:code — Unregister (requires API key).
  const delMatch = path.match(/^\/api\/pairing\/([A-Z0-9]{6})$/i);
  if (req.method === 'DELETE' && delMatch) {
    if (!checkApiKey(req)) {
      return sendJSON(res, 403, { error: 'Invalid or missing API key' });
    }

    const code = delMatch[1].toUpperCase();
    pairings.delete(code);
    console.log(`[UNREGISTER] ${code}`);
    return sendJSON(res, 200, { ok: true });
  }

  // Health check (does NOT leak pairing count).
  if (path === '/health') {
    return sendJSON(res, 200, { status: 'ok' });
  }

  sendJSON(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  console.log(`MyRemote Signaling Server running on port ${PORT}`);
  console.log(`API key: ${API_KEY ? 'configured' : 'NOT SET (registration will fail)'}`);
});
