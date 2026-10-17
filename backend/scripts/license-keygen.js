#!/usr/bin/env node
/* Makes an Ed25519 key pair for signing licences.
 *   node scripts/license-keygen.js
 * Keep the PRIVATE key on the server only (LICENSE_SIGNING_PRIVATE_KEY). Build the apps with the PUBLIC key
 * (--dart-define=LICENSE_PUBLIC_KEY=...). Never put the private key in an app, a repository or a log. */
const { generateKeyPairSync } = require('crypto');
const { privateKey, publicKey } = generateKeyPairSync('ed25519');
console.log('LICENSE_SIGNING_PRIVATE_KEY=' + privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64'));
console.log('LICENSE_PUBLIC_KEY=' + publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64'));
