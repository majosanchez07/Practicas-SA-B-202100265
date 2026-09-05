/**
 * Resumenes publicados por el Cronjob 2 y consumidos desde el broker.
 * Es el extremo final de la cadena que pide el enunciado:
 * Cronjob 1 -> BD -> Cronjob 2 -> broker -> notifications-service -> BD.
 */
const { DataTypes } = require('sequelize');
const sequelize = require('./database');

const Resumen = sequelize.define('Resumen', {
  id: {
    type: DataTypes.INTEGER,
    primaryKey: true,
    autoIncrement: true
  },
  generadoEn: {
    type: DataTypes.DATE,
    allowNull: false
  },
  carne: {
    type: DataTypes.STRING(20),
    allowNull: false
  },
  totalEjecuciones: {
    type: DataTypes.INTEGER,
    allowNull: false
  },
  detalle: {
    // Cantidad de ejecuciones por hora, tal como lo calcula el Cronjob 2.
    type: DataTypes.JSONB,
    allowNull: true
  }
}, {
  tableName: 'resumenes',
  timestamps: true
});

module.exports = Resumen;
