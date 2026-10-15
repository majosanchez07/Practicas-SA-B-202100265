const Loan = require('../models/loan');
const broker = require('../broker');

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
      const prestamo = await Loan.create({ userId, bookId, status: 'active' });

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
