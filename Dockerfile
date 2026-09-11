FROM golang:1.22-alpine AS launcher-builder

WORKDIR /src
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/launcher .


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

# Download 3x-ui while building the image
RUN set -eux; \
    curl -fL --retry 3 --connect-timeout 20 \
      "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz" \
      -o /tmp/xui.tar.gz; \
    tar -xzf /tmp/xui.tar.gz -C /app; \
    test -f /app/x-ui/x-ui; \
    chmod +x /app/x-ui/x-ui; \
    if [ -d /app/x-ui/bin ]; then find /app/x-ui/bin -type f -exec chmod +x {} \;; fi; \
    rm -f /tmp/xui.tar.gz

# main.go forces the DB/log folder to /app/data.
# Redirect that path to writable temporary storage.
RUN rm -rf /app/data \
    && ln -s /tmp/xui-data /app/data

COPY --from=launcher-builder /out/launcher /usr/local/bin/launcher

# Put Xray's working directory somewhere writable.
ENV XUI_BIN_FOLDER=/tmp/xui-bin
ENV XUI_ENABLE_FAIL2BAN=false
ENV XUI_SKIP_HSTS=true

EXPOSE 2053

# IMPORTANT:
# Do NOT copy the large Xray/geosite/geoip files into /tmp.
# Symlink them instead, leaving free space for config + database.
CMD ["sh", "-c", "mkdir -p /tmp/xui-data/logs /tmp/xui-bin; for f in /app/x-ui/bin/*; do ln -sf \"$f\" \"/tmp/xui-bin/$(basename \"$f\")\"; done; exec /usr/local/bin/launcher"]
