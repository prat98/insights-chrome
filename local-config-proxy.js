/**
 * Local Config Proxy Server
 * 
 * This server proxies chrome-service requests and injects a custom app entry
 * for automation-hub-new, allowing both old (ansible-hub-ui) and new (aap-ui)
 * frontends to run simultaneously.
 * 
 * Usage:
 *   node local-config-proxy.js
 * 
 * Then start insights-chrome with:
 *   NAV_CONFIG=9000 LOCAL_APPS=automation-hub:8002,automation-hub-new:8003 npm run dev
 */

const http = require('http');
const https = require('https');

const PORT = process.env.CONFIG_PROXY_PORT || 9000;
// Use production since stage has preprod lockdown
const TARGET = 'https://console.redhat.com';

// The new app we want to inject into fed-modules
// Key must match the federation name used in webpack config
const NEW_APP_CONFIG = {
  'automationHubNew': {
    manifestLocation: '/apps/automation-hub-new/fed-mods.json',
    modules: [
      {
        id: 'automationHubNew',
        module: './RootApp',
        routes: [
          {
            pathname: '/ansible/automation-hub-new',
          },
        ],
      },
    ],
  },
};

// Navigation entry for the new app  
const NEW_NAV_ENTRY = {
  id: 'automationHubNew',
  appId: 'automationHubNew', 
  title: 'Automation Hub (New)',
  href: '/ansible/automation-hub-new',
  icon: 'AnsibleIcon',
  description: 'AAP UI Hub Insights build (development)',
};

function proxyRequest(req, res) {
  const url = new URL(req.url, TARGET);
  
  console.log(`[Config Proxy] ${req.method} ${req.url}`);
  
  const options = {
    hostname: url.hostname,
    port: 443,
    path: url.pathname + url.search,
    method: req.method,
    headers: {
      ...req.headers,
      host: url.hostname,
    },
  };

  // Remove localhost-specific headers
  delete options.headers['host'];
  options.headers['host'] = url.hostname;
  delete options.headers['connection'];
  delete options.headers['content-length'];
  // Request uncompressed response so we can modify JSON
  delete options.headers['accept-encoding'];

  const proxyReq = https.request(options, (proxyRes) => {
    let body = '';

    proxyRes.on('data', (chunk) => {
      body += chunk;
    });

    proxyRes.on('end', () => {
      let modifiedBody = body;
      const contentType = proxyRes.headers['content-type'] || '';

      // Inject new app into fed-modules
      if (req.url.includes('fed-modules')) {
        console.log('[Config Proxy] fed-modules request detected, content-type:', contentType);
        try {
          const data = JSON.parse(body);
          // Add the new app entry
          Object.assign(data, NEW_APP_CONFIG);
          modifiedBody = JSON.stringify(data);
          console.log('[Config Proxy] Injected automationHubNew into fed-modules');
          console.log('[Config Proxy] Apps in fed-modules:', Object.keys(data).slice(0, 10).join(', '), '...');
        } catch (e) {
          console.error('[Config Proxy] Failed to parse fed-modules:', e.message);
          console.error('[Config Proxy] Body preview:', body.substring(0, 200));
        }
      }

      // Inject navigation entry for ansible bundle
      if (req.url.includes('ansible-navigation') && contentType.includes('application/json')) {
        try {
          const data = JSON.parse(body);
          // Find the navItems array and add our entry
          if (data.navItems && Array.isArray(data.navItems)) {
            // Find automation hub entry and add our new one after it
            const hubIndex = data.navItems.findIndex(
              (item) => item.id === 'automation-hub' || item.href?.includes('automation-hub')
            );
            if (hubIndex !== -1) {
              data.navItems.splice(hubIndex + 1, 0, NEW_NAV_ENTRY);
            } else {
              // Just add at the end if we can't find automation-hub
              data.navItems.push(NEW_NAV_ENTRY);
            }
            modifiedBody = JSON.stringify(data);
            console.log('[Config Proxy] Injected automation-hub-new into ansible navigation');
          }
        } catch (e) {
          console.error('[Config Proxy] Failed to parse navigation:', e.message);
        }
      }

      // Set response headers
      res.writeHead(proxyRes.statusCode, {
        'Content-Type': contentType,
        'Content-Length': Buffer.byteLength(modifiedBody),
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': '*',
      });
      res.end(modifiedBody);
    });
  });

  proxyReq.on('error', (e) => {
    console.error('[Config Proxy] Request error:', e.message);
    res.writeHead(502, { 'Content-Type': 'text/plain' });
    res.end(`Proxy error: ${e.message}`);
  });

  proxyReq.end();
}

const server = http.createServer(proxyRequest);

server.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════════╗
║           Local Config Proxy for insights-chrome              ║
╠═══════════════════════════════════════════════════════════════╣
║  Listening on: http://localhost:${PORT}                         ║
║  Proxying to:  ${TARGET}                  ║
║                                                               ║
║  Injecting:                                                   ║
║    - automation-hub-new into fed-modules                      ║
║    - New nav entry in ansible-navigation                      ║
║                                                               ║
║  Start insights-chrome with:                                  ║
║    NAV_CONFIG=${PORT} npm run dev                               ║
╚═══════════════════════════════════════════════════════════════╝
`);
});

