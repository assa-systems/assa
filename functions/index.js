const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.sendNotification = onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  const { token, title, body, data } = req.body;

  if (!token || !title || !body) {
    res.status(400).json({ error: "token, title, and body are required" });
    return;
  }

  try {
    const message = {
      token: token,
      notification: { title, body },
      data: data || {},
      android: {
        priority: "high",
        notification: {
          channelId: "assa_main",
          priority: "high",
        },
      },
    };

    const result = await getMessaging().send(message);
    res.status(200).json({ success: true, messageId: result });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});