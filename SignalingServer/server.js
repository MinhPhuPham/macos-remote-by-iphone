/**
 * MyRemote Signaling Server
 *
 * A lightweight HTTP server that acts as a "phone book" for pairing codes.
 * The Mac registers its pairing code + port, the server detects the public IP
 * from the request. The iPhone looks up the code to get the Mac's IP:port.
 *
 * Traffic never flows through this server — it's signaling only.
 * All video/input data goes directly iPhone ↔ Mac (P2P).
 *
 * Endpoints:
 *   POST /api/pairing        — Register/refresh a pairing code
 *   GET  /api/pairing/:code  — Look up a pairing code
 *   DELETE /api/pairing/:code — Unregister a pairing code
 *
 * Deploy: Node.js 18+, any VPS ($5/mo is plenty), or serverless (Vercel, etc.)
 *
 * Usage:
 *   node server.js                    # Starts on port 3000
 *   PORT=8080 node server.js          # Custom port
 */

const http = require('http');

const PORT = process.env.PORT || 3000;

// In-memory store: code → { publicIP, port, hostname, version, expiresAt }
const pairings = new Map();

// Auto-expire entries after 90 seconds (server refreshes every 30s).
const EXPIRY_MS = 90_000;

function cleanExpired() {
  const now = Date.now();
  for (const [code, entry] of pairings) {
    if (now > entry.expiresAt) {
      pairings.delete(code);
    }
  }
}

// Clean expired entries every 30 seconds.
setInterval(cleanExpired, 30_000);

function getClientIP(req) {
  // Support reverse proxy headers.
  return req.headers['x-forwarded-for']?.split(',')[0]?.trim()
    || req.headers['x-real-ip']
    || req.socket.remoteAddress;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString()));
      } catch {
        resolve(null);
      }
    });
    req.on('error', reject);
  });
}

function sendJSON(res, statusCode, data) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;

  // POST /api/pairing — Register a pairing code.
  if (req.method === 'POST' && path === '/api/pairing') {
    const body = await readBody(req);
    if (!body || !body.code || !body.port) {
      return sendJSON(res, 400, { error: 'Missing code or port' });
    }

    const code = body.code.toUpperCase();
    if (code.length !== 6) {
      return sendJSON(res, 400, { error: 'Code must be 6 characters' });
    }

    // Detect public IP from the request, or use explicit if provided.
    const publicIP = body.publicIP || getClientIP(req);

    pairings.set(code, {
      publicIP,
      port: body.port,
      hostname: body.hostname || 'Mac',
      version: body.version || '1.0',
      expiresAt: Date.now() + EXPIRY_MS,
    });

    console.log(`[REGISTER] ${code} → ${publicIP}:${body.port} (${body.hostname})`);
    return sendJSON(res, 200, { ok: true });
  }

  // GET /api/pairing/:code — Look up a pairing code.
  const getMatch = path.match(/^\/api\/pairing\/([A-Z0-9]{6})$/i);
  if (req.method === 'GET' && getMatch) {
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

  // DELETE /api/pairing/:code — Unregister.
  const delMatch = path.match(/^\/api\/pairing\/([A-Z0-9]{6})$/i);
  if (req.method === 'DELETE' && delMatch) {
    const code = delMatch[1].toUpperCase();
    pairings.delete(code);
    console.log(`[UNREGISTER] ${code}`);
    return sendJSON(res, 200, { ok: true });
  }

  // Health check.
  if (path === '/health') {
    return sendJSON(res, 200, { status: 'ok', pairings: pairings.size });
  }

  sendJSON(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  console.log(`MyRemote Signaling Server running on port ${PORT}`);
  console.log(`Endpoints:`);
  console.log(`  POST   /api/pairing         — Register pairing code`);
  console.log(`  GET    /api/pairing/:code    — Look up pairing code`);
  console.log(`  DELETE /api/pairing/:code    — Unregister`);
  console.log(`  GET    /health               — Health check`);
});
