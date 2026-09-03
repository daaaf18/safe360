-- Alertas en-app de "reporte cerca de tu ruta activa": hasta ahora
-- notificarRutasAfectadas() solo mandaba WhatsApp — el usuario tiene que
-- verlo también dentro de Chaty cuando abre la app. Esta tabla guarda las
-- alertas pendientes por usuario; GET /rutas/alertas las regresa y las
-- marca como leídas.
CREATE TABLE IF NOT EXISTS public.alertas_ruta (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
    mensaje TEXT NOT NULL,
    categoria VARCHAR(50),
    leida BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alertas_ruta_usuario_pendientes
    ON public.alertas_ruta (usuario_id) WHERE leida = FALSE;
