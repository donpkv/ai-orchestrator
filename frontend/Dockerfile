FROM node:20-alpine AS builder
WORKDIR /build

COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund

COPY index.html tsconfig.json vite.config.ts tailwind.config.js postcss.config.js ./
COPY src/ ./src/

RUN npm run build

FROM nginx:1.27-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /build/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN chown -R appuser:appgroup /usr/share/nginx/html /var/cache/nginx /var/log/nginx /etc/nginx/conf.d \
    && touch /var/run/nginx.pid \
    && chown appuser:appgroup /var/run/nginx.pid

USER appuser
EXPOSE 8083

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8083/ > /dev/null || exit 1

CMD ["nginx", "-g", "daemon off;"]
