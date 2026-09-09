# Build stage - compile Flutter web
FROM cirrusci/flutter:latest AS builder

WORKDIR /app
COPY . .

RUN flutter pub get
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
