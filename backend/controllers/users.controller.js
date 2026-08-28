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
  const { nombre, telefono } = req.body;

  try {
    const resultado = await pool.query(
      'INSERT INTO contactos_confianza (usuario_id, nombre, telefono) VALUES ($1, $2, $3) RETURNING *',
      [id, nombre, telefono]
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
  const { nombre, telefono } = req.body;

  try {
    const resultado = await pool.query(
      'UPDATE contactos_confianza SET nombre = $1, telefono = $2 WHERE id = $3 AND usuario_id = $4 RETURNING *',
      [nombre, telefono, contactoId, id]
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

module.exports = {
  getPerfil,
  editarPerfil,
  actualizarUbicacion,
  getContactos,
  agregarContacto,
  editarContacto,
  eliminarContacto
};