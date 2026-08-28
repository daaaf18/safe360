const { body, validationResult } = require('express-validator');

// ── AUTH ──────────────────────────────────────────────────

const validarRegistro = [
  body('nombre')
    .notEmpty().withMessage('El nombre es obligatorio')
    .isLength({ min: 2, max: 50 }).withMessage('El nombre debe tener entre 2 y 50 caracteres')
    .matches(/^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$/).withMessage('El nombre solo puede contener letras y espacios')
    .trim(),
  body('password')
    .notEmpty().withMessage('La contraseña es obligatoria')
    .isLength({ min: 8 }).withMessage('La contraseña debe tener al menos 8 caracteres')
    .matches(/[A-Z]/).withMessage('La contraseña debe tener al menos una mayúscula')
    .matches(/[0-9]/).withMessage('La contraseña debe tener al menos un número'),
];

const validarLogin = [
  body('email')
    .notEmpty().withMessage('El email es obligatorio')
    .isEmail().withMessage('El email no tiene un formato válido')
    .normalizeEmail(),
  body('password')
    .notEmpty().withMessage('La contraseña es obligatoria'),
];

// ── REPORTES ──────────────────────────────────────────────

const CATEGORIAS_VALIDAS = [
  'Robo', 'Acoso', 'Poca iluminación',
  'Accidente vial', 'Presencia sospechosa',
  'Cámara vandalizada', 'Otro'
];

const validarReporte = [
  body('categoria')
    .notEmpty().withMessage('La categoría es obligatoria')
    .isIn(CATEGORIAS_VALIDAS).withMessage(`Categoría inválida. Opciones: ${CATEGORIAS_VALIDAS.join(', ')}`),
  body('descripcion')
    .optional()
    .isLength({ min: 10, max: 500 }).withMessage('La descripción debe tener entre 10 y 500 caracteres')
    .trim(),
  body('latitud')
    .notEmpty().withMessage('La latitud es obligatoria')
    .isFloat({ min: 14.0, max: 33.0 }).withMessage('Latitud fuera del rango de México'),
  body('longitud')
    .notEmpty().withMessage('La longitud es obligatoria')
    .isFloat({ min: -118.0, max: -86.0 }).withMessage('Longitud fuera del rango de México'),
];

// ── CONTACTOS DE CONFIANZA ────────────────────────────────

const validarContacto = [
  body('nombre')
    .notEmpty().withMessage('El nombre es obligatorio')
    .isLength({ min: 2, max: 100 }).withMessage('El nombre debe tener entre 2 y 100 caracteres')
    .matches(/^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$/).withMessage('El nombre solo puede contener letras y espacios')
    .trim(),
  body('telefono')
    .notEmpty().withMessage('El teléfono es obligatorio')
    .matches(/^\d{10}$/).withMessage('El teléfono debe tener exactamente 10 dígitos'),
  body('email')
    .optional()
    .isEmail().withMessage('El email del contacto no tiene un formato válido')
    .normalizeEmail(),
];

// ── RUTAS ────────────────────────────────────────────────

const validarRuta = [
  body('origen_lat')
    .notEmpty().withMessage('La latitud de origen es obligatoria')
    .isFloat({ min: 14.0, max: 33.0 }).withMessage('Latitud de origen fuera del rango de México'),
  body('origen_lon')
    .notEmpty().withMessage('La longitud de origen es obligatoria')
    .isFloat({ min: -118.0, max: -86.0 }).withMessage('Longitud de origen fuera del rango de México'),
  body('destino_lat')
    .notEmpty().withMessage('La latitud de destino es obligatoria')
    .isFloat({ min: 14.0, max: 33.0 }).withMessage('Latitud de destino fuera del rango de México'),
  body('destino_lon')
    .notEmpty().withMessage('La longitud de destino es obligatoria')
    .isFloat({ min: -118.0, max: -86.0 }).withMessage('Longitud de destino fuera del rango de México'),
];

// ── SOS ──────────────────────────────────────────────────

const validarSOS = [
  body('latitud')
    .notEmpty().withMessage('La latitud es obligatoria')
    .isFloat({ min: 14.0, max: 33.0 }).withMessage('Latitud fuera del rango de México'),
  body('longitud')
    .notEmpty().withMessage('La longitud es obligatoria')
    .isFloat({ min: -118.0, max: -86.0 }).withMessage('Longitud fuera del rango de México'),
];

// ── MANEJADOR DE ERRORES ──────────────────────────────────

const manejarErrores = (req, res, next) => {
  const errores = validationResult(req);
  if (!errores.isEmpty()) {
    return res.status(400).json({ errores: errores.array() });
  }
  next();
};

module.exports = {
  validarRegistro,
  validarLogin,
  validarReporte,
  validarContacto,
  validarRuta,
  validarSOS,
  manejarErrores,
};