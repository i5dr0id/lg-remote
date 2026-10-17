import WebSocket from 'ws';
import fs from 'node:fs';

const TV_IP = process.env.TV_IP ?? '192.168.1.100';
const KEY_FILE = new URL('./.client-key', import.meta.url);

const manifest = {
  manifestVersion: 1,
  appVersion: '1.1',
  signed: {
    created: '20140509',
    appId: 'com.lge.test',
    vendorId: 'com.lge',
    localizedAppNames: { '': 'LG Remote App' },
    localizedVendorNames: { '': 'LG Electronics' },
    permissions: ['TEST_SECURE', 'CONTROL_INPUT_TEXT', 'CONTROL_MOUSE_AND_KEYBOARD', 'READ_INSTALLED_APPS',
      'READ_LGE_SDX', 'READ_NOTIFICATIONS', 'SEARCH', 'WRITE_SETTINGS', 'WRITE_NOTIFICATION_ALERT',
      'CONTROL_POWER', 'READ_CURRENT_CHANNEL', 'READ_RUNNING_APPS', 'READ_UPDATE_INFO',
      'UPDATE_FROM_REMOTE_APP', 'READ_LGE_TV_INPUT_EVENTS', 'READ_TV_CURRENT_TIME'],
    serial: '2f930e2d2cfe083771f68e4fe7bb07',
  },
  permissions: ['LAUNCH', 'LAUNCH_WEBAPP', 'APP_TO_APP', 'CLOSE', 'TEST_OPEN', 'TEST_PROTECTED', 'CONTROL_AUDIO',
    'CONTROL_DISPLAY', 'CONTROL_INPUT_JOYSTICK', 'CONTROL_INPUT_MEDIA_RECORDING', 'CONTROL_INPUT_MEDIA_PLAYBACK',
    'CONTROL_INPUT_TV', 'CONTROL_POWER', 'READ_APP_STATUS', 'READ_CURRENT_CHANNEL', 'READ_INPUT_DEVICE_LIST',
    'READ_NETWORK_STATE', 'READ_RUNNING_APPS', 'READ_TV_CHANNEL_LIST', 'WRITE_NOTIFICATION_TOAST',
    'READ_POWER_STATE', 'READ_COUNTRY_INFO', 'READ_SETTINGS'],
  signatures: [{ signatureVersion: 1, signature: 'placeholder' }],
};

export function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`wss://${TV_IP}:3001`, { rejectUnauthorized: false });
    const pending = new Map();
    let nextId = 0;

    const request = (uri, payload = {}) => new Promise((res, rej) => {
      const id = `req_${nextId++}`;
      pending.set(id, { res, rej });
      ws.send(JSON.stringify({ id, type: 'request', uri, payload }));
    });

    ws.on('error', reject);
    ws.on('open', () => {
      const key = fs.existsSync(KEY_FILE) ? fs.readFileSync(KEY_FILE, 'utf8').trim() : undefined;
      if (!key) console.log('Pairing: accept the prompt on the TV with your remote...');
      ws.send(JSON.stringify({
        id: 'register', type: 'register',
        payload: { forcePairing: false, pairingType: 'PROMPT', 'client-key': key, manifest },
      }));
    });
    ws.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.id === 'register') {
        if (msg.type === 'registered') {
          fs.writeFileSync(KEY_FILE, msg.payload['client-key']);
          resolve({ request, close: () => ws.close() });
        } else if (msg.type === 'error') reject(new Error(msg.error));
        return;
      }
      const p = pending.get(msg.id);
      if (!p) return;
      pending.delete(msg.id);
      msg.type === 'error' ? p.rej(new Error(msg.error)) : p.res(msg.payload);
    });
  });
}

// CLI: node lgtv.js <ssap-uri> [json-payload]
if (import.meta.url === `file://${process.argv[1]}`) {
  const [uri = 'ssap://com.webos.service.update/getCurrentSWInformation', payload] = process.argv.slice(2);
  const tv = await connect();
  console.log(JSON.stringify(await tv.request(uri, payload ? JSON.parse(payload) : {}), null, 2));
  tv.close();
}
