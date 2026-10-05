import process from 'node:process';

const environment = process.argv[2];
if (!['staging', 'production'].includes(environment)) throw new Error('Expected staging or production');
const expectedProject = `adfoot-${environment}`;
const expectedBundle = environment === 'staging' ? 'org.adfoot.app.staging' : 'org.adfoot.app';
const expectedShare = environment === 'staging' ? 'https://adfoot-staging.firebaseapp.com' : 'https://adfoot.org';
const expected = {APP_ENV: environment, FIREBASE_PROJECT_ID: expectedProject,
  FIREBASE_IOS_BUNDLE_ID: expectedBundle, VIDEO_SHARE_BASE_URL: expectedShare};
for (const [key, value] of Object.entries(expected)) {
  if (process.env[key] !== value) throw new Error(`${key} does not match ${environment}`);
}
const sender = process.env.FIREBASE_MESSAGING_SENDER_ID ?? '';
const appId = process.env.FIREBASE_IOS_APP_ID ?? '';
if (!/^\d+$/.test(sender) || !appId.startsWith(`1:${sender}:ios:`) ||
    !/^1:\d+:ios:[a-zA-Z0-9]+$/.test(appId)) {
  throw new Error('FIREBASE_IOS_APP_ID must identify the iOS app for this sender');
}
if (!process.env.FIREBASE_IOS_API_KEY || /replace|placeholder/i.test(process.env.FIREBASE_IOS_API_KEY)) {
  throw new Error('FIREBASE_IOS_API_KEY is missing or is a placeholder');
}
if (![`${expectedProject}.firebasestorage.app`, `${expectedProject}.appspot.com`]
  .includes(process.env.FIREBASE_STORAGE_BUCKET)) throw new Error('Storage bucket does not match the project');
console.log(`iOS build environment verified: ${environment}, ${expectedBundle}`);
