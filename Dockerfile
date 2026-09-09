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

# Build Flutter web
RUN flutter build web --release --no-tree-shake-icons

# Runtime stage - serve with nginx
FROM nginx:alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built Flutter web app
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
