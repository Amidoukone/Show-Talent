/* eslint-disable linebreak-style */
/* eslint-disable max-len */
import * as admin from "firebase-admin";

// Empêche les appels multiples à initializeApp()
if (!admin.apps.length) {
  admin.initializeApp();
}

// Export standardisé
const db = admin.firestore();
const auth = admin.auth();
const fieldValue = admin.firestore.FieldValue;
const storage = admin.storage();

export {admin, db, auth, fieldValue, storage};
