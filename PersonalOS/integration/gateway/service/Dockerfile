FROM node:18-alpine
WORKDIR /app

# Python for OMEGA
RUN apk add --no-cache python3

COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production
COPY . .
EXPOSE 8080
CMD ["node","index.js"]
