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

const RUST = 'https://rust.yomu.my.id';
const TOKEN = 'eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJkZTQzMWM2Mi1jYWY3LTRjNDctODk2My1jZWY1OGIzZDQ1ZWYiLCJpc3MiOiJ5b211LWJhY2tlbmQtamF2YSIsImF1ZCI6WyJ5b211LWNsaWVudHMiXSwicm9sZSI6IlBFTEFKQVIiLCJ0b2tlbl92ZXJzaW9uIjowLCJpYXQiOjE3Nzk0MjUyODAsImV4cCI6MTc3OTUxMTY4MH0.Ffv2eDk0S0um0iGDhENuUDnjVseMPP5zpC0z7XHkwnD5gCU1g2-MzvFmGqz79Hwigvo3vwniVnDJ7YO5Xc20Jg';

const ENDPOINTS = [
  // public — no auth
  () => `${RUST}/health`,
  // protected — needs Bearer token
  () => ({
    url: `${RUST}/api/v1/leaderboards`,
    params: { headers: { 'Authorization': `Bearer ${TOKEN}` } },
  }),
  () => ({
    url: `${RUST}/api/v1/users/de431c62-caf7-4c47-8963-cef58b3d45ef/tier`,
    params: { headers: { 'Authorization': `Bearer ${TOKEN}` } },
  }),
];

export default function () {
  const e = ENDPOINTS[Math.floor(Math.random() * ENDPOINTS.length)]();
  const res = typeof e === 'string' ? http.get(e) : http.get(e.url, e.params);
  check(res, { 'rust: status < 500': (r) => r.status < 500 });
}
