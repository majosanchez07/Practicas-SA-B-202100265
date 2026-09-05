/**
 * Conexion a PostgreSQL.
 *
 * En la Practica 4 cada microservicio tenia su propia instancia de Postgres.
 * En la Practica 5 hay una sola instancia desplegada como StatefulSet y cada
 * servicio queda aislado en su propio schema: se conserva la separacion logica
 * entre microservicios con un unico PVC y un unico headless service.
 */
const { Sequelize } = require('sequelize');

const DB_SCHEMA = process.env.DB_SCHEMA || 'loans';

const sequelize = new Sequelize(process.env.DATABASE_URL, {
  dialect: 'postgres',
  logging: process.env.LOG_LEVEL === 'debug' ? console.log : false,
  schema: DB_SCHEMA,
  pool: { max: 5, min: 0, acquire: 30000, idle: 10000 },
  retry: { max: 3 }
});

/** Idempotente: varias replicas pueden ejecutarlo en paralelo sin romperse. */
async function crearSchemaSiNoExiste() {
  await sequelize.createSchema(DB_SCHEMA, {}).catch((err) => {
    if (!/already exists/i.test(err.message)) throw err;
  });
}

module.exports = sequelize;
module.exports.crearSchemaSiNoExiste = crearSchemaSiNoExiste;
module.exports.DB_SCHEMA = DB_SCHEMA;
