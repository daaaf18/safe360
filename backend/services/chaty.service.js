const { GoogleGenerativeAI } = require('@google/generative-ai');
const pool = require('../models/db');
require('dotenv').config();

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-3.6-flash' });
// Respaldo cuando gemini-3.6-flash está saturado (confirmado con 503
// "high demand" repetidos) — un modelo más ligero, con menos demanda,
// para intentar una respuesta real de IA antes de caer al respaldo por
// palabras clave (que entiende mucho menos). Probado en vivo: mientras
// 3.6-flash fallaba seguido, este respondió bien 3/3 veces.
const modelRespaldo = genAI.getGenerativeModel({ model: 'gemini-3.1-flash-lite' });

// ── Palabras clave de emergencia — detección inmediata sin Gemini ──
const PALABRAS_EMERGENCIA = [
  'auxilio', 'ayuda', 'socorro', 'peligro', 'emergencia',
  'me están siguiendo', 'me atacaron', 'me robaron', 'help',
  'estoy en peligro', 'llamen a la policía', 'me lastimaron'
];

// ── Palabras clave de modo transporte ──
const PALABRAS_TRANSPORTE = [
  'uber', 'didi', 'taxi', 'camión', 'camion', 'metro',
  'microbús', 'microbus', 'transporte', 'combi', 'autobús', 'autobus'
];

const esEmergencia = (mensaje) => {
  const lower = mensaje.toLowerCase();
  return PALABRAS_EMERGENCIA.some(p => lower.includes(p));
};

const esModoTransporte = (mensaje) => {
  const lower = mensaje.toLowerCase();
  return PALABRAS_TRANSPORTE.some(p => lower.includes(p));
};

// ── Palabras clave de "llegué" — finaliza el viaje sin que el usuario
// tenga que tocar el botón "Finalizar viaje" ──
const PALABRAS_LLEGADA = [
  'ya llegué', 'ya llegue', 'llegué', 'llegue a mi destino', 'ya estoy aquí',
  'ya estoy aqui', 'finalizar viaje', 'terminar viaje', 'terminé el viaje',
  'termine el viaje', 'ya llegue bien', 'ya llegué bien',
];
const esLlegada = (mensaje) => {
  const lower = mensaje.toLowerCase();
  return PALABRAS_LLEGADA.some(p => lower.includes(p));
};

// ── Respaldo sin Gemini — por palabras clave ──────────────────────────
// Gemini (gemini-3.6-flash) confirmado con caídas intermitentes de "alta
// demanda" (503) que antes dejaban a Chaty mudo por completo ("no pude
// procesar tu mensaje" sin ninguna acción). Esto cubre las intenciones más
// comunes con reglas simples para que Chaty siga siendo útil mientras
// Gemini no responde — no entiende tan bien como el modelo, pero al menos
// reacciona a lo básico en vez de fallar siempre.
const PALABRAS_RUTA = ['ruta', 'ir a', 'cómo llego', 'como llego', 'llevame', 'llévame', 'quiero ir'];
const PALABRAS_REPORTE = ['reportar', 'reporte', 'vi algo', 'hay un'];
const PALABRAS_ZONA = ['zona', 'qué tan seguro', 'que tan seguro', 'es seguro aquí', 'es seguro aqui', 'riesgo de'];

const respuestaSinGemini = (mensaje) => {
  const lower = mensaje.toLowerCase();

  if (esModoTransporte(mensaje)) {
    return {
      accion: 'modo_transporte',
      mensaje: 'Va, ¿a dónde te llevan? Dime el destino para monitorear tu viaje.',
    };
  }
  if (PALABRAS_RUTA.some(p => lower.includes(p))) {
    return {
      accion: 'calcular_ruta',
      mensaje: '¿A dónde quieres ir? Dime el destino y te calculo la ruta más segura.',
    };
  }
  if (PALABRAS_REPORTE.some(p => lower.includes(p))) {
    return {
      accion: 'abrir_reporte',
      mensaje: 'Te abro el formulario de reporte para que cuentes lo que viste.',
    };
  }
  if (PALABRAS_ZONA.some(p => lower.includes(p))) {
    return {
      accion: 'consultar_zona',
      mensaje: 'Revisando el nivel de riesgo de tu zona actual.',
    };
  }
  return {
    accion: 'responder',
    mensaje: 'Ahorita estoy medio lenta (mucha demanda del lado de Google 😅), pero '
      + 'sigo aquí. Puedo calcular una ruta segura, activar el SOS, revisar el '
      + 'riesgo de tu zona o abrir un reporte — dime cuál.',
  };
};

const horaActual = () => new Date().getHours();
const esNocturno = () => horaActual() >= 20 || horaActual() < 6;
const esTardecita = () => horaActual() >= 18 && horaActual() < 20;

const SYSTEM_PROMPT = `Eres Chaty, el asistente de seguridad de Safe360, una app de navegación urbana segura para México.

Tu rol es ayudar a los usuarios a moverse con seguridad por la ciudad. Respondes en español mexicano, de forma breve, amigable y directa. Nunca uses lenguaje formal o robótico.

Puedes hacer estas acciones según lo que diga el usuario:
- Si dice que quiere ir a algún lugar: accion "calcular_ruta", extrae el destino
- Si dice que está en peligro o necesita ayuda urgente: accion "activar_sos"
- Si menciona que va en uber, didi, taxi o transporte público: accion "modo_transporte"
- Si pregunta por la seguridad de una zona: accion "consultar_zona"
- Si quiere reportar algo: accion "abrir_reporte"
- Para cualquier otra cosa: accion "responder"

IMPORTANTE: Siempre responde en este formato JSON exacto, sin texto adicional:
{
  "accion": "calcular_ruta" | "activar_sos" | "modo_transporte" | "consultar_zona" | "abrir_reporte" | "responder",
  "destino": "nombre del lugar si aplica, null si no",
  "mensaje": "tu respuesta al usuario, máximo 2 oraciones",
  "perfil_riesgo": "sola" | "acompañada" | "nocturno" | "normal",
  "tipo_transporte": "uber" | "didi" | "taxi" | "publico" | null
}`;

const procesarMensaje = async (mensaje, contexto = {}) => {
  try {
    // ── 1. Detección inmediata de emergencia — sin llamar a Gemini ──
    if (esEmergencia(mensaje)) {
      return {
        success: true,
        accion: 'activar_sos',
        destino: null,
        mensaje: '🚨 ¡Detecté una emergencia! Activando SOS ahora — tus contactos de confianza recibirán tu ubicación de inmediato.',
        perfil_riesgo: 'nocturno',
        tipo_transporte: null,
        emergencia_inmediata: true,
      };
    }

    // ── 1b. "Ya llegué" — finaliza el viaje/ruta activa sin que el
    // usuario tenga que tocar el botón. Solo dispara si de verdad hay
    // algo activo en rutas_activas (modo transporte o ruta segura) — si
    // no, "ya llegué a mi casa" en charla normal no debe hacer nada raro.
    if (esLlegada(mensaje) && contexto.usuario_id) {
      try {
        const activo = await pool.query(
          'SELECT 1 FROM rutas_activas WHERE usuario_id = $1 AND activa = TRUE',
          [contexto.usuario_id]
        );
        if (activo.rows.length > 0) {
          return {
            success: true,
            accion: 'finalizar_viaje',
            destino: null,
            mensaje: '✅ Qué bueno que llegaste bien. Dejo de monitorear tu viaje.',
            perfil_riesgo: 'normal',
            tipo_transporte: null,
            emergencia_inmediata: false,
          };
        }
      } catch (error) {
        console.error('Error revisando ruta activa para "llegué":', error.message);
        // Si falla la consulta, seguimos con el flujo normal (Gemini/
        // respaldo) en vez de tronar el mensaje completo.
      }
    }

    // ── 2. Construir contexto para Gemini ──
    const hora = horaActual();
    const contextoHorario = esNocturno()
      ? 'Es de noche (alto riesgo general en zonas poco iluminadas).'
      : esTardecita()
        ? 'Es tarde, anochece pronto. El riesgo puede aumentar en los próximos minutos.'
        : 'Es de día, riesgo general bajo.';

    const prompt = `${SYSTEM_PROMPT}

Contexto del usuario:
- Hora actual: ${hora}:${String(new Date().getMinutes()).padStart(2, '0')}
- Situación horaria: ${contextoHorario}
- Es de noche: ${esNocturno()}
- Modo transporte detectado: ${esModoTransporte(mensaje)}
${contexto.trust_score ? `- TrustScore de la zona actual: ${contexto.trust_score}/10` : ''}
${contexto.nivel_riesgo ? `- Nivel de riesgo de la zona: ${contexto.nivel_riesgo}` : ''}

Mensaje del usuario: "${mensaje}"

${esNocturno() ? 'NOTA: Es de noche, sé especialmente atenta a señales de riesgo y sugiere medidas de seguridad adicionales.' : ''}
${esModoTransporte(mensaje) ? 'NOTA: El usuario menciona transporte. Activa modo_transporte y pide detalles del viaje.' : ''}

Responde SOLO con el JSON, sin markdown ni texto adicional.`;

    // Sin timeout, si Gemini está lento o con alta demanda (pasa,
    // confirmado: el modelo llegó a tardar 30+ segundos y devolver 503),
    // el mensaje del usuario se queda esperando indefinidamente sin
    // ninguna respuesta ni error — cae al catch de abajo en vez de
    // colgar la conversación.
    const generarConTimeout = (modeloUsar, timeoutMs) => Promise.race([
      modeloUsar.generateContent(prompt),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Gemini tardó demasiado en responder')), timeoutMs)
      ),
    ]);

    let result;
    try {
      result = await generarConTimeout(model, 12_000);
    } catch (errorPrimario) {
      // gemini-3.6-flash saturado/lento — un intento con el modelo de
      // respaldo antes de rendirse al respaldo por palabras clave (que
      // entiende mucho menos que una respuesta real de IA).
      console.error('gemini-3.6-flash falló, reintentando con modelo de respaldo:', errorPrimario.message);
      result = await generarConTimeout(modelRespaldo, 10_000);
    }
    const responseText = result.response.text().trim();
    const clean = responseText.replace(/```json|```/g, '').trim();
    const parsed = JSON.parse(clean);

    // ── 3. Agregar alerta proactiva nocturna si calcula ruta ──
    let mensajeFinal = parsed.mensaje || 'Entendido, ¿en qué más puedo ayudarte?';
    if (parsed.accion === 'calcular_ruta' && esNocturno()) {
      mensajeFinal += ' ⚠️ Recuerda que es de noche — activa el modo escolta para que tus contactos sepan dónde estás.';
    }
    if (parsed.accion === 'calcular_ruta' && esTardecita()) {
      mensajeFinal += ' 🌆 Va a anochecer pronto, considera salir antes de que baje la visibilidad.';
    }

    return {
      success: true,
      accion: parsed.accion || 'responder',
      destino: parsed.destino || null,
      mensaje: mensajeFinal,
      perfil_riesgo: parsed.perfil_riesgo || 'normal',
      tipo_transporte: parsed.tipo_transporte || null,
      emergencia_inmediata: false,
    };

  } catch (error) {
    console.error('Error en Chaty:', error.message);
    // Antes esto siempre regresaba "no pude procesar tu mensaje" sin
    // ninguna acción — con Gemini cayéndose por alta demanda, Chaty se
    // quedaba mudo justo cuando más se necesitaba. respuestaSinGemini()
    // cubre las intenciones comunes por palabras clave para que la
    // conversación pueda seguir aunque Gemini no responda.
    const fallback = respuestaSinGemini(mensaje);
    return {
      success: true,
      accion: fallback.accion,
      destino: null,
      mensaje: fallback.mensaje,
      perfil_riesgo: 'normal',
      tipo_transporte: null,
      emergencia_inmediata: false,
    };
  }
};

module.exports = { procesarMensaje };