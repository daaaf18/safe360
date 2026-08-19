const pool = require('../models/db');

// GET /users/:id — Ver perfil
const getPerfil = async (req, res) => {
  const { id } = req.params;

  try {
    const resultado = await pool.query(
      'SELECT id, nombre, email, historial_confianza, created_at FROM usuarios WHERE id = $1',
      [id]
    );

    if (resultado.rows.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    res.json(resultado.rows[0]);
  } catch (error) {
    console.error('Error en getPerfil:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// PUT /users/:id — Editar perfil
const editarPerfil = async (req, res) => {
  const { id } = req.params;
  const { nombre, email } = req.body;

  try {
    const resultado = await pool.query(
      'UPDATE usuarios SET nombre = $1, email = $2 WHERE id = $3 RETURNING id, nombre, email',
      [nombre, email, id]
    );

    if (resultado.rows.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    res.json(resultado.rows[0]);
  } catch (error) {
    console.error('Error en editarPerfil:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// PUT /users/:id/ubicacion — Actualizar ubicación en tiempo real
const actualizarUbicacion = async (req, res) => {
  const { id } = req.params;
  const { latitud, longitud } = req.body;

  try {
    await pool.query(
      'UPDATE usuarios SET ubicacion_actual = ST_SetSRID(ST_MakePoint($1, $2), 4326) WHERE id = $3',
      [longitud, latitud, id]
    );

    res.json({ message: 'Ubicación actualizada correctamente' });
  } catch (error) {
    console.error('Error en actualizarUbicacion:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// GET /users/:id/contactos — Ver contactos de confianza
const getContactos = async (req, res) => {
  const { id } = req.params;

  try {
    const resultado = await pool.query(
      'SELECT * FROM contactos_confianza WHERE usuario_id = $1 ORDER BY created_at ASC',
      [id]
    );

    res.json(resultado.rows);
  } catch (error) {
    console.error('Error en getContactos:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// POST /users/:id/contactos — Agregar contacto
const agregarContacto = async (req, res) => {
  const { id } = req.params;
  const { nombre, telefono, email } = req.body;

  try {
    const resultado = await pool.query(
      'INSERT INTO contactos_confianza (usuario_id, nombre, telefono, email) VALUES ($1, $2, $3, $4) RETURNING *',
      [id, nombre, telefono, email]
    );

    res.status(201).json(resultado.rows[0]);
  } catch (error) {
    console.error('Error en agregarContacto:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// PUT /users/:id/contactos/:contactoId — Editar contacto
const editarContacto = async (req, res) => {
  const { id, contactoId } = req.params;
  const { nombre, telefono, email } = req.body;

  try {
    const resultado = await pool.query(
      'UPDATE contactos_confianza SET nombre = $1, telefono = $2, email = $3 WHERE id = $4 AND usuario_id = $5 RETURNING *',
      [nombre, telefono, email, contactoId, id]
    );

    if (resultado.rows.length === 0) {
      return res.status(404).json({ error: 'Contacto no encontrado' });
    }

    res.json(resultado.rows[0]);
  } catch (error) {
    console.error('Error en editarContacto:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// DELETE /users/:id/contactos/:contactoId — Eliminar contacto
const eliminarContacto = async (req, res) => {
  const { id, contactoId } = req.params;

  try {
    const resultado = await pool.query(
      'DELETE FROM contactos_confianza WHERE id = $1 AND usuario_id = $2 RETURNING *',
      [contactoId, id]
    );

    if (resultado.rows.length === 0) {
      return res.status(404).json({ error: 'Contacto no encontrado' });
    }

    res.json({ message: 'Contacto eliminado correctamente' });
  } catch (error) {
    console.error('Error en eliminarContacto:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// GET /usuarios/cercanos?lat=&lon=&radio=
const getCercanos = async (req, res) => {
  const { lat, lon, radio = 300 } = req.query;
  const usuario_id = req.usuario.id;

  if (!lat || !lon) {
    return res.status(400).json({ error: 'Se requieren lat y lon' });
  }

  try {
    // Usuarios activos en los últimos 5 minutos, excluyendo al solicitante
    // Posición aproximada — redondeada a ~100m para privacidad
    const resultado = await pool.query(
      `SELECT 
        COUNT(*) as total,
        ST_X(ST_SnapToGrid(ubicacion_publica, 0.001)) as lon_aprox,
        ST_Y(ST_SnapToGrid(ubicacion_publica, 0.001)) as lat_aprox
       FROM usuarios
       WHERE id != $1
       AND ubicacion_publica IS NOT NULL
       AND ultimo_ping > NOW() - INTERVAL '5 minutes'
       AND ST_DWithin(
         ubicacion_publica::geography,
         ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography,
         $4
       )
       GROUP BY ST_SnapToGrid(ubicacion_publica, 0.001)`,
      [usuario_id, lon, lat, radio]
    );

    res.json({
      total: resultado.rows.reduce((acc, r) => acc + parseInt(r.total), 0),
      zonas: resultado.rows.map(r => ({
        lat: r.lat_aprox,
        lon: r.lon_aprox,
        cantidad: parseInt(r.total)
      }))
    });

  } catch (error) {
    console.error('Error en getCercanos:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// PUT /users/:id/ping — Actualizar ping y ubicación pública aproximada
const actualizarPing = async (req, res) => {
  const { id } = req.params;
  const { latitud, longitud } = req.body;

  try {
    await pool.query(
      `UPDATE usuarios SET 
        ultimo_ping = NOW(),
        ubicacion_publica = ST_SnapToGrid(
          ST_SetSRID(ST_MakePoint($1, $2), 4326), 0.001
        )
       WHERE id = $3`,
      [longitud, latitud, id]
    );

    res.json({ message: 'Ping actualizado' });
  } catch (error) {
    console.error('Error en actualizarPing:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = {
  getPerfil,
  editarPerfil,
  actualizarUbicacion,
  getContactos,
  agregarContacto,
  editarContacto,
  eliminarContacto,
  getCercanos,
  actualizarPing
};