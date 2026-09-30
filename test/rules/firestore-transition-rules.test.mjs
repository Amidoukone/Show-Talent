import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {initializeTestEnvironment, assertFails, assertSucceeds} from
  "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, deleteDoc, serverTimestamp} from "firebase/firestore";

const env = await initializeTestEnvironment({
  projectId: "demo-adfoot",
  firestore: {
    host: "127.0.0.1", port: 8080,
    rules: readFileSync(resolve("firestore.transition.rules"), "utf8"),
  },
});
try {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const uid of ["alice", "bob"]) {
      await setDoc(doc(db, "users", uid), {
        nom: uid, role: "joueur", estActif: true, authDisabled: false,
      });
      await setDoc(doc(db, "public_profiles", uid), {
        nom: uid, role: "joueur", profilePublic: true,
      });
    }
    await setDoc(doc(db, "users", "alice", "following", "bob"), {
      followerUid: "alice", followingUid: "bob", active: true,
    });
    await setDoc(doc(db, "conversations", "alice_bob"), {
      utilisateurIds: ["alice", "bob"],
    });
  });
  const alice = env.authenticatedContext("alice").firestore();
  const bob = env.authenticatedContext("bob").firestore();
  const outsider = env.authenticatedContext("outsider").firestore();

  // Old clients continue to read users; new clients read projections/edges.
  await assertSucceeds(getDoc(doc(alice, "users", "bob")));
  await assertSucceeds(getDoc(doc(alice, "public_profiles", "bob")));
  await assertSucceeds(getDoc(doc(alice, "users", "alice", "following", "bob")));
  await assertFails(getDoc(doc(bob, "users", "alice", "following", "bob")));
  await assertFails(getDoc(doc(outsider, "public_profiles", "bob")));
  await assertFails(setDoc(doc(alice, "public_profiles", "alice"), {nom: "forged"}));

  // Blocking is directional and only its owner can remove it.
  await assertSucceeds(setDoc(doc(alice, "blocks", "alice_bob"), {
    blockerUid: "alice", blockedUid: "bob", createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(bob, "conversations", "alice_bob", "messages", "blocked"), {
    expediteurId: "bob", destinataireId: "alice", contenu: "hello",
  }));
  await assertFails(deleteDoc(doc(bob, "blocks", "alice_bob")));
  await assertSucceeds(deleteDoc(doc(alice, "blocks", "alice_bob")));
  await assertSucceeds(setDoc(doc(bob, "conversations", "alice_bob", "messages", "after"), {
    expediteurId: "bob", destinataireId: "alice", contenu: "hello",
  }));
  console.log("Transition rules: old and new profile paths and blocks passed");
} finally {
  await env.cleanup();
}
