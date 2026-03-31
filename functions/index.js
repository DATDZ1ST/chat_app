const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

const MAX_TOKENS_PER_BATCH = 500;

function splitIntoChunks(items, size) {
  const chunks = [];

  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }

  return chunks;
}

exports.sendChatMessageNotification = onDocumentCreated(
  "chat/{messageId}",
  async (event) => {
    if (!event.data) {
      return;
    }

    const messageData = event.data.data();
    const senderId = messageData.userId;
    const senderName = messageData.username || "New message";
    const messageText =
      typeof messageData.text === "string" && messageData.text.trim().length > 0
        ? messageData.text.trim()
        : "Sent you a new message";

    const usersSnapshot = await getFirestore().collection("users").get();
    const recipientTokens = [];

    usersSnapshot.forEach((userDoc) => {
      if (userDoc.id === senderId) {
        return;
      }

      const tokens = userDoc.get("fcmTokens");
      if (!Array.isArray(tokens)) {
        return;
      }

      tokens.forEach((token) => {
        if (typeof token === "string" && token.trim().length > 0) {
          recipientTokens.push({
            userId: userDoc.id,
            token: token.trim(),
          });
        }
      });
    });

    if (recipientTokens.length === 0) {
      logger.info("No push recipients found for new chat message.", {
        messageId: event.params.messageId,
      });
      return;
    }

    const invalidTokens = [];
    const tokenChunks = splitIntoChunks(recipientTokens, MAX_TOKENS_PER_BATCH);

    for (const tokenChunk of tokenChunks) {
      const response = await getMessaging().sendEachForMulticast({
        tokens: tokenChunk.map((entry) => entry.token),
        notification: {
          title: senderName,
          body: messageText,
        },
        data: {
          screen: "chat",
          senderId: senderId || "",
          messageId: event.params.messageId,
        },
        android: {
          notification: {
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      });

      response.responses.forEach((sendResult, index) => {
        if (sendResult.success) {
          return;
        }

        const failedToken = tokenChunk[index];
        const errorCode = sendResult.error?.code;

        logger.error("Failed to send chat notification.", {
          errorCode,
          token: failedToken?.token,
          userId: failedToken?.userId,
        });

        if (
          errorCode === "messaging/invalid-registration-token" ||
          errorCode === "messaging/registration-token-not-registered"
        ) {
          invalidTokens.push(failedToken);
        }
      });
    }

    if (invalidTokens.length === 0) {
      return;
    }

    const cleanupBatch = getFirestore().batch();
    invalidTokens.forEach((entry) => {
      if (!entry) {
        return;
      }

      cleanupBatch.set(
        getFirestore().collection("users").doc(entry.userId),
        {
          fcmTokens: FieldValue.arrayRemove([entry.token]),
        },
        {merge: true},
      );
    });

    await cleanupBatch.commit();
  },
);
