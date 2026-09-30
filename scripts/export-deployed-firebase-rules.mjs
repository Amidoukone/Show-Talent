#!/usr/bin/env node

// Read-only snapshot of the two live Firebase Rules releases.
import {mkdir, readFile, writeFile} from "node:fs/promises";
import {resolve, join} from "node:path";
import {cert} from "firebase-admin/app";

const argv = process.argv.slice(2);
const option = (name) => argv[argv.indexOf(name) + 1];
const projectId = option("--project");
const keyPath = option("--service-account");
if (!["adfoot-staging", "adfoot-production"].includes(projectId) || !keyPath) {
  throw new Error("Usage: node scripts/export-deployed-firebase-rules.mjs --project PROJECT --service-account PATH");
}
const account = JSON.parse(await readFile(resolve(keyPath), "utf8"));
if (account.type !== "service_account" || account.project_id !== projectId) {
  throw new Error("Service account project_id does not match --project");
}
const accessToken = (await cert(account).getAccessToken()).access_token;
const get = async (resource) => {
  const response = await fetch(`https://firebaserules.googleapis.com/v1/${resource}`, {
    headers: {Authorization: `Bearer ${accessToken}`},
  });
  if (!response.ok) throw new Error(`Rules API HTTP ${response.status}`);
  return response.json();
};
const releases = await get(`projects/${projectId}/releases?pageSize=100`);
const outDir = resolve("artifacts", "deployed-rules", projectId);
await mkdir(outDir, {recursive: true});
for (const [service, filename] of [
  ["cloud.firestore", "firestore.rules"],
  ["firebase.storage", "storage.rules"],
]) {
  const release = releases.releases?.find((item) =>
    item.name?.split("/releases/")[1]?.split("/")[0] === service);
  if (!release) throw new Error(`No ${service} release found`);
  const ruleset = await get(release.rulesetName);
  const content = ruleset.source?.files?.map((file) => file.content ?? "")
    .join("\n") ?? "";
  if (!content) throw new Error(`Empty ${service} ruleset`);
  await writeFile(join(outDir, filename), content);
  console.log(`${projectId} ${service}: ${release.rulesetName}`);
}
console.log(`Saved deployed rules under ${outDir}`);
