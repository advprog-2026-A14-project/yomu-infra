import http from 'k6/http';
import { check } from 'k6';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.5.0/index.js';

/**
 * Returns the base URL for all requests.
 * Defaults to http://localhost, overridable via K6_BASE_URL env var.
 * @returns {string} Base URL (e.g. "http://localhost")
 */
export function getBaseUrl() {
  return __ENV.K6_BASE_URL || 'http://localhost';
}

/**
 * Checks that an HTTP response has the expected status code.
 * Logs error details if the check fails.
 *
 * @param {object} res - k6 http response object
 * @param {number} expectedStatus - expected HTTP status code (default: 200)
 * @param {string} label - descriptive label for the check (e.g. "Java health")
 * @returns {boolean} whether the check passed
 */
export function checkResponse(res, expectedStatus = 200, label = 'unnamed') {
  const passed = check(res, {
    [`${label}: status is ${expectedStatus}`]: (r) => r.status === expectedStatus,
  });

  if (!passed) {
    console.error(
      `[FAIL] ${label}: expected ${expectedStatus}, got ${res.status} — body: ${res.body?.substring(0, 200) || '(empty)'}`
    );
  }

  return passed;
}

/**
 * Generates a random user object with username and email.
 * Useful for registration/load tests where unique identities are needed.
 *
 * @returns {{ username: string, email: string }} Random user data
 */
export function randomUser() {
  const id = randomString(8);
  return {
    username: `k6user_${id}`,
    email: `k6user_${id}@yomu.test`,
  };
}

/**
 * Performs a login request and returns the auth token.
 * This is a placeholder — adjust the endpoint and payload
 * to match Yomu's actual auth API when credentials are available.
 *
 * @param {string} baseUrl - base URL for the auth endpoint
 * @returns {{ token: string | null }} Object containing the token (or null on failure)
 */
export function setupAuth(baseUrl) {
  const url = `${baseUrl}/api/java/auth/login`;
  const payload = JSON.stringify({
    email: __ENV.K6_TEST_USER_EMAIL || 'test@yomu.test',
    password: __ENV.K6_TEST_USER_PASSWORD || 'testpassword',
  });

  const params = {
    headers: { 'Content-Type': 'application/json' },
    timeout: '10s',
  };

  const res = http.post(url, payload, params);
  const passed = check(res, {
    'login returned 200 or 201': (r) => r.status === 200 || r.status === 201,
    'login response has body': (r) => r.body && r.body.length > 0,
  });

  if (!passed) {
    console.warn(`[AUTH] Login failed with status ${res.status}`);
    return { token: null };
  }

  try {
    const body = JSON.parse(res.body);
    const token = body.data?.token || body.token || body.access_token || null;
    if (token) {
      console.log('[AUTH] Successfully obtained auth token');
    } else {
      console.warn('[AUTH] No token found in login response');
    }
    return { token };
  } catch (e) {
    console.warn(`[AUTH] Failed to parse login response: ${e.message}`);
    return { token: null };
  }
}

/**
 * Common HTTP request parameters with JSON headers.
 * @returns {object} k6 request params
 */
export function jsonHeaders() {
  return {
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
  };
}

/**
 * Builds the full URL for a given service path.
 * @param {string} path - API path (e.g., "/api/java/actuator/health/readiness")
 * @returns {string} Full URL
 */
export function url(path) {
  return `${getBaseUrl()}${path}`;
}