/**
 * Consulta de disponibilidad al catalogo (books-service).
 *
 * Practica 10: antes de registrar un prestamo se verifica que el libro exista
 * y este disponible. Ademas de ser una regla de negocio razonable, crea la
 * cadena gateway -> loans-service -> books-service que la practica exige
 * seguir bajo un unico identificador de traza: axios usa el modulo http, que
 * OpenTelemetry instrumenta, de modo que el traceparent se inyecta solo.
 */
const axios = require('axios');

const BOOKS_SERVICE_URL = process.env.BOOKS_SERVICE_URL || 'http://books-service:8001';
const TIMEOUT_MS = Number(process.env.CATALOGO_TIMEOUT_MS || 3000);

class CatalogoNoDisponible extends Error {}

async function consultarLibro(bookId) {
  let data;
  try {
    ({ data } = await axios.post(
      `${BOOKS_SERVICE_URL}/graphql`,
      { query: 'query($id:Int!){ book(id:$id){ id title available } }', variables: { id: bookId } },
      { timeout: TIMEOUT_MS },
    ));
  } catch (err) {
    throw new CatalogoNoDisponible(err.message);
  }
  if (data.errors) throw new CatalogoNoDisponible(data.errors[0].message);
  return data.data.book;
}

module.exports = { consultarLibro, CatalogoNoDisponible };
