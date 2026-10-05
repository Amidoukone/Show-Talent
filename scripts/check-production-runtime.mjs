// Read-only inspection of errors emitted after the production deployment.
import {readFile} from 'node:fs/promises';
import {cert} from 'firebase-admin/app';
import {createRequire} from 'node:module';

const since = process.argv[2];
if (!since || !Number.isFinite(Date.parse(since))) throw new Error('Expected deployment timestamp in ISO format');
const projectId = 'adfoot-production';
const filter = `timestamp >= "${new Date(since).toISOString()}" AND severity >= ERROR AND (resource.type="cloud_run_revision" OR resource.type="cloud_function")`;
let listPage;
if (process.argv[3] === '--firebase-cli-auth') {
  // Reuse the authenticated Firebase CLI account without exposing its tokens.
  const require = createRequire(import.meta.url);
  const {getGlobalDefaultAccount} = require('firebase-tools/lib/auth');
  const {requireAuth} = require('firebase-tools/lib/requireAuth');
  const {listEntries} = require('firebase-tools/lib/gcp/cloudlogging');
  const account = getGlobalDefaultAccount();
  if (!account) throw new Error('No signed-in Firebase CLI account');
  await requireAuth({project: projectId, ...account});
  listPage = (pageToken) => listEntries(projectId, filter, 100, 'desc', pageToken);
} else {
  if (process.argv[3]) throw new Error('Unknown authentication option');
  const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialPath) throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS or use --firebase-cli-auth');
  const account = JSON.parse(await readFile(credentialPath, 'utf8'));
  if (account.type !== 'service_account' || account.project_id !== projectId) throw new Error('Production credentials required');
  const token = (await cert(account).getAccessToken()).access_token;
  listPage = async (pageToken) => {
    const response = await fetch('https://logging.googleapis.com/v2/entries:list', {
      method: 'POST', headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({resourceNames: [`projects/${projectId}`], filter,
        orderBy: 'timestamp desc', pageSize: 100, ...(pageToken ? {pageToken} : {})}),
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) throw new Error(`Cloud Logging returned HTTP ${response.status}`);
    return response.json();
  };
}
const errors = [];
let pageToken;
for (let page = 0; page < 10; page++) {
  const data = await listPage(pageToken);
  for (const entry of data.entries ?? []) {
    // Do not print payloads: application errors can contain personal data.
    errors.push({timestamp: entry.timestamp, severity: entry.severity,
      service: entry.resource?.labels?.service_name ?? entry.resource?.labels?.function_name ?? 'unknown',
      insertId: entry.insertId});
  }
  pageToken = data.nextPageToken;
  if (!pageToken) break;
}
console.log(JSON.stringify({projectId, since, checkedAt: new Date().toISOString(),
  complete: !pageToken, errorCount: errors.length, errors}, null, 2));
if (pageToken || errors.length) process.exitCode = 1;
