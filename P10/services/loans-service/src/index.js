require('dotenv').config();
const express = require('express');
const { ApolloServer } = require('apollo-server-express');
const sequelize = require('./models/database');
const typeDefs = require('./graphql/schema');
const resolvers = require('./graphql/resolvers');
const Loan = require('./models/loan');
const { registrarHealth } = require('./health');
const broker = require('./broker');
const log = require('./logger');
const { middlewareMetricas } = require('./metricas');

async function startServer() {
  const app = express();
  // Practica 10: antes de Apollo para medir tambien las peticiones GraphQL.
  app.use(middlewareMetricas);

  const server = new ApolloServer({ typeDefs, resolvers });
  await server.start();
  server.applyMiddleware({ app, path: '/graphql' });

  app.get('/', (req, res) => {
    res.json({ mensaje: 'Loans Service corriendo', graphql: '/graphql' });
  });

  registrarHealth(app, sequelize, 'loans-service');

  await sequelize.authenticate();
  await sequelize.crearSchemaSiNoExiste();
  await sequelize.sync();
  log.info('base de datos conectada', { schema: sequelize.DB_SCHEMA });

  // No se espera a la conexion con el broker: el servicio queda listo para
  // atender peticiones y la conexion se establece en segundo plano en cuanto
  // RabbitMQ este disponible.
  broker.conectar().catch((err) => {
    log.error('no se pudo conectar al broker', { error: err.message });
  });

  const PORT = process.env.PORT || 8002;
  app.listen(PORT, () => {
    log.info('loans-service iniciado', { port: Number(PORT), graphql: '/graphql' });
  });
}

startServer().catch((err) => {
  log.error('loans-service no pudo arrancar', { error: err.message });
  process.exit(1);
});
