import http from 'k6/http';
import { sleep } from 'k6';
import { getBaseUrl, url } from '../helpers/common.js';

export const options = {
  stages: [
    { duration: '5m', target: 30 },
    { duration: '4h', target: 30 },
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<3000'],
    http_req_failed: ['rate<0.005'],
  },
};

const BASE_URL = getBaseUrl();

const ENDPOINTS = [
  { path: '/', weight: 40, expectedStatus: 200, label: 'Frontend homepage' },
  { path: '/api/java/actuator/health/readiness', weight: 10, expectedStatus: 200, label: 'Java health' },
  { path: '/api/rust/health', weight: 10, expectedStatus: 200, label: 'Rust health' },
  { path: '/api/java/articles', weight: 20, expectedStatus: [200, 401], label: 'Java articles' },
  { path: '/api/rust/leaderboard', weight: 20, expectedStatus: [200, 401], label: 'Rust leaderboard' },
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
  const res = http.get(url(endpoint.path));

  const expectedStatuses = Array.isArray(endpoint.expectedStatus)
    ? endpoint.expectedStatus
    : [endpoint.expectedStatus];

  check(res, {
    [`${endpoint.label}: status is ${expectedStatuses.join(' or ')}`]: (r) =>
      expectedStatuses.includes(r.status),
  });

  if (res.status >= 500) {
    console.error(
      `[SOAK] ${endpoint.label}: server error ${res.status} — potential resource leak detected`
    );
  }

  // Memory leak detection: k6 VUs use ~5-10MB baseline.
  // Monitor system memory during this 4+ hour test.
  // If memory grows linearly over the soak duration, suspect a leak
  // in the Java or Rust backend. Watch Grafana JVM heap / Rust allocations.
  sleep(Math.random() * 2 + 1);
}