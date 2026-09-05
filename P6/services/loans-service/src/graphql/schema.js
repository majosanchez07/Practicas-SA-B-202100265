const { gql } = require('apollo-server-express');

const typeDefs = gql`
  type Loan {
    id: Int!
    userId: Int!
    bookId: Int!
    loanDate: String
    returnDate: String
    status: String!
  }

  type Query {
    loans: [Loan!]!
    loan(id: Int!): Loan
    loansByUser(userId: Int!): [Loan!]!
  }

  type Mutation {
    createLoan(userId: Int!, bookId: Int!): Loan!
    returnLoan(id: Int!): Loan
  }
`;

module.exports = typeDefs;
