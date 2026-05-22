import http from 'k6/http';
import { check, sleep } from 'k6';
import { getBaseUrl, getJavaUrl, getRustUrl } from '../helpers/common.js';

export const options = {
  stages: [
    { duration: '1m', target: 50 },
    { duration: '3m', target: 200 },
    { duration: '3m', target: 200 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<5000'],
    http_req_failed: ['rate<0.05'],
  },
};

const FRONTEND_URL = getBaseUrl();
const JAVA_URL = getJavaUrl();
const RUST_URL = getRustUrl();

const ENDPOINTS = [
  { url: () => `${FRONTEND_URL}/`, weight: 40, label: 'Frontend homepage' },
  { url: () => `${JAVA_URL}/actuator/health/readiness`, weight: 10, label: 'Java health' },
  { url: () => `${RUST_URL}/health`, weight: 10, label: 'Rust health' },
  { url: () => `${JAVA_URL}/articles`, weight: 20, label: 'Java articles' },
  { url: () => `${RUST_URL}/api/v1/leaderboard`, weight: 20, label: 'Rust leaderboard' },
];

const totalWeight = ENDPOINTS.reduce((sum, e) => sum + e.weight, 0);

function pickEndpoint() {
  const r = Math.random() * totalWeight;
  let cumulative = 0;
  for (const endpoint of ENDPOINTS) {
    cumulative += endpoint.weight;
    if (r <= cumulative) return endpoint;
  }
  return ENDPOINTS[0];
}

export default function () {
  const endpoint = pickEndpoint();
  const res = http.get(endpoint.url());

  const passed = check(res, {
    [`${endpoint.label}: status below 500`]: (r) => r.status < 500,
  });

  if (!passed) {
    console.error(
      `[STRESS] ${endpoint.label}: server error ${res.status} — traffic may be exceeding capacity`
    );
  }

  sleep(Math.random() * 0.5 + 0.5);
}