import http from 'k6/http';
import { check } from 'k6';
import { getBaseUrl, getJavaUrl, getRustUrl } from '../helpers/common.js';

export const options = {
  scenarios: {
    brutal_test: {
      executor: 'constant-vus',
      vus: 1000,
      duration: '60s',
    },
  },

  thresholds: {
    http_req_duration: ['p(95)<5000'],
    http_req_failed: ['rate<0.05'],
  },

  noConnectionReuse: false,
  userAgent: 'k6-jmeter-style-stress',
};

const FRONTEND_URL = getBaseUrl();
const JAVA_URL = getJavaUrl();
const RUST_URL = getRustUrl();

const ENDPOINTS = [
  {
    url: () => `${FRONTEND_URL}/`,
    weight: 40,
    label: 'Frontend homepage',
  },
  {
    url: () => `${JAVA_URL}/actuator/health/readiness`,
    weight: 20,
    label: 'Java readiness',
  },
  {
    url: () => `${RUST_URL}/health`,
    weight: 20,
    label: 'Rust health',
  },
  {
    url: () => `${JAVA_URL}/api/v1/articles`,
    weight: 20,
    label: 'Java articles',
  },
];

const totalWeight = ENDPOINTS.reduce((sum, e) => sum + e.weight, 0);

function pickEndpoint() {
  const r = Math.random() * totalWeight;

  let cumulative = 0;

  for (const endpoint of ENDPOINTS) {
    cumulative += endpoint.weight;

    if (r <= cumulative) {
      return endpoint;
    }
  }

  return ENDPOINTS[0];
}

export default function () {
  const endpoint = pickEndpoint();

  const res = http.get(endpoint.url(), {
    timeout: '30s',
  });

  const passed = check(res, {
    [`${endpoint.label} status 200`]: (r) => r.status === 200,
  });

  if (!passed || res.error) {
    console.error(`
[FAILED]
endpoint=${endpoint.label}
status=${res.status}
error=${res.error}
duration=${res.timings.duration}ms
url=${endpoint.url()}
`);
  }
}