FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production
COPY worker.js .
EXPOSE 9101
CMD ["node","worker.js"]
