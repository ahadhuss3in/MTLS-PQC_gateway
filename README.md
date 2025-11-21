# MTLS Gateway (PQC-enabled, experimental)

## Overview
Lightweight gateway that proxies mutual-TLS Spring Boot services through `nginx` with experimental post-quantum-cryptography (PQC) support. The repository contains two Spring Boot services (`mtls-client`, `MTLS-fz`) and an `nginx` configuration + helper scripts to build/run a PQC-enabled nginx.

## Repository layout
- `docker-compose.yml` — compose definition for gateway and services
- `setup-pqc-nginx.sh` — prepare/build PQC-enabled nginx/OpenSSL (experimental)
- `start-pqc-gateway.sh`, `stop-pqc-gateway.sh` — quick start/stop scripts
- `mtls-client/` — client Spring Boot app (mvn wrapper included)
- `MTLS-fz/` — server Spring Boot app (mvn wrapper included)
- `nginx/`
  - `conf/nginx.conf` — nginx configuration
  - `certs/` — client/server certs used by examples

## Prerequisites (macOS)
1. Java 11+ and Maven (or use included `./mvnw` wrappers in subprojects).
2. Homebrew (optional) for installing Docker.
3. Docker Desktop (recommended) or Docker Engine + Docker Compose.

Install Docker Desktop via Homebrew:

```bash
brew install --cask docker
open /Applications/Docker.app
# wait until Docker is running (whale icon)
```

## Quick start
1. Ensure Docker is running.
2. Run the PQC setup script (this builds or prepares PQC-enabled nginx; may take time and is experimental):

```bash
chmod +x ./setup-pqc-nginx.sh
./setup-pqc-nginx.sh
```

3. Start the gateway and backend services:

```bash
chmod +x ./start-pqc-gateway.sh
./start-pqc-gateway.sh
# or: docker compose up --build
```

4. Stop services:

```bash
./stop-pqc-gateway.sh
# or: docker compose down
```

## Build services locally (optional)
To build the Spring Boot apps locally:

```bash
# build server
cd MTLS-fz
./mvnw clean package

# build client
cd ../mtls-client
./mvnw clean package
```

## Test the gateway
A simple `curl` example using the client certificate in `nginx/certs`:

```bash
curl --cert nginx/certs/client-cert.pem --key nginx/certs/client-key.pem -k https://localhost/server
```
Expected response: the server endpoint will return the secured payload.

## Notes about PQC enablement
- Enabling PQC requires a PQC-capable OpenSSL (e.g., OpenSSL built with liboqs) and nginx compiled against that OpenSSL. The repository provides `setup-pqc-nginx.sh` to automate this where possible.  
- This is experimental and may require manual adjustments per macOS environment and OpenSSL/nginx versions. Use the script output/logs for troubleshooting.

## Troubleshooting
- If Docker commands fail, confirm Docker Desktop is running.
- If nginx build fails during `setup-pqc-nginx.sh`, check logs printed by the script and ensure required build tools are installed (`gcc`, `make`, `autoconf`, etc.).
- mTLS issues: verify certificate paths in `nginx/conf/nginx.conf` and that services trust the CA in `nginx/certs/`.

## License
Project provided as-is. Review scripts before running in production.

