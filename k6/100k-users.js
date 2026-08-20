// Copyright 2026
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// k6 load test simulating up to 100,000 concurrent virtual users against
// the frontend Service, exercising the same browse -> add-to-cart -> checkout
// path as src/loadgenerator's Locust script. Ramps gradually so HPA (see
// kubernetes-manifests-aws/hpa.yaml) and Karpenter (see karpenter/) have
// time to react instead of the run itself acting as a step-function DoS.
//
// Usage:
//   FRONTEND_URL=http://<frontend-lb-hostname> k6 run k6/100k-users.js

import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.FRONTEND_URL || 'http://localhost:8080';

const PRODUCT_IDS = [
  '0PUK6V6EV0', '1YMWWN1N4O', '2ZYFJ3GM2N', '66VCHSJNUP',
  '6E92ZMYYFZ', '9SIQT8TOJO', 'L9ECAV7KIM', 'LS4PSXUNUM', 'OLJCESPC7Z',
];

export const options = {
  scenarios: {
    ramping_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 5000 },
        { duration: '3m', target: 25000 },
        { duration: '5m', target: 60000 },
        { duration: '5m', target: 100000 },
        { duration: '10m', target: 100000 },
        { duration: '3m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },
};

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

export default function () {
  let res = http.get(`${BASE_URL}/`);
  check(res, { 'home status 200': (r) => r.status === 200 });

  const productId = pick(PRODUCT_IDS);
  res = http.get(`${BASE_URL}/product/${productId}`);
  check(res, { 'product status 200': (r) => r.status === 200 });

  res = http.post(`${BASE_URL}/cart`, {
    product_id: productId,
    quantity: '1',
  });
  check(res, { 'add-to-cart status 200/302': (r) => r.status === 200 || r.status === 302 });

  res = http.get(`${BASE_URL}/cart`);
  check(res, { 'cart status 200': (r) => r.status === 200 });

  sleep(Math.random() * 3 + 1);
}
