const pool = require('../models/db');
const { notificarRutasAfectadas } = require('../services/notificaciones.service');

// POST /reportes — Crear reporte
const crearReporte = async (req, res) => {
  const { categoria, descripcion, latitud, longitud, evidencia_url = null } = req.body;
  const usuario_id = req.usuario.id;

  try {
    const resultado = await pool.query(
      `INSERT INTO reportes (usuario_id, categoria, descripcion, evidencia_url, geom)
       VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($5, $6), 4326))
       RETURNING id, categoria, descripcion, evidencia_url, trust_score, estado, created_at`,
      [usuario_id, categoria, descripcion, evidencia_url, longitud, latitud]
    );

    res.status(201).json(resultado.rows[0]);

    // Notificar rutas activas afectadas (en background, no bloquea la respuesta)
    notificarRutasAfectadas({
      categoria,
      latitud,
      longitud,
    });

  } catch (error) {
    console.error('Error en crearReporte:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// GET /reportes — Listar reportes con paginación
const getReportes = async (req, res) => {
  const { categoria, latitud, longitud, radio } = req.query;
  const limite = Math.min(parseInt(req.query.limite) || 20, 100);
  const pagina = Math.max(parseInt(req.query.pagina) || 1, 1);
  const offset = (pagina - 1) * limite;

  try {
    let query = `SELECT id, usuario_id, categoria, descripcion, evidencia_url,
                 ST_X(geom) as longitud, ST_Y(geom) as latitud,
                 trust_score, estado, created_at FROM reportes WHERE 1=1`;
    const params = [];

    if (categoria) {
      params.push(categoria);
      query += ` AND categoria = $${params.length}`;
    }

    if (latitud && longitud && radio) {
      params.push(longitud, latitud, radio);
      query += ` AND ST_DWithin(
        geom::geography,
        ST_SetSRID(ST_MakePoint($${params.length - 2}, $${params.length - 1}), 4326)::geography,
        $${params.length}
      )`;
    }

    query += ` ORDER BY created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limite, offset);

    const resultado = await pool.query(query, params);

    res.json({
      pagina,
      limite,
      total: resultado.rows.length,
      reportes: resultado.rows,
    });
  } catch (error) {
    console.error('Error en getReportes:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// GET /reportes/:id — Ver reporte específico
const getReporte = async (req, res) => {
  const { id } = req.params;

  try {
    const resultado = await pool.query(
      `SELECT id, usuario_id, categoria, descripcion, evidencia_url,
       ST_X(geom) as longitud, ST_Y(geom) as latitud,
       trust_score, estado, created_at FROM reportes WHERE id = $1`,
      [id]
    );

    if (resultado.rows.length === 0) {
      return res.status(404).json({ error: 'Reporte no encontrado' });
    }

    res.json(resultado.rows[0]);
  } catch (error) {
    console.error('Error en getReporte:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// PUT /reportes/:id — Actualizar estado
const actualizarEstado = async (req, res) => {
  const { id } = req.params;
  const { estado } = req.body;

  const estadosValidos = ['pendiente', 'verificado', 'rechazado', 'en_revision'];
  if (!estadosValidos.includes(estado)) {
    return res.status(400).json({ error: `Estado inválido. Opciones: ${estadosValidos.join(', ')}` });
  }

  try {
    const resultado = await pool.query(
      'UPDATE reportes SET estado = $1 WHERE id = $2 RETURNING *',
      [estado, id]
    );

    if (resultado.rows.length === 0) {
      return res.status(404).json({ error: 'Reporte no encontrado' });
    }

    res.json(resultado.rows[0]);
  } catch (error) {
    console.error('Error en actualizarEstado:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { crearReporte, getReportes, getReporte, actualizarEstado };