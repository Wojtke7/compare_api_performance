# README local / VM

This document explains how to run the full benchmark stack with Docker Compose:
- REST, gRPC, GraphQL (`myapp`)
- PostgreSQL
- Prometheus
- Grafana
- load generators (`local/scripts/load.sh`)

## 1) Requirements

- Docker Engine
- Docker Compose (`docker compose`)
- (optional) `hey` for a quick REST smoke test from host

## 2) Run locally

From the repository root:

```bash
cd local
docker compose up -d --build
```

Check status:

```bash
docker compose ps
```

## 3) Endpoints

- REST: `http://localhost:8080/api/devices`
- gRPC: `localhost:8082`
- GraphQL: `http://localhost:8084/query`
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000` (default login: `admin` / `admin`)

## 4) Run load tests

From the `local` directory:

```bash
bash scripts/load.sh docker-rest
bash scripts/load.sh docker-graphql
bash scripts/load.sh docker-grpc
bash scripts/load.sh docker-all
```

Help:

```bash
bash scripts/load.sh help
```

Load config files:
- `local/load/rest-Tester.toml`
- `local/load/graphql-Tester.toml`
- `local/load/grpc-Tester.toml`

## 5) Run on a VM

### 5.1 Copy project (without git on VM)

On your local machine:

```bash
rsync -av --exclude .git /path/to/compare_api_performance/ user@VM:~/compare_api_performance/
```

### 5.2 Start stack on VM

After SSH into the VM:

```bash
cd ~/compare_api_performance/local
docker compose up -d --build
docker compose ps
```

## 6) SSH tunneling for Grafana and Prometheus

If you do not want to expose public ports, use SSH tunnels.

On your local machine:

```bash
# Grafana (local port 3300 -> VM:3000)
ssh -L 3300:localhost:3000 user@VM
```

Then open:
- Grafana: `http://localhost:3300`

For Grafana + Prometheus in one tunnel:

```bash
ssh -L 3300:localhost:3000 -L 9090:localhost:9090 user@VM
```

Then open:
- Grafana: `http://localhost:3300`
- Prometheus: `http://localhost:9090`

