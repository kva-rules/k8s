#!/usr/bin/env bash
# k8s.sh — one-shot Kubernetes lifecycle for the Services project (kind-based)
#
#   ./k8s.sh up      : create kind cluster, build+load images, deploy, seed roles
#   ./k8s.sh down    : delete the kind cluster
#   ./k8s.sh status  : pod + ingress status
#   ./k8s.sh test    : end-to-end smoke test via ingress
#
# After `up`, add this line to /etc/hosts (needs sudo, one-time):
#     127.0.0.1  ticketing.local

set -u
PROJECT_DIR="/Users/abhidhabmellwyn/Downloads/Services"
K8S_DIR="${PROJECT_DIR}/k8s"
CLUSTER=ticketing
NS=ticketing-system

c_g=$'\033[32m'; c_r=$'\033[31m'; c_y=$'\033[33m'; c_z=$'\033[0m'
ok()  { echo "${c_g}[✓]${c_z} $*"; }
err() { echo "${c_r}[x]${c_z} $*" >&2; }
inf() { echo "${c_y}[i]${c_z} $*"; }

SERVICES=(
  "api-gateway|api_gateway"
  "auth-service|auth_service"
  "user-service|User_service"
  "ticket-service|Ticket_service"
  "solution-service|Solution_service"
  "knowledge-service|knowledge_service"
  "reward-service|Reward_service"
  "notification-service|Notification_service"
)

cmd_up() {
  # 1 — cluster
  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
    inf "creating kind cluster ${CLUSTER}..."
    kind create cluster --config "${K8S_DIR}/kind-cluster.yaml"
  else
    ok "kind cluster ${CLUSTER} already exists"
  fi

  # 2 — build & load images
  inf "building images..."
  for s in "${SERVICES[@]}"; do
    IFS='|' read -r img folder <<<"$s"
    inf "  ${img}"
    docker build -q -t "${img}:latest" "${PROJECT_DIR}/${folder}" >/dev/null || { err "build failed: $img"; return 1; }
  done
  docker build -q -t frontend:latest "${PROJECT_DIR}/frontend" >/dev/null

  inf "loading images into kind..."
  for s in "${SERVICES[@]}"; do
    IFS='|' read -r img _ <<<"$s"
    kind load docker-image "${img}":latest --name "${CLUSTER}" >/dev/null 2>&1
  done
  kind load docker-image frontend:latest --name "${CLUSTER}" >/dev/null 2>&1

  # 3 — ingress controller
  if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
    inf "installing nginx-ingress..."
    kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller --timeout=180s
  fi

  # 4 — deploy
  inf "applying manifests..."
  bash "${K8S_DIR}/apply.sh" || true  # tolerate timeouts

  # 5 — wait
  inf "waiting for all pods ready..."
  kubectl wait --for=condition=ready pod --all -n "${NS}" --timeout=300s || true

  # 6 — seed roles
  inf "seeding roles table..."
  kubectl exec -n "${NS}" postgres-auth-0 -- psql -U postgres -d auth_db -c \
    "INSERT INTO roles (role_id, role_name, created_at, description) VALUES
       (gen_random_uuid(), 'USER',     NOW(), 'Standard user role'),
       (gen_random_uuid(), 'ADMIN',    NOW(), 'Administrator role'),
       (gen_random_uuid(), 'ENGINEER', NOW(), 'Engineer role'),
       (gen_random_uuid(), 'MANAGER',  NOW(), 'Manager role')
     ON CONFLICT (role_name) DO NOTHING;" >/dev/null && ok "roles seeded"

  ok "deployment complete"
  echo
  echo "  Add to /etc/hosts (one-time):"
  echo "    sudo sh -c 'echo \"127.0.0.1 ticketing.local\" >> /etc/hosts'"
  echo
  echo "  Then:  open http://ticketing.local/"
}

cmd_down() {
  inf "deleting kind cluster ${CLUSTER}..."
  kind delete cluster --name "${CLUSTER}"
}

cmd_status() {
  echo "=== pods (${NS}) ==="
  kubectl get pods -n "${NS}" 2>/dev/null
  echo
  echo "=== ingress ==="
  kubectl get ingress -n "${NS}" 2>/dev/null
}

cmd_test() {
  BASE=http://localhost
  H="Host: ticketing.local"

  echo "--- register ---"
  curl -s -H "$H" -H 'Content-Type: application/json' -X POST "$BASE/api/auth/register" \
    -d '{"email":"smoke@test.com","password":"Test123!","role":"USER"}' | head -c 200; echo

  echo "--- login ---"
  TOKEN=$(curl -s -H "$H" -H 'Content-Type: application/json' -X POST "$BASE/api/auth/login" \
    -d '{"email":"smoke@test.com","password":"Test123!"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['accessToken'])")
  echo "token: ${TOKEN:0:40}..."

  echo "--- protected ---"
  for p in /api/tickets /api/solutions /api/knowledge /api/rewards/leaderboard; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "$H" -H "Authorization: Bearer $TOKEN" "$BASE$p")
    printf "  %-28s %s\n" "$p" "$code"
  done

  echo "--- unauthorized ---"
  for p in /api/tickets /api/solutions; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "$H" "$BASE$p")
    printf "  %-28s %s\n" "$p" "$code"
  done
}

case "${1:-}" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  test)   cmd_test ;;
  *) echo "usage: $0 {up|down|status|test}"; exit 1 ;;
esac
