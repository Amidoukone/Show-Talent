#!/usr/bin/env node
// Backward-compatible staging-only entry point.
if (process.argv.some(arg => arg === '--environment' || arg.startsWith('--environment='))) throw new Error('This entry point is staging-only');
process.argv.push('--environment', 'staging');
await import('./prepare-release-candidate.mjs');
