const { GoogleGenerativeAI } = require('@google/generative-ai');
require('dotenv').config();

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-3.6-flash' });

const SYSTEM_PROMPT = `Eres Chaty, el asistente de seguridad de Safe360, una app de navegación urbana segura.

Tu rol es ayudar a los usuarios a moverse con seguridad por la ciudad. Respondes en español, de forma breve, amigable y directa.

Puedes hacer estas acciones según lo que diga el usuario:
- Si dice que quiere ir a algún lugar: responde con accion: "calcular_ruta" y extrae el destino
- Si dice que está en peligro o necesita ayuda urgente: responde con accion: "activar_sos"  
- Si pregunta por la seguridad de una zona: responde con accion: "consultar_zona"
- Si quiere reportar algo: responde con accion: "abrir_reporte"
- Para cualquier otra cosa: responde con accion: "responder" y da una respuesta útil

IMPORTANTE: Siempre responde en este formato JSON exacto, sin texto adicional:
{
  "accion": "calcular_ruta" | "activar_sos" | "consultar_zona" | "abrir_reporte" | "responder",
  "destino": "nombre del lugar si aplica",
  "mensaje": "tu respuesta al usuario",
  "perfil_riesgo": "sola" | "acompañada" | "nocturno" | "normal"
}`;

const procesarMensaje = async (mensaje, contexto = {}) => {
  try {
    const prompt = `${SYSTEM_PROMPT}

Contexto del usuario:
- Hora actual: ${new Date().getHours()}:${String(new Date().getMinutes()).padStart(2, '0')}
- Es de noche: ${new Date().getHours() >= 20 || new Date().getHours() < 6}

Mensaje del usuario: "${mensaje}"

Responde SOLO con el JSON, sin markdown ni texto adicional.`;

    const result = await model.generateContent(prompt);
    const responseText = result.response.text().trim();

    // Limpiar respuesta por si Gemini añade markdown
    const clean = responseText.replace(/```json|```/g, '').trim();
    const parsed = JSON.parse(clean);

    return {
      success: true,
      accion: parsed.accion || 'responder',
      destino: parsed.destino || null,
      mensaje: parsed.mensaje || 'Entendido, ¿en qué más puedo ayudarte?',
      perfil_riesgo: parsed.perfil_riesgo || 'normal',
    };

  } catch (error) {
    console.error('Error en Chaty:', error.message);
    return {
      success: false,
      accion: 'responder',
      destino: null,
      mensaje: 'Lo siento, no pude procesar tu mensaje. ¿Puedes repetirlo?',
      perfil_riesgo: 'normal',
    };
  }
};

module.exports = { procesarMensaje };