// mv-package registry — the packagist/npm-registry equivalent for MultiValue.
// Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
//
// A dependency-free HTTP registry.  Packages live under registry/<name>/ as a
// meta.json ({name, version, description, tarball}) beside the release tar the
// tarball path points at.  The MVPKG client (pure MultiValue BASIC) speaks to
// three routes:
//
//   GET /package/<name>   -> that package's meta.json
//   GET /search?q=<term>  -> {"packages":[{name,version,description}, ...]}
//   GET /tarball/<file>   -> the release tar bytes (application/gzip)
//
//   node server.js [port]        (default 8080; or $MVPKG_PORT)

'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const REGDIR = path.join(__dirname, 'registry');
const PORT = Number(process.argv[2] || process.env.MVPKG_PORT || 8080);

// Read every registry/<name>/meta.json.  Re-read per request so a package
// dropped in while the server runs is picked up without a restart.
function loadPackages() {
  const out = [];
  let names;
  try { names = fs.readdirSync(REGDIR); } catch { return out; }
  for (const name of names) {
    const mp = path.join(REGDIR, name, 'meta.json');
    try {
      const meta = JSON.parse(fs.readFileSync(mp, 'utf8'));
      if (meta && meta.name) out.push(meta);
    } catch { /* not a package dir */ }
  }
  return out;
}

function sendJSON(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json',
                        'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

const server = http.createServer((req, res) => {
  const u = url.parse(req.url, true);
  const parts = u.pathname.split('/').filter(Boolean);

  // GET /package/<name>
  if (parts[0] === 'package' && parts[1]) {
    const meta = loadPackages().find(p => p.name === parts[1]);
    if (!meta) return sendJSON(res, 404, { error: 'not found' });
    return sendJSON(res, 200, meta);
  }

  // GET /search?q=<term>
  if (parts[0] === 'search') {
    const q = String(u.query.q || '').toLowerCase();
    const hits = loadPackages()
      .filter(p => !q || (p.name + ' ' + (p.description || '')).toLowerCase().includes(q))
      .map(p => ({ name: p.name, version: p.version, description: p.description || '' }));
    return sendJSON(res, 200, { packages: hits });
  }

  // GET /tarball/<file>
  if (parts[0] === 'tarball' && parts[1]) {
    // Resolve strictly inside registry/ — never follow a "../" out of it.
    const file = path.normalize(parts.slice(1).join('/'));
    if (file.startsWith('..')) { res.writeHead(400); return res.end('bad path'); }
    // The tarball path in meta.json is /tarball/<name>/<file>, on disk under
    // registry/<name>/<file>.
    const abs = path.join(REGDIR, file);
    fs.readFile(abs, (err, data) => {
      if (err) { res.writeHead(404); return res.end('not found'); }
      res.writeHead(200, { 'Content-Type': 'application/gzip',
                           'Content-Length': data.length });
      res.end(data);
    });
    return;
  }

  if (u.pathname === '/' || parts[0] === 'packages') {
    return sendJSON(res, 200, { packages: loadPackages() });
  }

  res.writeHead(404); res.end('not found');
});

server.listen(PORT, () => {
  console.log(`mv-package registry on http://127.0.0.1:${PORT}  (registry: ${REGDIR})`);
});
