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

exports.sendPrivateChatNotification = onDocumentCreated(
  "private_chats/{chatId}/messages/{messageId}",
  async (event) => {
    if (!event.data) {
      return;
    }

    const messageData = event.data.data();
    const senderId = messageData.userId;
    const recipientId = messageData.recipientId;
    const senderName = messageData.username || "New message";
    const messageText =
      typeof messageData.text === "string" && messageData.text.trim().length > 0
        ? messageData.text.trim()
        : "Sent you a new message";

    if (!recipientId || recipientId === senderId) {
      logger.info("Skipping push because recipient is missing or invalid.", {
        chatId: event.params.chatId,
        messageId: event.params.messageId,
      });
      return;
    }

    const recipientDoc = await getFirestore().collection("users").doc(recipientId).get();
    if (!recipientDoc.exists) {
      logger.info("Recipient profile not found.", {
        recipientId,
        chatId: event.params.chatId,
      });
      return;
    }

    const recipientTokens = [];
    const tokens = recipientDoc.get("fcmTokens");

    if (Array.isArray(tokens)) {
      tokens.forEach((token) => {
        if (typeof token === "string" && token.trim().length > 0) {
          recipientTokens.push({
            userId: recipientId,
            token: token.trim(),
          });
        }
      });
    }

    if (recipientTokens.length === 0) {
      logger.info("No push recipients found for private chat message.", {
        chatId: event.params.chatId,
        recipientId,
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
          screen: "conversation",
          chatId: event.params.chatId,
          otherUserId: senderId || "",
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

        logger.error("Failed to send private chat notification.", {
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

exports.sendIncomingCallNotification = onDocumentCreated(
  "calls/{callId}",
  async (event) => {
    if (!event.data) {
      return;
    }

    const callData = event.data.data();
    const callerId = callData.callerId;
    const calleeId = callData.calleeId;
    const callerName = callData.callerName || "Incoming call";
    const chatId = callData.chatId;
    const isVideo = callData.isVideo === true;
    const status = callData.status;

    if (!calleeId || !callerId || !chatId || status !== "ringing") {
      logger.info("Skipping incoming call push because required data is missing.", {
        callId: event.params.callId,
      });
      return;
    }

    const recipientDoc = await getFirestore().collection("users").doc(calleeId).get();
    if (!recipientDoc.exists) {
      logger.info("Incoming call recipient profile not found.", {
        calleeId,
        callId: event.params.callId,
      });
      return;
    }

    const recipientTokens = [];
    const tokens = recipientDoc.get("fcmTokens");

    if (Array.isArray(tokens)) {
      tokens.forEach((token) => {
        if (typeof token === "string" && token.trim().length > 0) {
          recipientTokens.push({
            userId: calleeId,
            token: token.trim(),
          });
        }
      });
    }

    if (recipientTokens.length === 0) {
      logger.info("No push recipients found for incoming call.", {
        callId: event.params.callId,
        calleeId,
      });
      return;
    }

    const invalidTokens = [];
    const tokenChunks = splitIntoChunks(recipientTokens, MAX_TOKENS_PER_BATCH);

    for (const tokenChunk of tokenChunks) {
      const response = await getMessaging().sendEachForMulticast({
        tokens: tokenChunk.map((entry) => entry.token),
        notification: {
          title: callerName,
          body: isVideo ? "Incoming video call" : "Incoming voice call",
        },
        data: {
          screen: "call",
          callId: event.params.callId,
          chatId,
          otherUserId: callerId,
          isVideo: isVideo ? "true" : "false",
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

        logger.error("Failed to send incoming call notification.", {
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
