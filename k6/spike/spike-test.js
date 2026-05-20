import http from 'k6/http';
import { sleep } from 'k6';
import { getBaseUrl, checkResponse, url } from '../helpers/common.js';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '10s', target: 200 },
    { duration: '3m', target: 10 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<5000'],
    http_req_failed: ['rate<0.05'],
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
      `[SPIKE] ${endpoint.label}: server error ${res.status} during spike — checking recovery`
    );
  }

  sleep(Math.random() * 1 + 0.5);
}