require('dotenv').config();
const express = require('express');
const sequelize = require('./models/database');
const Notification = require('./models/notification');
const Resumen = require('./models/resumen');
const notificationsRouter = require('./routes/notifications');
const { registrarHealth } = require('./health');
const consumer = require('./consumer');

const app = express();
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ mensaje: 'Notifications Service corriendo' });
});

registrarHealth(app, sequelize, 'notifications-service');

app.use('/notifications', notificationsRouter);

async function startServer() {
  await sequelize.authenticate();
  await sequelize.crearSchemaSiNoExiste();
  await sequelize.sync();
  console.log(`Base de datos conectada (schema: ${sequelize.DB_SCHEMA})`);

  // El consumidor arranca despues de la BD: si empezara antes, procesaria
  // mensajes sin poder persistirlos y los mandaria a la DLQ sin necesidad.
  await consumer.iniciar();

  const PORT = process.env.PORT || 8003;
  app.listen(PORT, () => {
    console.log(`Notifications Service corriendo en puerto ${PORT}`);
  });
}

startServer().catch(console.error);
