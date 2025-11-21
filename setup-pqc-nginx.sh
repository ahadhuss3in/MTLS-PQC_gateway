#!/bin/bash
set -e

echo "=== PQC-Enabled NGINX Setup for mTLS Gateway ==="
echo ""

# Directories
OQS_DIR="/tmp/oqs"
OQS_OPENSSL_DIR="/tmp/oqs-openssl"
NGINX_DIR="/tmp/nginx-oqs"
INSTALL_PREFIX="$HOME/.local/pqc-nginx"
CERT_DIR="$INSTALL_PREFIX/certs"

echo "Step 1: Installing dependencies..."
# Check for Homebrew on macOS
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew not found. Please install it first."
    exit 1
fi

brew install cmake ninja astyle wget autoconf automake libtool

echo ""
echo "Step 2: Building liboqs..."
rm -rf "$OQS_DIR"
git clone --depth 1 --branch main https://github.com/open-quantum-safe/liboqs.git "$OQS_DIR"
cd "$OQS_DIR"
mkdir -p build && cd build
cmake -GNinja -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DBUILD_SHARED_LIBS=ON ..
ninja
ninja install

echo ""
echo "Step 3: Building OQS-OpenSSL..."
rm -rf "$OQS_OPENSSL_DIR"
git clone --depth 1 --branch OQS-OpenSSL_1_1_1-stable https://github.com/open-quantum-safe/openssl.git "$OQS_OPENSSL_DIR"
cd "$OQS_OPENSSL_DIR"
./Configure no-shared darwin64-x86_64-cc -lm --prefix="$INSTALL_PREFIX/oqs-openssl"
make -j$(sysctl -n hw.ncpu)
make install_sw

echo ""
echo "Step 4: Building NGINX with OQS-OpenSSL..."
rm -rf "$NGINX_DIR"
wget -O /tmp/nginx.tar.gz http://nginx.org/download/nginx-1.24.0.tar.gz
mkdir -p "$NGINX_DIR"
tar -xzf /tmp/nginx.tar.gz -C /tmp/
mv /tmp/nginx-1.24.0 "$NGINX_DIR"
cd "$NGINX_DIR"

./configure \
    --prefix="$INSTALL_PREFIX/nginx" \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-cc-opt="-I$INSTALL_PREFIX/include" \
    --with-ld-opt="-L$INSTALL_PREFIX/lib" \
    --with-openssl="$OQS_OPENSSL_DIR"

make -j$(sysctl -n hw.ncpu)
make install

echo ""
echo "Step 5: Converting Java keystores to PEM format..."
mkdir -p "$CERT_DIR"

# Server cert and key
openssl pkcs12 -in "$PWD/../MTLS-fz/src/main/resources/server-keystore.p12" \
    -nocerts -nodes -passin pass:password -out "$CERT_DIR/server-key.pem"
openssl pkcs12 -in "$PWD/../MTLS-fz/src/main/resources/server-keystore.p12" \
    -clcerts -nokeys -passin pass:password -out "$CERT_DIR/server-cert.pem"

# CA cert for client verification
keytool -importkeystore \
    -srckeystore "$PWD/../MTLS-fz/src/main/resources/server-truststore.jks" \
    -srcstorepass password \
    -destkeystore "$CERT_DIR/trust.p12" \
    -deststoretype PKCS12 \
    -deststorepass password
openssl pkcs12 -in "$CERT_DIR/trust.p12" -nokeys -out "$CERT_DIR/ca.pem" -passin pass:password

# Client cert and key for NGINX -> backend mTLS
openssl pkcs12 -in "$PWD/../mtls-client/src/main/resources/client-keystore.p12" \
    -nocerts -nodes -passin pass:password -out "$CERT_DIR/client-key.pem"
openssl pkcs12 -in "$PWD/../mtls-client/src/main/resources/client-keystore.p12" \
    -clcerts -nokeys -passin pass:password -out "$CERT_DIR/client-cert.pem"

echo ""
echo "Step 6: Creating NGINX configuration..."
cat > "$INSTALL_PREFIX/nginx/conf/nginx.conf" <<'NGINXCONF'
worker_processes  auto;
error_log  logs/error.log info;
pid        logs/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for" '
                      'SSL: $ssl_protocol $ssl_cipher';

    access_log  logs/access.log  main;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen 8443 ssl;
        server_name localhost;

        # PQC-enabled TLS (via OQS-OpenSSL)
        ssl_certificate     CERT_DIR_PLACEHOLDER/server-cert.pem;
        ssl_certificate_key CERT_DIR_PLACEHOLDER/server-key.pem;

        # Client certificate verification (mTLS)
        ssl_client_certificate CERT_DIR_PLACEHOLDER/ca.pem;
        ssl_verify_client on;
        ssl_verify_depth 10;

        # Use TLS 1.3 for PQ KEMs
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # Proxy to Spring Boot backend
        location / {
            proxy_pass https://127.0.0.1:8080;

            # NGINX -> backend mTLS
            proxy_ssl_certificate      CERT_DIR_PLACEHOLDER/client-cert.pem;
            proxy_ssl_certificate_key  CERT_DIR_PLACEHOLDER/client-key.pem;
            proxy_ssl_trusted_certificate CERT_DIR_PLACEHOLDER/ca.pem;
            proxy_ssl_verify on;
            proxy_ssl_server_name on;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Client-DN $ssl_client_s_dn;
        }
    }
}
NGINXCONF

# Replace placeholder with actual cert directory
sed -i.bak "s|CERT_DIR_PLACEHOLDER|$CERT_DIR|g" "$INSTALL_PREFIX/nginx/conf/nginx.conf"
rm "$INSTALL_PREFIX/nginx/conf/nginx.conf.bak"

echo ""
echo "Step 7: Creating startup scripts..."

cat > "$INSTALL_PREFIX/start-nginx.sh" <<STARTSCRIPT
#!/bin/bash
export DYLD_LIBRARY_PATH="$INSTALL_PREFIX/lib:\$DYLD_LIBRARY_PATH"
"$INSTALL_PREFIX/nginx/sbin/nginx" -c "$INSTALL_PREFIX/nginx/conf/nginx.conf"
echo "NGINX started on https://localhost:8443"
echo "Check logs: tail -f $INSTALL_PREFIX/nginx/logs/error.log"
STARTSCRIPT

cat > "$INSTALL_PREFIX/stop-nginx.sh" <<STOPSCRIPT
#!/bin/bash
"$INSTALL_PREFIX/nginx/sbin/nginx" -s stop
echo "NGINX stopped"
STOPSCRIPT

chmod +x "$INSTALL_PREFIX/start-nginx.sh"
chmod +x "$INSTALL_PREFIX/stop-nginx.sh"

echo ""
echo "=========================================="
echo "✓ PQC-enabled NGINX installation complete!"
echo "=========================================="
echo ""
echo "Installation directory: $INSTALL_PREFIX"
echo ""
echo "Next steps:"
echo "1. Start your Spring Boot backend on port 8080"
echo "2. Start NGINX: $INSTALL_PREFIX/start-nginx.sh"
echo "3. Update Java client to use https://localhost:8443"
echo ""
echo "To verify PQC is working:"
echo "  $INSTALL_PREFIX/oqs-openssl/bin/openssl s_client -connect localhost:8443 -tls1_3"
echo ""
p