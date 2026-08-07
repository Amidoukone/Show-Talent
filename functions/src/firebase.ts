/* eslint-disable linebreak-style */

import {getApp, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {getStorage} from "firebase-admin/storage";

const app = getApps().length > 0 ? getApp() : initializeApp();
const auth = getAuth(app);
const db = getFirestore(app);
const storage = getStorage(app);
const messaging = getMessaging(app);
const fieldValue = FieldValue;

export {app, auth, db, fieldValue, messaging, storage};
