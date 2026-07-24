const http = require('http');
const { GoogleAuth } = require('google-auth-library');

const SERVICE_ACCOUNT = require('./service-account.json');

async function getAccessToken() {
  const auth = new GoogleAuth({
    credentials: SERVICE_ACCOUNT,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  return token.token;
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
  if (req.method !== 'POST') { res.writeHead(404); res.end(); return; }

  let body = '';
  req.on('data', chunk => body += chunk);
  req.on('end', async () => {
    try {
      const { token, title, body: msgBody, data } = JSON.parse(body);
      const accessToken = await getAccessToken();

      const fcmRes = await fetch(
        `https://fcm.googleapis.com/v1/projects/afit-shuttle-system/messages:send`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body: msgBody },
              data: data || {},
              android: {
                priority: 'high',
                notification: { channel_id: 'assa_main' }
              }
            }
          })
        }
      );

      const result = await fcmRes.json();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(result));
    } catch (err) {
      res.writeHead(500);
      res.end(JSON.stringify({ error: err.message }));
    }
  });
});

server.listen(3000, () => console.log('FCM server running on http://localhost:3000'));