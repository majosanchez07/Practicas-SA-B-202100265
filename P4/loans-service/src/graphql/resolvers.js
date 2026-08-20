const Loan = require('../models/loan');

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
      return await Loan.create({ userId, bookId, status: 'active' });
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
