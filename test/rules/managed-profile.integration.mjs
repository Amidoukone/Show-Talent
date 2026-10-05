import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mock} from 'node:test';

const require = createRequire(import.meta.url);

export async function checkManagedProfiles(check) {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Emulator required');
  const {db, auth, storage} = require('../../functions/lib/firebase.js');
  const {updateManagedAccountProfile, withdrawManagedMinorConsent} =
    require('../../functions/lib/admin_account_actions.js');
  const {provisionManagedAccount} = require('../../functions/lib/managed_accounts.js');
  const email = require('../../functions/lib/email_delivery.js');
  const uid = 'audit_managed_player';
  const peer = 'audit_managed_peer';
  const user = db.collection('users').doc(uid);
  const privateContact = user.collection('private').doc('contact');
  const consentRef = user.collection('private').doc('guardianConsent');
  const conversation = db.collection('conversations').doc('audit_managed_conversation');
  const video = db.collection('videos').doc('audit_managed_video');
  const consent = {
    guardianName: 'Test Guardian', relationship: 'parent',
    method: 'oral_confirmation', confirmed: true, mediaAllowed: true,
  };
  const request = (patch) => ({
    auth: {uid: 'audit_admin', token: {admin: true}}, data: {uid, patch},
  });
  const record = {uid, email: 'audit@example.invalid', displayName: 'Audit', emailVerified: true, disabled: false};
  const stubs = [
    mock.method(auth, 'getUser', async () => record),
    mock.method(auth, 'getUserByEmail', async () => record),
    mock.method(auth, 'generatePasswordResetLink', async () => 'https://example.invalid/reset'),
    mock.method(email, 'sendAccountInviteEmail', async () => ({sent: false, reason: 'test'})),
  ];
  const remainingFiles = new Set([`cvs/${uid}/old.pdf`, `profilePhotos/${uid}`]);
  let failStorage = false;
  stubs.push(mock.method(storage, 'bucket', () => ({
    name: 'demo-adfoot.appspot.com',
    getFiles: async ({prefix}) => [[...remainingFiles].filter((name) => name.startsWith(prefix)).map((name) => ({name}))],
    file: (name) => ({delete: async () => {
      if (failStorage) throw new Error('Simulated Storage failure');
      remainingFiles.delete(name);
    }}),
  })));
  try {
    await user.set({nom: 'Audit', role: 'joueur', createdByAdmin: true, isMinorProfile: false,
      estActif: true, authDisabled: false, emailVerified: true, profilePublic: true,
      cvUrl: `gs://demo-adfoot.appspot.com/cvs/${uid}/old.pdf`});
    await privateContact.set({birthDate: new Date('1990-01-01')});
    await db.collection('users').doc(peer).set({isMinorProfile: false});
    await conversation.set({utilisateurIds: [uid, peer], readableBy: [uid, peer]});
    await video.set({uid, status: 'ready', publicFeedVisible: true});

    await check('correction adulte vers mineur ferme les listes dans le commit meme si Storage echoue', 'allow', async () => {
      failStorage = true;
      await assert.rejects(updateManagedAccountProfile.run(request({birthDate: '2010-01-01', guardianConsent: consent})), /Simulated Storage failure/);
      assert.equal((await user.get()).data().minorMediaPurgePending, true);
      assert.equal((await video.get()).data().publicFeedVisible, false);
      assert.deepEqual((await conversation.get()).data().readableBy, []);
      assert.equal((await consentRef.get()).data().status, 'admin_recorded');
    });
    await check('reprise de purge retrouve le CV apres effacement de sa reference', 'allow', async () => {
      failStorage = false;
      await updateManagedAccountProfile.run(request({guardianConsent: consent}));
      assert.equal((await user.get()).data().minorMediaPurgePending, false);
      assert.equal(remainingFiles.size, 0);
    });
    await check('reprovisionnement conserve les medias autorises et enregistre le consentement', 'allow', async () => {
      await user.update({photoProfil: 'allowed-photo'});
      const result = await provisionManagedAccount.run({
        auth: request({}).auth,
        data: {email: record.email, displayName: 'Audit', nom: 'Audit', role: 'joueur', birthDate: '2010-01-01', guardianConsent: consent},
      });
      assert.equal(result.success, true);
      assert.equal((await user.get()).data().photoProfil, 'allowed-photo');
    });
    await check('retrait parental revoque le consentement et masque la projection', 'allow', async () => {
      await withdrawManagedMinorConsent.run(request({}));
      assert.equal((await consentRef.get()).data().status, 'withdrawn');
      assert.equal((await user.get()).data().minorProfileApproved, false);
      assert.equal((await db.collection('public_profiles').doc(uid).get()).exists, false);
    });
    await check('la migration v5 prepare les audiences meme si v4 est deja terminee', 'allow', async () => {
      const {backfillPublicProfiles} = require('../../functions/lib/cleanup.js');
      const previous = db.collection('migration_state').doc('public_profiles_and_follows_v4');
      await previous.set({completed: true, source: 'previous-release'});
      await backfillPublicProfiles.run({});
      assert.equal((await db.collection('migration_state').doc('public_profiles_and_follows_v5').get()).data().completed, true);
      assert.equal((await previous.get()).data().source, 'previous-release');
      assert.deepEqual((await conversation.get()).data().readableBy, []);
    });
  } finally {
    for (const stub of stubs) stub.mock.restore();
  }
}
