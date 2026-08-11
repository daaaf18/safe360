-- SEMANA 1-2: Esquema inicial de base de datos Safe360
-- Ejecutar en orden después de crear la base de datos: CREATE DATABASE safe360;

CREATE EXTENSION IF NOT EXISTS postgis;

-- Tabla de usuarios
CREATE TABLE IF NOT EXISTS usuarios (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    historial_confianza FLOAT DEFAULT 1.0,
    google_id VARCHAR(100),
    ubicacion_actual GEOMETRY(Point, 4326),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Tabla de reportes ciudadanos
CREATE TABLE IF NOT EXISTS reportes (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    categoria VARCHAR(50) NOT NULL,
    descripcion TEXT,
    evidencia_url VARCHAR(255),
    geom GEOMETRY(Point, 4326) NOT NULL,
    trust_score FLOAT DEFAULT 0.0,
    estado VARCHAR(20) DEFAULT 'pendiente',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Tabla de zonas de riesgo (heatmap)
CREATE TABLE IF NOT EXISTS zonas_riesgo (
    id SERIAL PRIMARY KEY,
    nivel VARCHAR(50) NOT NULL,
    geom GEOMETRY(Polygon, 4326) NOT NULL,
    ultima_actualizacion TIMESTAMP DEFAULT NOW()
);

-- Tabla de contactos de confianza
CREATE TABLE IF NOT EXISTS contactos_confianza (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    email VARCHAR(150),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Tabla de luminarias (datos reales importados desde CSV del municipio de Puebla)
CREATE TABLE IF NOT EXISTS luminarias (
    id SERIAL PRIMARY KEY,
    calle VARCHAR(100),
    colonia VARCHAR(100),
    estado VARCHAR(20) DEFAULT 'operativa',
    geom GEOMETRY(Point, 4326) NOT NULL,
    ultima_actualizacion TIMESTAMP DEFAULT NOW()
);

-- Tabla de cámaras de vigilancia
CREATE TABLE IF NOT EXISTS camaras (
    id SERIAL PRIMARY KEY,
    estado VARCHAR(20) NOT NULL,
    geom GEOMETRY(Point, 4326) NOT NULL,
    ultima_actualizacion TIMESTAMP DEFAULT NOW()
);

-- Tabla de historial de incidentes (para Score Temporal)
CREATE TABLE IF NOT EXISTS historial_incidentes (
    id SERIAL PRIMARY KEY,
    reporte_id INTEGER REFERENCES reportes(id),
    franja_horaria INTEGER, -- hora del día (0-23)
    dia_semana INTEGER,     -- día de la semana (0=lunes, 6=domingo)
    zona_id INTEGER REFERENCES zonas_riesgo(id),
    created_at TIMESTAMP DEFAULT NOW()
);
