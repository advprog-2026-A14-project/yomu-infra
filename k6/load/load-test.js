import http from 'k6/http';
import { check, sleep } from 'k6';
import { getBaseUrl, getJavaUrl, getRustUrl } from '../helpers/common.js';

export const options = {
  stages: [
    { duration: '2m', target: 10 },
    { duration: '5m', target: 50 },
    { duration: '2m', target: 10 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<3000'],
    http_req_failed: ['rate<0.01'],
  },
};

const FRONTEND_URL = getBaseUrl();
const JAVA_URL = getJavaUrl();
const RUST_URL = getRustUrl();

const ENDPOINTS = [
  { url: () => `${FRONTEND_URL}/`, weight: 40, expectedStatus: 200, label: 'Frontend homepage' },
  { url: () => `${JAVA_URL}/actuator/health/readiness`, weight: 20, expectedStatus: 200, label: 'Java readiness' },
  { url: () => `${RUST_URL}/health`, weight: 20, expectedStatus: 200, label: 'Rust health' },
  { url: () => `${JAVA_URL}/api/v1/articles`, weight: 20, expectedStatus: [200, 401], label: 'Java articles' },
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

  const expectedStatuses = Array.isArray(endpoint.expectedStatus)
    ? endpoint.expectedStatus
    : [endpoint.expectedStatus];

  check(res, {
    [`${endpoint.label}: status is ${expectedStatuses.join(' or ')}`]: (r) =>
      expectedStatuses.includes(r.status),
  });

  if (!expectedStatuses.includes(res.status)) {
    console.error(
      `[LOAD] ${endpoint.label}: unexpected status ${res.status}, expected ${expectedStatuses.join(' or ')}`
    );
  }

  sleep(Math.random() * 2 + 1);
}