# Build stage
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Serve stage
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Angular 20 output path:
COPY --from=build /app/dist/summit-trace-ui/browser /usr/share/nginx/html