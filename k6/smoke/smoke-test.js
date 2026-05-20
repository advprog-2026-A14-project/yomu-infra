import http from 'k6/http';
import { check, sleep } from 'k6';
import { getBaseUrl, checkResponse } from '../helpers/common.js';

export const options = {
  vus: 1,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.1'],
  },
};

const BASE_URL = getBaseUrl();

/**
 * Smoke test — validates that all services are up and responding
 * before switching traffic in a blue-green deployment.
 */
export default function () {
  // --- Frontend homepage ---
  const frontendRes = http.get(`${BASE_URL}/`);
  checkResponse(frontendRes, 200, 'Frontend homepage');

  // --- Java backend: readiness probe ---
  const javaReadinessRes = http.get(`${BASE_URL}/api/java/actuator/health/readiness`);
  checkResponse(javaReadinessRes, 200, 'Java readiness');

  // --- Java backend: liveness probe ---
  const javaLivenessRes = http.get(`${BASE_URL}/api/java/actuator/health/liveness`);
  checkResponse(javaLivenessRes, 200, 'Java liveness');

  // --- Rust backend: health check ---
  const rustHealthRes = http.get(`${BASE_URL}/api/rust/health`);
  checkResponse(rustHealthRes, 200, 'Rust health');

  sleep(1);
}

export function handleSummary(data) {
  const passed = data.metrics.http_req_failed
    ? data.metrics.http_req_failed.values.rate < 0.1
    : true;
  const p95 = data.metrics.http_req_duration
    ? data.metrics.http_req_duration.values['p(95)']
    : 0;

  console.log('\n=== SMOKE TEST SUMMARY ===');
  console.log(`Total requests:  ${data.metrics.iterations?.values?.count || 'N/A'}`);
  console.log(`Fail rate:       ${data.metrics.http_req_failed?.values?.rate?.toFixed(4) || 'N/A'}`);
  console.log(`p(95) duration:   ${p95?.toFixed(0) || 'N/A'}ms`);
  console.log(`Result:          ${passed ? 'PASS ✅' : 'FAIL ❌'}`);
  console.log('==========================\n');

  return {};
}