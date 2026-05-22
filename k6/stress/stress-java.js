import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 1000,
  iterations: 50000,
  thresholds: {
    http_req_duration: ['p(95)<5000'],
    http_req_failed: ['rate<0.05'],
  },
};

const JAVA = 'https://java.yomu.my.id';

const ENDPOINTS = [
  () => `${JAVA}/actuator/health/readiness`,
  () => `${JAVA}/api/v1/articles`,
];

export default function () {
  const url = ENDPOINTS[Math.floor(Math.random() * ENDPOINTS.length)]();
  const res = http.get(url);
  check(res, { 'java: status < 500': (r) => r.status < 500 });
}
