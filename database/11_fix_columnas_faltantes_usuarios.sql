-- Fix: la base de datos real (Supabase) se quedó desincronizada de
-- 01_02_esquema_inicial.sql — le faltaban columnas que el código ya
-- esperaba (google_id para el login con Google, ubicacion_actual para el
-- tracking en tiempo real del SOS). Esto causaba
-- "column ... does not exist" en producción.
--
-- Seguro de re-correr: usa IF NOT EXISTS.

ALTER TABLE public.usuarios
  ADD COLUMN IF NOT EXISTS google_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS ubicacion_actual GEOMETRY(Point, 4326);
