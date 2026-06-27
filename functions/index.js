const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.notificarSismo = functions.database
  .ref("/sismos/ultimo")
  .onWrite(async (change) => {
    const datos = change.after.val();
    if (!datos) return null;

    const nivel     = datos.nivel     || "DESCONOCIDO";
    const vibracion = datos.vibracion || 0;

    // Obtener token FCM guardado por la app
    const tokenSnap = await admin.database()
      .ref("/dispositivo/fcmToken").get();
    const token = tokenSnap.val();
    if (!token) return null;

    // Título e ícono según nivel
    const titulos = {
      LIGERO:   "⚠️ Sismo Ligero",
      MODERADO: "🟠 Sismo Moderado",
      FUERTE:   "🔴 SISMO FUERTE",
    };

    const mensaje = {
      token: token,
      notification: {
        title: titulos[nivel] || "Sismo detectado",
        body:  `Vibración: ${vibracion.toFixed(4)} m/s²`,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "sismoapp_alertas",
          sound: "default",
        },
      },
    };

    return admin.messaging().send(mensaje);
  });