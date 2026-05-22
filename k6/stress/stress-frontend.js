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

export default function () {
  const res = http.get('https://yomu.my.id/');
  check(res, { 'frontend: status < 500': (r) => r.status < 500 });
}
