require('dotenv').config();
const express = require('express');
const { ApolloServer } = require('apollo-server-express');
const sequelize = require('./models/database');
const typeDefs = require('./graphql/schema');
const resolvers = require('./graphql/resolvers');
const Loan = require('./models/loan');
const { registrarHealth } = require('./health');
const broker = require('./broker');

async function startServer() {
  const app = express();

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
  console.log(`Base de datos conectada (schema: ${sequelize.DB_SCHEMA})`);

  // No se espera a la conexion con el broker: el servicio queda listo para
  // atender peticiones y la conexion se establece en segundo plano en cuanto
  // RabbitMQ este disponible.
  broker.conectar().catch((err) => {
    console.error('[broker] no se pudo conectar:', err.message);
  });

  const PORT = process.env.PORT || 8002;
  app.listen(PORT, () => {
    console.log(`Loans Service corriendo en puerto ${PORT}`);
    console.log(`GraphQL en http://localhost:${PORT}/graphql`);
  });
}

startServer().catch(console.error);
