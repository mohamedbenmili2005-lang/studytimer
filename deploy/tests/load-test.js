// Test de charge k6 (cahier 8 : API < 500 ms pour les operations courantes).
// Utilisation : k6 run deploy/tests/load-test.js          (serveur : BASE_URL=https://mon-serveur k6 run ...)
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 50,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:5293';
const JSON_HEADERS = { 'Content-Type': 'application/json' };

export function setup() {
  const id = Date.now();
  const body = JSON.stringify({
    firstName: 'Load', lastName: 'Test', username: 'load' + id, email: 'load' + id + '@test.com',
    password: 'MotDePasse123', country: 'MA', timeZone: 'UTC',
  });
  const r = http.post(BASE + '/api/auth/register', body, { headers: JSON_HEADERS });
  check(r, { 'inscription ok': (x) => x.status === 200 });
  return { token: r.json('token') };
}

export default function (data) {
  const params = { headers: { Authorization: 'Bearer ' + data.token } };
  const res = http.batch([
    ['GET', BASE + '/api/leaderboard?period=week', null, params],
    ['GET', BASE + '/api/statistics/dashboard', null, params],
    ['GET', BASE + '/api/sessions/history', null, params],
    ['GET', BASE + '/api/challenges', null, params],
  ]);
  for (const r of res) check(r, { 'statut 200': (x) => x.status === 200 });
  sleep(1);
}