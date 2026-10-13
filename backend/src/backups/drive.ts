import { createHmac, timingSafeEqual } from 'crypto';

/** Google OAuth client for Drive uploads; absent until the server is given GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET. */
export interface DriveConfig {
  clientId: string;
  clientSecret: string;
  /** Where Google sends the user back: `${PUBLIC_API_URL}/api/v1/backups/drive/callback`. */
  redirectUri: string;
}

export const driveConfig = (env: NodeJS.ProcessEnv = process.env): DriveConfig | null => {
  const { GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, PUBLIC_API_URL } = env;
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !PUBLIC_API_URL) return null;
  return { clientId: GOOGLE_CLIENT_ID, clientSecret: GOOGLE_CLIENT_SECRET, redirectUri: `${PUBLIC_API_URL.replace(/\/$/, '')}/api/v1/backups/drive/callback` };
};

// drive.file: the app can only see files it created itself, never the rest of the user's Drive.
const SCOPES = ['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/userinfo.email'];
const FOLDER = 'Billing Backups';

type Fetch = typeof fetch;

/** `state` ties Google's redirect back to the company that asked, and cannot be forged or reused for long. */
export function signState(firmId: string, secret: string, now = Date.now()): string {
  const body = `${firmId}.${now}`;
  return `${body}.${createHmac('sha256', secret).update(body).digest('hex')}`;
}

export function verifyState(state: string, secret: string, now = Date.now(), maxAgeMs = 15 * 60 * 1000): string | null {
  const [firmId, issued, signature] = state.split('.');
  if (!firmId || !issued || !signature) return null;
  const expected = createHmac('sha256', secret).update(`${firmId}.${issued}`).digest('hex');
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  return now - Number(issued) <= maxAgeMs ? firmId : null;
}

export const consentUrl = (config: DriveConfig, state: string): string =>
  'https://accounts.google.com/o/oauth2/v2/auth?' +
  new URLSearchParams({
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    response_type: 'code',
    scope: SCOPES.join(' '),
    // offline + consent: Google then returns a refresh token, which is what lets the server upload unattended.
    access_type: 'offline',
    prompt: 'consent',
    state,
  }).toString();

async function json(res: Response, what: string) {
  const text = await res.text();
  if (!res.ok) throw new Error(`Google ${what} failed (${res.status}): ${text.slice(0, 200)}`);
  return JSON.parse(text) as Record<string, unknown>;
}

/** Exchanges the code from Google's redirect for a refresh token and the account's email. */
export async function exchangeCode(config: DriveConfig, code: string, http: Fetch = fetch) {
  const token = await json(
    await http('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ code, client_id: config.clientId, client_secret: config.clientSecret, redirect_uri: config.redirectUri, grant_type: 'authorization_code' }),
    }),
    'sign-in',
  );
  if (typeof token.refresh_token !== 'string') throw new Error('Google did not return a refresh token. Remove the app from your Google account and connect again.');
  const info = await json(await http('https://www.googleapis.com/oauth2/v2/userinfo', { headers: { authorization: `Bearer ${token.access_token}` } }), 'profile');
  return { refreshToken: token.refresh_token, email: typeof info.email === 'string' ? info.email : null };
}

export async function accessToken(config: DriveConfig, refreshToken: string, http: Fetch) {
  const token = await json(
    await http('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: config.clientId, client_secret: config.clientSecret, refresh_token: refreshToken, grant_type: 'refresh_token' }),
    }),
    'token refresh',
  );
  return token.access_token as string;
}

/** Uploads one backup into the "Billing Backups" folder (created on first use) and returns the Drive file id. */
export async function uploadToDrive(config: DriveConfig, refreshToken: string, fileName: string, data: Buffer, http: Fetch = fetch): Promise<string> {
  const auth = { authorization: `Bearer ${await accessToken(config, refreshToken, http)}` };
  const query = `name = '${FOLDER}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
  const found = await json(await http(`https://www.googleapis.com/drive/v3/files?${new URLSearchParams({ q: query, fields: 'files(id)' })}`, { headers: auth }), 'folder lookup');
  let folderId = (found.files as Array<{ id: string }> | undefined)?.[0]?.id;
  if (!folderId) {
    const created = await json(
      await http('https://www.googleapis.com/drive/v3/files', {
        method: 'POST',
        headers: { ...auth, 'content-type': 'application/json' },
        body: JSON.stringify({ name: FOLDER, mimeType: 'application/vnd.google-apps.folder' }),
      }),
      'folder creation',
    );
    folderId = created.id as string;
  }
  const boundary = `backup-${Date.now()}`;
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify({ name: fileName, parents: [folderId] })}\r\n`),
    Buffer.from(`--${boundary}\r\ncontent-type: application/gzip\r\n\r\n`),
    data,
    Buffer.from(`\r\n--${boundary}--`),
  ]);
  const uploaded = await json(
    await http('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id', {
      method: 'POST',
      headers: { ...auth, 'content-type': `multipart/related; boundary=${boundary}` },
      body,
    }),
    'upload',
  );
  return uploaded.id as string;
}
