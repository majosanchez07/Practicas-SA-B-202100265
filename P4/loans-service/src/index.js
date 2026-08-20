require('dotenv').config();
const express = require('express');
const { ApolloServer } = require('apollo-server-express');
const sequelize = require('./models/database');
const typeDefs = require('./graphql/schema');
const resolvers = require('./graphql/resolvers');
const Loan = require('./models/loan');

async function startServer() {
  const app = express();

  const server = new ApolloServer({ typeDefs, resolvers });
  await server.start();
  server.applyMiddleware({ app, path: '/graphql' });

  app.get('/', (req, res) => {
    res.json({ mensaje: 'Loans Service corriendo', graphql: '/graphql' });
  });

  app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'loans-service' });
  });

  await sequelize.authenticate();
  await sequelize.sync({ alter: true });
  console.log('Base de datos conectada');

  const PORT = process.env.PORT || 8002;
  app.listen(PORT, () => {
    console.log(`Loans Service corriendo en puerto ${PORT}`);
    console.log(`GraphQL en http://localhost:${PORT}/graphql`);
  });
}

startServer().catch(console.error);
