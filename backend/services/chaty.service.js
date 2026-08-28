const { GoogleGenerativeAI } = require('@google/generative-ai');
require('dotenv').config();

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-3.6-flash' });

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

    const result = await model.generateContent(prompt);
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
    return {
      success: false,
      accion: 'responder',
      destino: null,
      mensaje: 'Lo siento, no pude procesar tu mensaje. ¿Puedes repetirlo?',
      perfil_riesgo: 'normal',
      tipo_transporte: null,
      emergencia_inmediata: false,
    };
  }
};

module.exports = { procesarMensaje };