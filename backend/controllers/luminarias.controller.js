const pool = require('../models/db');

// GET /luminarias?latitud=&longitud=&radio=
const getLuminarias = async (req, res) => {
  const { latitud, longitud, radio = 500 } = req.query;

  if (!latitud || !longitud) {
    return res.status(400).json({ error: 'Se requieren latitud y longitud' });
  }

  try {
    const resultado = await pool.query(
      `SELECT id, calle, colonia, estado,
       ST_X(geom) as longitud, ST_Y(geom) as latitud,
       ST_Distance(
         geom::geography,
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
       ) as distancia_metros
       FROM luminarias
       WHERE ST_DWithin(
         geom::geography,
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
         $3
       )
       ORDER BY distancia_metros ASC
       LIMIT 100`,
      [longitud, latitud, radio]
    );

    res.json({
      total: resultado.rows.length,
      luminarias: resultado.rows
    });
  } catch (error) {
    console.error('Error en getLuminarias:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// PUT /luminarias/:id/estado
const actualizarEstado = async (req, res) => {
  const { id } = req.params;
  const { estado } = req.body;

  const estadosValidos = ['operativa', 'fundida', 'en_reparacion'];
  if (!estadosValidos.includes(estado)) {
    return res.status(400).json({ error: `Estado inválido. Opciones: ${estadosValidos.join(', ')}` });
  }

  try {
    const resultado = await pool.query(
      'UPDATE luminarias SET estado = $1, ultima_actualizacion = NOW() WHERE id = $2 RETURNING *',
      [estado, id]
    );

    if (resultado.rows.length === 0) {
      return res.status(404).json({ error: 'Luminaria no encontrada' });
    }

    res.json(resultado.rows[0]);
  } catch (error) {
    console.error('Error en actualizarEstado:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { getLuminarias, actualizarEstado };