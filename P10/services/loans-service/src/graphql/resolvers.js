const Loan = require('../models/loan');
const broker = require('../broker');
const { GraphQLError } = require('graphql');
const { consultarLibro, CatalogoNoDisponible } = require('../catalogo');
const metricas = require('../metricas');
const log = require('../logger');

/**
 * Practica 10: rechaza la solicitud dejando las tres senales coherentes: un
 * registro con trace_id, la metrica de negocio con su motivo y un error
 * GraphQL con codigo.
 */
function rechazar(motivo, mensaje, campos, nivel = 'warn') {
  metricas.prestamoRechazado(motivo);
  log[nivel]('prestamo rechazado', { motivo, ...campos });
  throw new GraphQLError(mensaje, { extensions: { code: motivo } });
}

const resolvers = {
  Query: {
    loans: async () => {
      return await Loan.findAll();
    },
    loan: async (_, { id }) => {
      return await Loan.findByPk(id);
    },
    loansByUser: async (_, { userId }) => {
      return await Loan.findAll({ where: { userId } });
    }
  },
  Mutation: {
    createLoan: async (_, { userId, bookId }) => {
      let libro;
      try {
        libro = await consultarLibro(bookId);
      } catch (err) {
        if (!(err instanceof CatalogoNoDisponible)) throw err;
        rechazar('catalogo_no_disponible', 'El catalogo no esta disponible',
          { userId, bookId, error: err.message }, 'error');
      }
      if (!libro) rechazar('libro_no_existe', 'El libro no existe', { userId, bookId });
      if (!libro.available) rechazar('libro_no_disponible', 'El libro no esta disponible', { userId, bookId });

      const prestamo = await Loan.create({ userId, bookId, status: 'active' });
      metricas.prestamoCreado();
      log.info('prestamo creado', { loanId: prestamo.id, userId, bookId });

      // Flujo asincrono: se publica el evento y se retorna de inmediato.
      // La notificacion al usuario la genera notifications-service por su
      // cuenta; loans-service no espera ni depende de que ese servicio este
      // arriba para responderle al cliente.
      broker.publicarPrestamoCreado(prestamo);

      return prestamo;
    },
    returnLoan: async (_, { id }) => {
      const loan = await Loan.findByPk(id);
      if (!loan) return null;
      loan.returnDate = new Date();
      loan.status = 'returned';
      await loan.save();
      return loan;
    }
  }
};

module.exports = resolvers;
