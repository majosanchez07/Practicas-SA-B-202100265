const express = require('express');
const router = express.Router();
const Notification = require('../models/notification');
const Resumen = require('../models/resumen');

router.get('/', async (req, res) => {
  try {
    const notifications = await Notification.findAll();
    res.json(notifications);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/user/:userId', async (req, res) => {
  try {
    const notifications = await Notification.findAll({
      where: { userId: req.params.userId }
    });
    res.json(notifications);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const { userId, type, message } = req.body;
    const notification = await Notification.create({ userId, type, message });
    res.status(201).json(notification);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.patch('/:id/read', async (req, res) => {
  try {
    const notification = await Notification.findByPk(req.params.id);
    if (!notification) return res.status(404).json({ error: 'No encontrada' });
    notification.read = true;
    await notification.save();
    res.json(notification);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Evidencia del flujo asincrono completo: aqui se ven los resumenes que el
// Cronjob 2 publico en el broker y que este servicio consumio y almaceno.
router.get('/resumenes', async (req, res) => {
  try {
    const resumenes = await Resumen.findAll({ order: [['generadoEn', 'DESC']] });
    res.json(resumenes);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
