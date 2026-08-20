require('dotenv').config();
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
app.use(express.json());

const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-service:8000';
const BOOKS_SERVICE_URL = process.env.BOOKS_SERVICE_URL || 'http://books-service:8001';
const LOANS_SERVICE_URL = process.env.LOANS_SERVICE_URL || 'http://loans-service:8002';
const NOTIFICATIONS_SERVICE_URL = process.env.NOTIFICATIONS_SERVICE_URL || 'http://notifications-service:8003';

app.get('/', (req, res) => {
  res.json({
    mensaje: 'API Gateway - Biblioteca',
    version: '1.0.0',
    servicios: {
      auth: '/auth',
      books: '/books',
      loans: '/loans',
      notifications: '/notifications'
    }
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'api-gateway' });
});

app.use('/auth', createProxyMiddleware({
  target: AUTH_SERVICE_URL,
  changeOrigin: true,
  pathRewrite: { '^/auth': '' },
  on: {
    error: (err, req, res) => {
      res.status(502).json({ error: 'Auth service no disponible', detalle: err.message });
    }
  }
}));

app.use('/books', createProxyMiddleware({
  target: BOOKS_SERVICE_URL,
  changeOrigin: true,
  pathRewrite: { '^/books': '' },
  on: {
    error: (err, req, res) => {
      res.status(502).json({ error: 'Books service no disponible', detalle: err.message });
    }
  }
}));

app.use('/loans', createProxyMiddleware({
  target: LOANS_SERVICE_URL,
  changeOrigin: true,
  pathRewrite: { '^/loans': '' },
  on: {
    error: (err, req, res) => {
      res.status(502).json({ error: 'Loans service no disponible', detalle: err.message });
    }
  }
}));

app.use('/notifications', createProxyMiddleware({
  target: NOTIFICATIONS_SERVICE_URL,
  changeOrigin: true,
  pathRewrite: { '^/notifications': '' },
  on: {
    error: (err, req, res) => {
      res.status(502).json({ error: 'Notifications service no disponible', detalle: err.message });
    }
  }
}));

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`API Gateway corriendo en puerto ${PORT}`);
  console.log(`Auth Service     -> ${AUTH_SERVICE_URL}`);
  console.log(`Books Service    -> ${BOOKS_SERVICE_URL}`);
  console.log(`Loans Service    -> ${LOANS_SERVICE_URL}`);
  console.log(`Notifications    -> ${NOTIFICATIONS_SERVICE_URL}`);
});
