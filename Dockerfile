# =============================================================================
# Dockerfile — task_manager_admin_panel (Flutter Web + Nginx)
# =============================================================================

# ── Stage 1: Build Flutter Web ────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Enable web target
RUN flutter config --enable-web

# Cache dependencies
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Precache web SDK
RUN flutter precache --web

# Copy full source
COPY . .

# Build with configurable backend URL
ARG BACKEND_URL=https://appacademia-production-be7e.up.railway.app
RUN echo "Building with BACKEND_URL=${BACKEND_URL}" && \
    flutter build web --release --no-tree-shake-icons \
        --dart-define=BACKEND_URL=${BACKEND_URL} && \
    echo "✅ Build OK"

# Runtime stage - serve with nginx
FROM nginx:alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built Flutter web app
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 8080
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
