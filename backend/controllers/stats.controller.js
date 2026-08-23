const pool = require('../models/db');

// GET /users/:id/stats — Estadísticas y TrustScore personal del usuario
const getStats = async (req, res) => {
  const { id } = req.params;

  try {
    // Total de reportes del usuario
    const totalResult = await pool.query(
      'SELECT COUNT(*) as total FROM reportes WHERE usuario_id = $1',
      [id]
    );

    // Reportes por estado
    const estadosResult = await pool.query(
      `SELECT estado, COUNT(*) as cantidad 
       FROM reportes WHERE usuario_id = $1 
       GROUP BY estado`,
      [id]
    );

    // Categoría más reportada
    const categoriaResult = await pool.query(
      `SELECT categoria, COUNT(*) as cantidad 
       FROM reportes WHERE usuario_id = $1 
       GROUP BY categoria 
       ORDER BY cantidad DESC 
       LIMIT 1`,
      [id]
    );

    // TrustScore promedio de sus reportes verificados
    const trustResult = await pool.query(
      `SELECT AVG(trust_score) as trust_promedio 
       FROM reportes 
       WHERE usuario_id = $1 AND estado = 'verificado'`,
      [id]
    );

    // Historial de confianza del usuario
    const usuarioResult = await pool.query(
      'SELECT historial_confianza FROM usuarios WHERE id = $1',
      [id]
    );

    const total = parseInt(totalResult.rows[0].total);
    const estados = {};
    estadosResult.rows.forEach(r => {
      estados[r.estado] = parseInt(r.cantidad);
    });

    const trustPromedio = parseFloat(trustResult.rows[0]?.trust_promedio) || 0;
    const historialConfianza = parseFloat(usuarioResult.rows[0]?.historial_confianza) || 1.0;

    res.json({
      total_reportes: total,
      reportes_verificados: estados['verificado'] || 0,
      reportes_pendientes: estados['pendiente'] || 0,
      reportes_rechazados: estados['rechazado'] || 0,
      categoria_mas_reportada: categoriaResult.rows[0]?.categoria || null,
      trust_score_promedio: Math.round(trustPromedio * 100) / 100,
      historial_confianza: historialConfianza,
      nivel_confianza: historialConfianza >= 0.8 ? 'Alto' : historialConfianza >= 0.5 ? 'Medio' : 'Bajo',
    });

  } catch (error) {
    console.error('Error en getStats:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { getStats };