-- Rutas frecuentes en Perfil: antes `rutas` solo guardaba origen/destino/
-- trust_score, sin la geometría ni el nivel de riesgo — no alcanzaba para
-- reactivar una ruta guardada con un toque (habría que recalcularla toda
-- de nuevo). Esto le agrega el detalle que POST /rutas/segura ya calcula
-- de todos modos, para no tener que rehacer el trabajo al reactivarla.
ALTER TABLE public.rutas
    ADD COLUMN IF NOT EXISTS distancia_metros INTEGER,
    ADD COLUMN IF NOT EXISTS nivel_riesgo VARCHAR(20),
    ADD COLUMN IF NOT EXISTS puntos JSONB,
    ADD COLUMN IF NOT EXISTS ruteo_real BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_rutas_usuario_creado
    ON public.rutas (usuario_id, created_at DESC);
