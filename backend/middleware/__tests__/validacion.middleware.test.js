const express = require('express');
const request = require('supertest');
const {
  validarRegistro,
  validarContacto,
  validarRuta,
  manejarErrores,
} = require('../validacion.middleware');

// App mínima de prueba: monta cada cadena de validación sobre una ruta
// dummy que solo responde 200 si pasó la validación. No toca la base de
// datos real — prueba exclusivamente las reglas de entrada.
const appDePrueba = express();
appDePrueba.use(express.json());
appDePrueba.post('/registro', validarRegistro, manejarErrores, (req, res) => res.status(200).json({ ok: true }));
appDePrueba.post('/contacto', validarContacto, manejarErrores, (req, res) => res.status(200).json({ ok: true }));
appDePrueba.post('/ruta', validarRuta, manejarErrores, (req, res) => res.status(200).json({ ok: true }));

describe('validarRegistro', () => {
  test('acepta un nombre y contraseña válidos', async () => {
    const res = await request(appDePrueba)
      .post('/registro')
      .send({ nombre: 'Dafne Cirne', password: 'Segura123' });
    expect(res.status).toBe(200);
  });

  test('rechaza un nombre con números', async () => {
    const res = await request(appDePrueba)
      .post('/registro')
      .send({ nombre: 'Dafne123', password: 'Segura123' });
    expect(res.status).toBe(400);
  });

  test('rechaza contraseña sin mayúscula ni número', async () => {
    const res = await request(appDePrueba)
      .post('/registro')
      .send({ nombre: 'Dafne', password: 'inseguro' });
    expect(res.status).toBe(400);
  });

  test('rechaza nombre vacío', async () => {
    const res = await request(appDePrueba)
      .post('/registro')
      .send({ nombre: '', password: 'Segura123' });
    expect(res.status).toBe(400);
  });

  test('acepta nombres con acentos y ñ (nombres reales mexicanos)', async () => {
    const res = await request(appDePrueba)
      .post('/registro')
      .send({ nombre: 'José Muñoz', password: 'Segura123' });
    expect(res.status).toBe(200);
  });
});

describe('validarContacto — limpieza y validación de teléfono', () => {
  test('acepta un teléfono de exactamente 10 dígitos', async () => {
    const res = await request(appDePrueba)
      .post('/contacto')
      .send({ nombre: 'Ana', telefono: '2221234567' });
    expect(res.status).toBe(200);
  });

  test('rechaza un teléfono con lada de país sin limpiar (+52...)', async () => {
    // La app limpia el teléfono en el cliente antes de mandarlo — este
    // test confirma que el servidor SÍ rechaza si por algún motivo llega
    // sin limpiar, en vez de aceptarlo silenciosamente.
    const res = await request(appDePrueba)
      .post('/contacto')
      .send({ nombre: 'Ana', telefono: '+522221234567' });
    expect(res.status).toBe(400);
  });

  test('rechaza un teléfono con menos de 10 dígitos', async () => {
    const res = await request(appDePrueba)
      .post('/contacto')
      .send({ nombre: 'Ana', telefono: '12345' });
    expect(res.status).toBe(400);
  });
});

describe('validarRuta — coordenadas dentro de México', () => {
  test('acepta coordenadas reales de Puebla', async () => {
    const res = await request(appDePrueba)
      .post('/ruta')
      .send({ origen_lat: 19.0414, origen_lon: -98.2063, destino_lat: 19.05, destino_lon: -98.21 });
    expect(res.status).toBe(200);
  });

  test('rechaza coordenadas fuera del rango de México (ej. Nueva York)', async () => {
    const res = await request(appDePrueba)
      .post('/ruta')
      .send({ origen_lat: 40.7128, origen_lon: -74.006, destino_lat: 19.05, destino_lon: -98.21 });
    expect(res.status).toBe(400);
  });

  test('rechaza si falta una coordenada', async () => {
    const res = await request(appDePrueba)
      .post('/ruta')
      .send({ origen_lat: 19.0414, destino_lat: 19.05, destino_lon: -98.21 });
    expect(res.status).toBe(400);
  });
});
