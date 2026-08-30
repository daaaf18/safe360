-- SEMANA 1-2: Esquema inicial de base de datos Safe360
-- Ejecutar en orden después de crear la base de datos: CREATE DATABASE safe360;

--CREATE EXTENSION IF NOT EXISTS postgis;

-- Tabla de cámaras de vigilancia
--CREATE TABLE IF NOT EXISTS camaras (
  --  id SERIAL PRIMARY KEY,
    --estado VARCHAR(20) NOT NULL,
    --geom GEOMETRY(Point, 4326) NOT NULL,
    --ultima_actualizacion TIMESTAMP DEFAULT NOW()
--);


-- Extensión PostGIS (ya viene habilitada en Supabase)
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;

-- ============================================================
-- TABLA: usuarios
-- ============================================================
CREATE TABLE IF NOT EXISTS public.usuarios (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    historial_confianza DOUBLE PRECISION DEFAULT 1.0,
    google_id VARCHAR(100),
    ubicacion_actual GEOMETRY(Point, 4326),
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLA: contactos_confianza
-- ============================================================
CREATE TABLE IF NOT EXISTS public.contactos_confianza (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    email VARCHAR(150),
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLA: luminarias
-- ============================================================
CREATE TABLE IF NOT EXISTS public.luminarias (
    id SERIAL PRIMARY KEY,
    calle VARCHAR(100),
    colonia VARCHAR(100),
    estado VARCHAR(20) DEFAULT 'operativa',
    geom GEOMETRY(Point, 4326) NOT NULL,
    ultima_actualizacion TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLA: reportes
-- ============================================================
CREATE TABLE IF NOT EXISTS public.reportes (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
    categoria VARCHAR(50) NOT NULL,
    descripcion TEXT,
    evidencia_url VARCHAR(255),
    geom GEOMETRY(Point, 4326) NOT NULL,
    trust_score DOUBLE PRECISION DEFAULT 0.0,
    estado VARCHAR(20) DEFAULT 'pendiente',
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLA: rutas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rutas (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER REFERENCES public.usuarios(id),
    origen GEOMETRY(Point, 4326),
    destino GEOMETRY(Point, 4326),
    trust_score_promedio DOUBLE PRECISION DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLA: rutas_activas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rutas_activas (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
    origen GEOMETRY(Point, 4326),
    destino GEOMETRY(Point, 4326),
    activa BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLA: zonas_riesgo
-- ============================================================
CREATE TABLE IF NOT EXISTS public.zonas_riesgo (
    id SERIAL PRIMARY KEY,
    geom GEOMETRY(Polygon, 4326),
    nivel VARCHAR(10) DEFAULT 'bajo',
    trust_score_promedio DOUBLE PRECISION DEFAULT 0.0,
    ultima_actualizacion TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- TABLA: historial_incidentes (Score Temporal)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.historial_incidentes (
    id SERIAL PRIMARY KEY,
    zona_id INTEGER REFERENCES public.zonas_riesgo(id),
    reporte_id INTEGER REFERENCES public.reportes(id),
    hora_incidente INTEGER CHECK (hora_incidente >= 0 AND hora_incidente <= 23),
    dia_semana INTEGER CHECK (dia_semana >= 0 AND dia_semana <= 6),
    nivel_riesgo VARCHAR(10) DEFAULT 'bajo',
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- ÍNDICES GEOESPACIALES (GIST)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_luminarias_geom ON public.luminarias USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_reportes_geom ON public.reportes USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_zonas_riesgo_geom ON public.zonas_riesgo USING GIST (geom);

-- ============================================================
-- FUNCIÓN: calcular_trust_score
-- Actualiza el trust_score de un reporte basándose en votos,
-- luminarias cercanas e historial del usuario
-- ============================================================
CREATE OR REPLACE FUNCTION public.calcular_trust_score(reporte_id_param INTEGER)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    v_geom GEOMETRY;
    v_usuario_id INTEGER;
    v_historial DOUBLE PRECISION;
    v_luminarias_cercanas INTEGER;
    v_reportes_similares INTEGER;
    v_score DOUBLE PRECISION;
BEGIN
    SELECT geom, usuario_id INTO v_geom, v_usuario_id
    FROM public.reportes WHERE id = reporte_id_param;

    SELECT historial_confianza INTO v_historial
    FROM public.usuarios WHERE id = v_usuario_id;

    SELECT COUNT(*) INTO v_luminarias_cercanas
    FROM public.luminarias
    WHERE estado = 'operativa'
    AND ST_DWithin(geom::geography, v_geom::geography, 100);

    SELECT COUNT(*) INTO v_reportes_similares
    FROM public.reportes
    WHERE id != reporte_id_param
    AND estado != 'rechazado'
    AND ST_DWithin(geom::geography, v_geom::geography, 200)
    AND created_at > NOW() - INTERVAL '24 hours';

    v_score := (v_historial * 0.4)
             + (LEAST(v_reportes_similares, 5) / 5.0 * 0.4)
             + (CASE WHEN v_luminarias_cercanas = 0 THEN 0.2 ELSE 0.0 END);

    v_score := GREATEST(0.0, LEAST(1.0, v_score));

    UPDATE public.reportes SET trust_score = v_score WHERE id = reporte_id_param;

    RETURN v_score;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCIÓN: score_temporal_zona
-- Devuelve el nivel de riesgo proyectado de una zona
-- para una hora específica del día
-- ============================================================
CREATE OR REPLACE FUNCTION public.score_temporal_zona(
    zona_id_param INTEGER,
    hora_param INTEGER
)
RETURNS VARCHAR AS $$
DECLARE
    v_nivel VARCHAR;
    v_conteo INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_conteo
    FROM public.historial_incidentes
    WHERE zona_id = zona_id_param
    AND hora_incidente = hora_param;

    IF v_conteo >= 5 THEN
        v_nivel := 'alto';
    ELSIF v_conteo >= 2 THEN
        v_nivel := 'medio';
    ELSE
        v_nivel := 'bajo';
    END IF;

    RETURN v_nivel;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCIÓN: recalcular_heatmap
-- Actualiza zonas_riesgo cuando se confirma un reporte
-- ============================================================
CREATE OR REPLACE FUNCTION public.recalcular_heatmap()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado = 'verificado' AND OLD.estado != 'verificado' THEN
        UPDATE public.zonas_riesgo
        SET trust_score_promedio = (
            SELECT AVG(r.trust_score)
            FROM public.reportes r
            WHERE r.estado = 'verificado'
            AND ST_Within(r.geom, public.zonas_riesgo.geom)
        ),
        nivel = CASE
            WHEN (SELECT AVG(r.trust_score) FROM public.reportes r
                  WHERE r.estado = 'verificado'
                  AND ST_Within(r.geom, public.zonas_riesgo.geom)) >= 0.7 THEN 'alto'
            WHEN (SELECT AVG(r.trust_score) FROM public.reportes r
                  WHERE r.estado = 'verificado'
                  AND ST_Within(r.geom, public.zonas_riesgo.geom)) >= 0.4 THEN 'medio'
            ELSE 'bajo'
        END,
        ultima_actualizacion = NOW()
        WHERE ST_Within(NEW.geom, geom);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- TRIGGER: recalcular heatmap al verificar reporte
-- ============================================================
DROP TRIGGER IF EXISTS trigger_recalcular_heatmap ON public.reportes;
CREATE TRIGGER trigger_recalcular_heatmap
    AFTER UPDATE OF estado ON public.reportes
    FOR EACH ROW
    EXECUTE FUNCTION public.recalcular_heatmap();