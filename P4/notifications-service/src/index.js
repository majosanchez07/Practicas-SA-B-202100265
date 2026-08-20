require('dotenv').config();
const express = require('express');
const sequelize = require('./models/database');
const Notification = require('./models/notification');
const notificationsRouter = require('./routes/notifications');

const app = express();
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ mensaje: 'Notifications Service corriendo' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'notifications-service' });
});

app.use('/notifications', notificationsRouter);

async function startServer() {
  await sequelize.authenticate();
  await sequelize.sync({ alter: true });
  console.log('Base de datos conectada');

  const PORT = process.env.PORT || 8003;
  app.listen(PORT, () => {
    console.log(`Notifications Service corriendo en puerto ${PORT}`);
  });
}

startServer().catch(console.error);
