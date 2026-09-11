# Build the small Go launcher/reverse-proxy from the fork
FROM golang:1.22-alpine AS launcher-builder

WORKDIR /src
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/launcher .

# Runtime image
FROM alpine:3.22

RUN apk add --no-cache \
    ca-certificates \
    curl \
    tar \
    gzip \
    bash \
    tzdata \
    openssl

WORKDIR /app

# Download 3x-ui at IMAGE BUILD time, not when the container starts.
# This prevents the Deplexo /app/x-ui name collision that caused:
# open /app/x-ui/x-ui: no such file or directory
RUN set -eux; \
    curl -fL --retry 3 --connect-timeout 20 \
      "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz" \
      -o /tmp/xui.tar.gz; \
    tar -xzf /tmp/xui.tar.gz -C /app; \
    test -f /app/x-ui/x-ui; \
    chmod +x /app/x-ui/x-ui; \
    if [ -d /app/x-ui/bin ]; then find /app/x-ui/bin -type f -exec chmod +x {} \;; fi; \
    rm -f /tmp/xui.tar.gz

COPY --from=launcher-builder /out/launcher /usr/local/bin/launcher

# Deplexo routes public traffic to this port.
EXPOSE 2053

# The original main.go starts /app/x-ui/x-ui and proxies:
# /           -> panel on 20530
# /xvpnws/    -> VLESS/WS on 20868
# /sub/       -> subscription on 2096
CMD ["/usr/local/bin/launcher"]
