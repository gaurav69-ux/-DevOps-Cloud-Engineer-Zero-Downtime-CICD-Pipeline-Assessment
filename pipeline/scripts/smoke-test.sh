#!/bin/bash
# scripts/smoke-tests.sh — 15 critical path smoke tests
# Usage: ./smoke-tests.sh --target <url> [--suite production-critical-path]
set -euo pipefail

TARGET="${1:-}"
SUITE="${2:-production-critical-path}"
PASS=0; FAIL=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --target) TARGET="$2"; shift 2 ;;
    --suite)  SUITE="$2";  shift 2 ;;
    *) shift ;;
  esac
done

[[ -z "$TARGET" ]] && { echo "Usage: $0 --target <url>"; exit 1; }
BASE="${TARGET%/}"

check() {
  local id="$1" desc="$2" method="$3" path="$4" expected="$5" extra="${6:-}"
  local status
  status=$(curl -sf -o /dev/null -w "%{http_code}" -X "$method" \
    -H "Authorization: Bearer ${SMOKE_TEST_TOKEN:-}" \
    -H "Content-Type: application/json" \
    ${extra:+$extra} \
    "${BASE}${path}" 2>/dev/null || echo "000")
  if [[ "$status" == "$expected" ]]; then
    echo "  ✓ T${id}: ${desc} [${status}]"; ((PASS++))
  else
    echo "  ✗ T${id}: ${desc} [expected ${expected}, got ${status}]"; ((FAIL++))
  fi
}

echo "=== NovaPay Smoke Tests: ${SUITE} against ${BASE} ==="

# Auth
LOGIN_RESP=$(curl -sf -X POST "${BASE}/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"smoke-test@novapay.in","password":"'"${SMOKE_TEST_PASSWORD:-}"'"}' 2>/dev/null || echo "{}")
SMOKE_TEST_TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

check "01" "Health liveness"            GET  "/actuator/health/liveness"    "200"
check "02" "Health readiness"           GET  "/actuator/health/readiness"   "200"
check "03" "Auth login"                 POST "/api/v1/auth/login"           "200" \
  "-d '{\"username\":\"smoke-test@novapay.in\",\"password\":\"${SMOKE_TEST_PASSWORD:-}\"}'"
check "04" "Account list (authed)"      GET  "/api/v1/accounts"            "200"
check "05" "Account balance"            GET  "/api/v1/accounts/1/balance"  "200"
check "06" "Payment initiate"           POST "/api/v1/payments/initiate"   "202" \
  "-d '{\"amount\":1,\"currency\":\"INR\",\"beneficiary\":\"test@upi\",\"remarks\":\"smoke-test\"}'"
check "07" "Payment status"             GET  "/api/v1/payments/status/1"   "200"
check "08" "UPI payment"               POST "/api/v1/upi/pay"             "202" \
  "-d '{\"amount\":1,\"vpa\":\"test@novapay\",\"remarks\":\"smoke\"}'"
check "09" "Transaction history"        GET  "/api/v1/transactions"        "200"
check "10" "Beneficiary list"           GET  "/api/v1/beneficiaries"       "200"
check "11" "Version endpoint"           GET  "/api/v1/config/version"      "200"
check "12" "Prometheus metrics"         GET  "/actuator/prometheus"        "200"
check "13" "KYC verify"                POST "/api/v1/kyc/verify"          "200" \
  "-d '{\"pan\":\"XXXXX1234X\",\"dob\":\"1990-01-01\"}'"
check "14" "Notifications send"         POST "/api/v1/notifications/send"  "202" \
  "-d '{\"type\":\"TEST\",\"recipient\":\"smoke@test\"}'"
check "15" "Auth logout"               POST "/api/v1/auth/logout"          "200"

echo ""
echo "Results: ${PASS}/15 passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && echo "✓ All smoke tests PASSED" || { echo "✗ Smoke tests FAILED — blocking deployment"; exit 1; }