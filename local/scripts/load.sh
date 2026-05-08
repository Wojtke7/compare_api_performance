#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CA_PEM="$ROOT/local/load/ca.pem"

cmd="${1:-help}"

_load_net="${LOAD_DOCKER_NETWORK:-}"
if [ "$_load_net" = "off" ] || [ "$_load_net" = "0" ]; then
  _load_net=""
elif [ -z "$_load_net" ] && docker network inspect local_default >/dev/null 2>&1; then
  _load_net="local_default"
fi

if [ -n "$_load_net" ]; then
  DOCKER_NET=(--network "$_load_net")
  URL_REST="http://rest-server:8080/api/devices"
  URL_GRAPHQL="http://graphql-server:8080/query"
  URL_GRPC="http://grpc-server:8080"
  echo "(load) Docker network: $_load_net (internal service URLs)" >&2
else
  DOCKER_NET=()
  _host="${LOAD_HOST:-host.docker.internal}"
  URL_REST="http://${_host}:8080/api/devices"
  URL_GRAPHQL="http://${_host}:8084/query"
  URL_GRPC="http://${_host}:8082"
  echo "(load) Host mode: ${_host} (published ports)" >&2
fi

run_rest() {
  docker run --rm \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/rest-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_REST" \
    "$@"
}

run_graphql() {
  docker run --rm \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/graphql-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_GRAPHQL" \
    "$@"
}

run_grpc() {
  docker run --rm \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/grpc-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_GRPC" \
    "$@"
}

run_parallel_once() {
  local suffix="${1}"
  local ec=0

  run_rest --name "compare-load-rest-${suffix}" quay.io/aputra/tester:v1 &
  local pid_rest=$!
  run_graphql --name "compare-load-graphql-${suffix}" quay.io/aputra/tester:v1 &
  local pid_gql=$!
  run_grpc --name "compare-load-grpc-${suffix}" quay.io/aputra/tester-grpc:v4 &
  local pid_grpc=$!

  wait "$pid_rest" || ec=1
  wait "$pid_gql" || ec=1
  wait "$pid_grpc" || ec=1
  return "$ec"
}

run_parallel_timed() {
  local round="${1}"
  local duration="${2}"
  local suffix="${$}-${round}"
  local ec=0

  echo "(load) Round ${round}: start REST + GraphQL + gRPC (duration: ${duration})"
  run_rest --name "compare-load-rest-${suffix}" quay.io/aputra/tester:v1 &
  local pid_rest=$!
  run_graphql --name "compare-load-graphql-${suffix}" quay.io/aputra/tester:v1 &
  local pid_gql=$!
  run_grpc --name "compare-load-grpc-${suffix}" quay.io/aputra/tester-grpc:v4 &
  local pid_grpc=$!

  (
    sleep "$duration"
    docker stop "compare-load-rest-${suffix}" "compare-load-graphql-${suffix}" "compare-load-grpc-${suffix}" >/dev/null 2>&1 || true
  ) &
  local stopper_pid=$!

  wait "$pid_rest" || ec=1
  wait "$pid_gql" || ec=1
  wait "$pid_grpc" || ec=1
  wait "$stopper_pid" || true
  return "$ec"
}

run_cycles() {
  local rounds="${LOAD_ROUNDS:-3}"
  local duration="${LOAD_DURATION:-2h}"
  local cooldown="${LOAD_COOLDOWN:-10m}"
  local i=1
  local ec=0

  while [ "$i" -le "$rounds" ]; do
    run_parallel_timed "$i" "$duration" || ec=1
    if [ "$i" -lt "$rounds" ]; then
      echo "(load) Cooldown after round ${i}: ${cooldown}"
      sleep "$cooldown"
    fi
    i=$((i + 1))
  done
  return "$ec"
}

case "$cmd" in
hey-rest)
  command -v hey >/dev/null || { echo "Install: brew install hey"; exit 1; }
  echo "REST GET 30s / 50 concurrent -> http://127.0.0.1:8080/api/devices"
  hey -z 30s -c 50 http://127.0.0.1:8080/api/devices
  ;;
docker-rest)
  echo "REST tester"
  run_rest quay.io/aputra/tester:v1
  ;;
docker-graphql)
  echo "GraphQL tester"
  run_graphql quay.io/aputra/tester:v1
  ;;
docker-grpc)
  echo "gRPC tester"
  run_grpc quay.io/aputra/tester-grpc:v4
  ;;
docker-once)
  echo "Single parallel run: REST + GraphQL + gRPC"
  run_parallel_once "$$"
  ;;
docker-all)
  echo "Cyclic mode: default is 3 rounds x 2h + cooldown 10m"
  run_cycles
  ;;
help|*)
  cat <<EOF
Usage (stack: cd local && docker compose up -d):

  On host — quick smoke test (requires hey):
    bash $0 hey-rest

  Load testers (same images as in tests/1-test):
    bash $0 docker-rest
    bash $0 docker-graphql
    bash $0 docker-grpc
    bash $0 docker-once
    bash $0 docker-all

  docker-all:
    Runs 3 rounds by default.
    Each round runs for 2h, then cooldown 10m, then next round.
    You can override timing and number of rounds:
      LOAD_ROUNDS=3 LOAD_DURATION=2h LOAD_COOLDOWN=10m bash $0 docker-all

  Different Docker network name (for example when compose runs elsewhere):
    LOAD_DOCKER_NETWORK=moj_projekt_default bash $0 docker-all

  Force host mode (host + ports 8080/8082/8084):
    LOAD_DOCKER_NETWORK=off LOAD_HOST=host.docker.internal bash $0 docker-all

  Increase request_timeout_ms in local/load/*-Tester.toml if you still see TIMEOUT.

Then check Grafana / Prometheus (compare_api_* metrics).
EOF
  ;;
esac
