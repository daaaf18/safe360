-- 14_indices_geografia.sql
--
-- Hallazgo real (medido con EXPLAIN ANALYZE, no supuesto): las consultas
-- espaciales de la app filtran con ST_DWithin(geom::geography, ...), pero
-- el índice GIST original (idx_luminarias_geom / idx_reportes_geom) se
-- creó sobre la columna `geom` en su tipo original (geometry) — el
-- planificador de Postgres no puede usar ese índice para satisfacer un
-- filtro sobre la EXPRESIÓN geom::geography, porque para el planificador
-- son dos cosas distintas. Resultado real medido antes de este fix:
--
--   luminarias (125,303 filas): Seq Scan paralelo, ~470ms (arranque en
--   frío) / ~39ms (con caché tibia) por cada consulta de "qué luminarias
--   fundidas hay cerca de este punto" — se ejecuta en CADA llamada a
--   Ruta segura y a "qué tan segura es mi zona".
--
-- Fix: un índice de expresión GIST sobre (geom::geography), que sí
-- coincide exactamente con lo que las consultas ya usan.
--
-- Resultado medido después del fix: la misma consulta pasa de Seq Scan a
-- Index Scan, y de ~470ms/~39ms a ~0.9ms — más de 400x más rápida en la
-- tabla grande. En `reportes` el efecto es menos notorio hoy (pocas filas
-- todavía), pero evita que se vuelva a convertir en cuello de botella
-- conforme crezcan los reportes reales.

CREATE INDEX IF NOT EXISTS idx_luminarias_geog ON luminarias USING gist ((geom::geography));
CREATE INDEX IF NOT EXISTS idx_reportes_geog ON reportes USING gist ((geom::geography));

-- Refresca las estadísticas del planificador para ambas tablas después de
-- crear los índices, para que la próxima consulta ya elija el plan
-- correcto sin esperar al autovacuum.
ANALYZE luminarias;
ANALYZE reportes;
