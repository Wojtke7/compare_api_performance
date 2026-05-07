#!/usr/bin/env bash
# Uruchom z katalogu repo lub z local/: stack musi działać (docker compose up).
# Uruchamiaj jako: bash load.sh … lub ./load.sh … (wymaga bash; nie: sh load.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Ten sam plik co w K8s: mount /ca.pem — tester bez niego zgłasza NotFound.
CA_PEM="$ROOT/local/load/ca.pem"

# Domyślnie: jeśli istnieje sieć local_default (typowo: cd local && docker compose up),
# jedź po DNS serwisów wewnątrz Dockera — na Macu dużo mniej timeoutów niż host.docker.internal.
# Wyłączenie: LOAD_DOCKER_NETWORK=off bash load.sh docker-all
_load_net="${LOAD_DOCKER_NETWORK:-}"
if [ "$_load_net" = "off" ] || [ "$_load_net" = "0" ]; then
  _load_net=""
elif [ -z "$_load_net" ] && docker network inspect local_default >/dev/null 2>&1; then
  _load_net="local_default"
fi

if [ -n "$_load_net" ]; then
  DOCKER_NET=( --network "$_load_net" )
  URL_REST="http://rest-server:8080/api/devices"
  URL_GRAPHQL="http://graphql-server:8080/query"
  URL_GRPC="http://grpc-server:8080"
  echo "(load) Używam sieci Docker: $_load_net (wewnętrzne URL-e, bez host.docker.internal)" >&2
else
  DOCKER_NET=()
  _host="${LOAD_HOST:-host.docker.internal}"
  URL_REST="http://${_host}:8080/api/devices"
  URL_GRAPHQL="http://${_host}:8084/query"
  URL_GRPC="http://${_host}:8082"
  echo "(load) Używam hosta: ${_host} + porty z mapowania (wolniejsze przy dużym loadzie)" >&2
fi

cmd="${1:-help}"

case "$cmd" in
hey-rest)
  command -v hey >/dev/null || { echo "Zainstaluj: brew install hey"; exit 1; }
  echo "REST GET 30s / 50 rownoleglych -> http://127.0.0.1:8080/api/devices"
  hey -z 30s -c 50 http://127.0.0.1:8080/api/devices
  ;;
docker-rest)
  echo "Tester jak w K8s (obraz quay.io/aputra/tester:v1) -> REST"
  docker run --rm \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/rest-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_REST" \
    quay.io/aputra/tester:v1
  ;;
docker-graphql)
  echo "Tester -> GraphQL POST /query"
  docker run --rm \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/graphql-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_GRAPHQL" \
    quay.io/aputra/tester:v1
  ;;
docker-grpc)
  echo "Tester-grpc -> grpc-server"
  docker run --rm \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/grpc-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_GRPC" \
    quay.io/aputra/tester-grpc:v4
  ;;
docker-all)
  echo "Start rownolegly: REST + GraphQL + gRPC"
  ec=0
  docker run --rm --name "compare-load-rest-$$" \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/rest-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_REST" \
    quay.io/aputra/tester:v1 &
  pid_rest=$!
  docker run --rm --name "compare-load-graphql-$$" \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/graphql-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_GRAPHQL" \
    quay.io/aputra/tester:v1 &
  pid_gql=$!
  docker run --rm --name "compare-load-grpc-$$" \
    "${DOCKER_NET[@]}" \
    -v "$ROOT/local/load/grpc-Tester.toml:/Tester.toml:ro" \
    -v "$CA_PEM:/ca.pem:ro" \
    -e TEST_URL="$URL_GRPC" \
    quay.io/aputra/tester-grpc:v4 &
  pid_grpc=$!
  wait "$pid_rest" || ec=1
  wait "$pid_gql" || ec=1
  wait "$pid_grpc" || ec=1
  if [ "$ec" -ne 0 ]; then
    echo "Co najmniej jeden tester zakonczyl sie bledem (exit != 0)." >&2
  fi
  exit "$ec"
  ;;
help|*)
  cat <<EOF
Użycie (stack: cd local && docker compose up -d):

  Na hoście — szybki dym (wymaga hey):
    bash $0 hey-rest

  Load testery (obrazy jak w tests/1-test):
    bash $0 docker-rest
    bash $0 docker-graphql
    bash $0 docker-grpc
    bash $0 docker-all

  Sieć: jeśli istnieje Docker network local_default, skrypt domyślnie
  łączy testery do rest-server / graphql-server / grpc-server po porcie 8080
  WEWNĄTRZ sieci (zalecane na Macu — mniej TIMEOUT niż host.docker.internal).

  Inna nazwa sieci (np. compose z innego katalogu):
    LOAD_DOCKER_NETWORK=moj_projekt_default bash $0 docker-all

  Wymuszenie starego trybu (host + porty 8080/8082/8084):
    LOAD_DOCKER_NETWORK=off LOAD_HOST=host.docker.internal bash $0 docker-all

  Zwiększ request_timeout_ms w local/load/*-Tester.toml jeśli nadal widzisz TIMEOUT.

Potem patrz Grafana / Prometheus (metryki compare_api_*).
EOF
  ;;
esac
