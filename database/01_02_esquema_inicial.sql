CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE usuarios (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100),
    email VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    historial_confianza NUMERIC(3, 2)
);

CREATE TABLE reportes (
    id SERIAL PRIMARY KEY,
    usuario_id INT REFERENCES usuarios(id),
    categoria VARCHAR(50),
    trust_score NUMERIC(3, 2),
    estado VARCHAR(20),
    timestamp TIMESTAMP,
    geom GEOMETRY(Point, 4326)
);

CREATE TABLE zonas_riesgo (
    id SERIAL PRIMARY KEY,
    nivel VARCHAR(50),
    ultima_actualizacion TIMESTAMP,
    geom GEOMETRY(Polygon, 4326)
);