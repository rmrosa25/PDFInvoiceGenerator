#!/usr/bin/env bash
# Usage:
#   ./test.sh              # build (tsc) and test against local Node process
#   ./test.sh --local      # same as above
#   ./test.sh --docker     # build Docker image and test against container
#   ./test.sh --help
set -euo pipefail

# ── Mode ──────────────────────────────────────────────────────────────────────
MODE="local"
case "${1:-}" in
  --docker) MODE="docker" ;;
  --local|"") MODE="local" ;;
  --help|-h)
    echo "Usage: $0 [--local|--docker]"
    echo "  --local   Build with tsc and run as a Node process (default)"
    echo "  --docker  Build a Docker image and run as a container"
    exit 0
    ;;
  *) echo "Unknown option: $1  (use --local or --docker)"; exit 1 ;;
esac

# ── Config ────────────────────────────────────────────────────────────────────
PORT=3000
BASE_URL="http://localhost:${PORT}"
IMAGE_NAME="invoice-generator-test"
CONTAINER_NAME="invoice-generator-test-$$"
SERVER_PID=""
PASS=0
FAIL=0
OUTPUT_DIR="$(mktemp -d)"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}${BOLD}[test]${RESET} $*"; }
pass()    { echo -e "  ${GREEN}✅ PASS${RESET} $*"; PASS=$((PASS + 1)); }
fail()    { echo -e "  ${RED}❌ FAIL${RESET} $*"; FAIL=$((FAIL + 1)); }
section() { echo -e "\n${BOLD}${YELLOW}── $* ──${RESET}"; }

cleanup() {
  # Stop local Node process
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  # Stop and remove Docker container
  if docker ps -q --filter "name=${CONTAINER_NAME}" 2>/dev/null | grep -q .; then
    docker stop "${CONTAINER_NAME}" > /dev/null 2>&1 || true
  fi
  if docker ps -aq --filter "name=${CONTAINER_NAME}" 2>/dev/null | grep -q .; then
    docker rm "${CONTAINER_NAME}" > /dev/null 2>&1 || true
  fi
  rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT

assert_http() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (HTTP $actual)"
  else
    fail "$label — expected HTTP $expected, got $actual"
  fi
}

assert_pdf() {
  local label="$1" file="$2"
  if [[ -f "$file" ]] && head -c 5 "$file" | grep -q '%PDF-'; then
    local size
    size=$(wc -c < "$file" | tr -d ' ')
    pass "$label (valid PDF, ${size} bytes)"
  else
    fail "$label — file is not a valid PDF"
  fi
}

assert_json_contains() {
  local label="$1" body="$2" needle="$3"
  if echo "$body" | grep -q "$needle"; then
    pass "$label"
  else
    fail "$label — response did not contain '${needle}'"
    echo "    Response: $body"
  fi
}

wait_for_server() {
  local ready=0
  for _ in $(seq 1 40); do
    if curl -sf "${BASE_URL}/invoice/layouts" > /dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.5
  done
  echo "$ready"
}

# ── Docker helpers ────────────────────────────────────────────────────────────
ensure_docker() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker not found in PATH.${RESET}"
    echo "  On macOS with Colima: brew install docker colima && colima start"
    exit 1
  fi

  # On macOS, check if a Docker daemon is reachable; start Colima if not
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if ! docker info > /dev/null 2>&1; then
      if command -v colima &> /dev/null; then
        log "Docker daemon not running — starting Colima..."
        colima start
        for _ in $(seq 1 20); do
          docker info > /dev/null 2>&1 && break || sleep 1
        done
      else
        echo -e "${RED}Error: Docker daemon is not running and Colima is not installed.${RESET}"
        echo "  Install with: brew install colima && colima start"
        exit 1
      fi
    fi
  fi

  if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running.${RESET}"
    exit 1
  fi
}

# ── 1. Build ──────────────────────────────────────────────────────────────────
section "Build (${MODE})"

if [[ "$MODE" == "local" ]]; then
  log "Running tsc..."
  if npm run build --silent 2>&1; then
    pass "TypeScript compilation"
  else
    fail "TypeScript compilation — aborting"
    exit 1
  fi
else
  ensure_docker
  log "Building Docker image '${IMAGE_NAME}'..."
  if docker build -t "${IMAGE_NAME}" . 2>&1; then
    pass "Docker image built"
  else
    fail "Docker build failed — aborting"
    exit 1
  fi
fi

# ── 2. Start server ───────────────────────────────────────────────────────────
section "Server startup (${MODE})"

if [[ "$MODE" == "local" ]]; then
  log "Starting Node server on port ${PORT}..."
  node dist/index.js > /tmp/invoice-server-test.log 2>&1 &
  SERVER_PID=$!

  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "Server process failed to start"
    cat /tmp/invoice-server-test.log
    exit 1
  fi

  READY=$(wait_for_server)
  if [[ "$READY" == "1" ]]; then
    pass "Server started (PID ${SERVER_PID})"
  else
    fail "Server did not become ready within 20s"
    cat /tmp/invoice-server-test.log
    exit 1
  fi
else
  log "Starting container '${CONTAINER_NAME}' on port ${PORT}..."
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${PORT}:3000" \
    "${IMAGE_NAME}" > /dev/null

  READY=$(wait_for_server)
  if [[ "$READY" == "1" ]]; then
    pass "Container started (${CONTAINER_NAME})"
  else
    fail "Container did not become ready within 20s"
    echo -e "${RED}Container logs:${RESET}"
    docker logs "${CONTAINER_NAME}" 2>&1 || true
    exit 1
  fi
fi

# ── 3. Layouts endpoint ───────────────────────────────────────────────────────
section "GET /invoice/layouts"

RESPONSE=$(curl -sf "${BASE_URL}/invoice/layouts")
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/invoice/layouts")

assert_http "Layouts endpoint responds" "200" "$STATUS"
assert_json_contains "Response includes 'standard' layout" "$RESPONSE" '"standard"'
assert_json_contains "Response includes 'minimal' layout"  "$RESPONSE" '"minimal"'

# ── 4. Standard layout ────────────────────────────────────────────────────────
section "POST /invoice/generate — standard layout"

STANDARD_PDF="${OUTPUT_DIR}/standard.pdf"
STATUS=$(curl -s -o "$STANDARD_PDF" -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "layout": "standard",
    "invoice": { "number": "INV-2026-001", "date": "2026-05-07", "dueDate": "2026-06-07" },
    "seller": {
      "name": "Acme Corp", "address": "123 Main St",
      "city": "Lisbon", "country": "Portugal",
      "taxId": "PT123456789", "email": "billing@acme.com"
    },
    "buyer": {
      "name": "Client Ltd", "address": "456 Oak Ave",
      "city": "Porto", "country": "Portugal",
      "taxId": "PT987654321"
    },
    "items": [
      { "description": "Web Development", "quantity": 10, "unitPrice": 150.00, "vatRate": 23 },
      { "description": "Design Services",  "quantity": 5,  "unitPrice": 80.00,  "vatRate": 23 }
    ],
    "currency": "EUR",
    "notes": "Payment due within 30 days."
  }')

assert_http "Standard layout returns 200"    "200" "$STATUS"
assert_pdf  "Standard layout produces a PDF" "$STANDARD_PDF"

# ── 5. Minimal layout ─────────────────────────────────────────────────────────
section "POST /invoice/generate — minimal layout"

MINIMAL_PDF="${OUTPUT_DIR}/minimal.pdf"
STATUS=$(curl -s -o "$MINIMAL_PDF" -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "layout": "minimal",
    "invoice": { "number": "INV-2026-002", "date": "2026-05-07", "dueDate": "2026-06-07" },
    "seller": { "name": "Studio X", "address": "1 Design Ave", "city": "London", "country": "UK" },
    "buyer":  { "name": "Brand Co", "address": "99 Market St", "city": "Manchester", "country": "UK" },
    "items": [
      { "description": "Brand Identity", "quantity": 1, "unitPrice": 2500.00, "vatRate": 20 },
      { "description": "Print Assets",   "quantity": 3, "unitPrice": 300.00,  "vatRate": 20 }
    ],
    "currency": "GBP"
  }')

assert_http "Minimal layout returns 200"    "200" "$STATUS"
assert_pdf  "Minimal layout produces a PDF" "$MINIMAL_PDF"

# ── 6. Multi-rate VAT ─────────────────────────────────────────────────────────
section "POST /invoice/generate — multiple VAT rates"

MULTI_PDF="${OUTPUT_DIR}/multi-vat.pdf"
STATUS=$(curl -s -o "$MULTI_PDF" -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "layout": "standard",
    "invoice": { "number": "INV-2026-003", "date": "2026-05-07", "dueDate": "2026-05-21" },
    "seller": { "name": "Multi VAT Ltd", "address": "1 Tax St", "city": "Dublin", "country": "Ireland" },
    "buyer":  { "name": "Buyer Inc",     "address": "2 Buy Rd",  "city": "Cork",   "country": "Ireland" },
    "items": [
      { "description": "Software (23% VAT)", "quantity": 2, "unitPrice": 500.00, "vatRate": 23 },
      { "description": "Books (0% VAT)",     "quantity": 4, "unitPrice": 25.00,  "vatRate": 0  },
      { "description": "Food (13.5% VAT)",   "quantity": 6, "unitPrice": 10.00,  "vatRate": 13.5 }
    ],
    "currency": "EUR"
  }')

assert_http "Multi-rate VAT returns 200"    "200" "$STATUS"
assert_pdf  "Multi-rate VAT produces a PDF" "$MULTI_PDF"

# ── 7. Zero-VAT invoice ───────────────────────────────────────────────────────
section "POST /invoice/generate — zero VAT"

ZERO_PDF="${OUTPUT_DIR}/zero-vat.pdf"
STATUS=$(curl -s -o "$ZERO_PDF" -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "layout": "minimal",
    "invoice": { "number": "INV-2026-004", "date": "2026-05-07", "dueDate": "2026-05-14" },
    "seller": { "name": "Freelancer", "address": "Home Office", "city": "Berlin", "country": "Germany" },
    "buyer":  { "name": "Startup GmbH", "address": "Hub St 1", "city": "Munich", "country": "Germany" },
    "items": [
      { "description": "Consulting (VAT exempt)", "quantity": 8, "unitPrice": 120.00, "vatRate": 0 }
    ],
    "currency": "EUR"
  }')

assert_http "Zero-VAT invoice returns 200"    "200" "$STATUS"
assert_pdf  "Zero-VAT invoice produces a PDF" "$ZERO_PDF"

# ── 8. Unknown layout → 400 ───────────────────────────────────────────────────
section "POST /invoice/generate — unknown layout"

UNKNOWN_PAYLOAD='{
  "layout": "nonexistent",
  "invoice": { "number": "X", "date": "2026-05-07", "dueDate": "2026-05-08" },
  "seller": { "name": "X", "address": "X", "city": "X", "country": "X" },
  "buyer":  { "name": "X", "address": "X", "city": "X", "country": "X" },
  "items": [{ "description": "X", "quantity": 1, "unitPrice": 1, "vatRate": 0 }],
  "currency": "EUR"
}'

BODY=$(curl -s   -X POST "${BASE_URL}/invoice/generate" -H "Content-Type: application/json" -d "$UNKNOWN_PAYLOAD")
STATUS=$(curl -s -X POST "${BASE_URL}/invoice/generate" -H "Content-Type: application/json" -d "$UNKNOWN_PAYLOAD" -o /dev/null -w "%{http_code}")

assert_http "Unknown layout returns 400" "400" "$STATUS"
assert_json_contains "Error body lists available layouts" "$BODY" '"availableLayouts"'

# ── 9. Schema validation ──────────────────────────────────────────────────────
section "POST /invoice/generate — schema validation"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" -H "Content-Type: application/json" \
  -d '{ "layout": "standard" }')
assert_http "Missing required fields returns 400" "400" "$STATUS"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" -H "Content-Type: application/json" \
  -d '{
    "layout": "standard",
    "invoice": { "number": "X", "date": "2026-05-07", "dueDate": "2026-05-08" },
    "seller": { "name": "X", "address": "X", "city": "X", "country": "X" },
    "buyer":  { "name": "X", "address": "X", "city": "X", "country": "X" },
    "items": [], "currency": "EUR"
  }')
assert_http "Empty items array returns 400" "400" "$STATUS"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" -H "Content-Type: application/json" \
  -d '{
    "layout": "standard",
    "invoice": { "number": "X", "date": "2026-05-07", "dueDate": "2026-05-08" },
    "seller": { "name": "X", "address": "X", "city": "X", "country": "X" },
    "buyer":  { "name": "X", "address": "X", "city": "X", "country": "X" },
    "items": [{ "description": "X", "quantity": -1, "unitPrice": 10, "vatRate": 0 }],
    "currency": "EUR"
  }')
assert_http "Negative quantity returns 400" "400" "$STATUS"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${BASE_URL}/invoice/generate" -H "Content-Type: application/json" \
  -d '{
    "layout": "standard",
    "invoice": { "number": "X", "date": "2026-05-07", "dueDate": "2026-05-08" },
    "seller": { "name": "X", "address": "X", "city": "X", "country": "X" },
    "buyer":  { "name": "X", "address": "X", "city": "X", "country": "X" },
    "items": [{ "description": "X", "quantity": 1, "unitPrice": 10, "vatRate": 150 }],
    "currency": "EUR"
  }')
assert_http "VAT rate > 100 returns 400" "400" "$STATUS"

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo ""
echo -e "${BOLD}────────────────────────────────────────${RESET}"
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET} / ${TOTAL} total${RESET}"
echo -e "${BOLD}────────────────────────────────────────${RESET}"

if [[ $FAIL -gt 0 ]]; then
  if [[ "$MODE" == "docker" ]]; then
    echo -e "${RED}Container logs:${RESET}"
    docker logs "${CONTAINER_NAME}" 2>&1 || true
  else
    echo -e "${RED}Server log:${RESET}"
    cat /tmp/invoice-server-test.log
  fi
  exit 1
fi
