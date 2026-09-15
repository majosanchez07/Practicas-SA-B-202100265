/**
 * Endpoints de salud diferenciados para las probes de Kubernetes.
 *
 * liveness  -> solo confirma que el event loop responde. No toca la base de
 *              datos: si lo hiciera, una caida temporal de Postgres provocaria
 *              que Kubernetes reiniciara el pod, lo cual no arregla nada.
 * readiness -> confirma que ademas puede atender trafico real (BD accesible).
 *              Al fallar, el pod sale del balanceo pero sigue vivo.
 */
function registrarHealth(app, sequelize, nombreServicio) {
  app.get('/health/live', (req, res) => {
    res.json({ status: 'alive', service: nombreServicio });
  });

  app.get('/health/ready', async (req, res) => {
    try {
      await sequelize.authenticate();
      res.json({ status: 'ready', service: nombreServicio, database: 'up' });
    } catch (err) {
      res.status(503).json({
        status: 'not-ready',
        service: nombreServicio,
        database: 'down',
        detalle: err.message
      });
    }
  });

  // Alias de compatibilidad con la Practica 4.
  app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: nombreServicio });
  });
}

module.exports = { registrarHealth };
