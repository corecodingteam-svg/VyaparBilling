import { consentUrl, driveConfig, exchangeCode, signState, uploadToDrive, verifyState } from '../src/backups/drive';

const config = { clientId: 'client', clientSecret: 'secret', redirectUri: 'https://api.example.com/api/v1/backups/drive/callback' };
const reply = (body: unknown, status = 200) => ({ ok: status < 400, status, text: async () => JSON.stringify(body) }) as unknown as Response;

describe('Google Drive backup', () => {
  it('is off until the server has a client id, secret and public URL', () => {
    expect(driveConfig({})).toBeNull();
    expect(driveConfig({ GOOGLE_CLIENT_ID: 'a', GOOGLE_CLIENT_SECRET: 'b', PUBLIC_API_URL: 'https://x.example.com/' })?.redirectUri).toBe(
      'https://x.example.com/api/v1/backups/drive/callback',
    );
  });

  it('signs the state so only this server can name the company, and only for a while', () => {
    const state = signState('firm-1', 'key', 1000);
    expect(verifyState(state, 'key', 2000)).toBe('firm-1');
    expect(verifyState(state, 'other-key', 2000)).toBeNull();
    expect(verifyState(state.replace('firm-1', 'firm-2'), 'key', 2000)).toBeNull();
    expect(verifyState(state, 'key', 1000 + 16 * 60 * 1000)).toBeNull();
    expect(verifyState('garbage', 'key')).toBeNull();
  });

  it('asks only for access to its own files, offline', () => {
    const url = new URL(consentUrl(config, 'st'));
    expect(url.searchParams.get('scope')).toContain('drive.file');
    expect(url.searchParams.get('scope')).not.toContain('auth/drive ');
    expect([url.searchParams.get('access_type'), url.searchParams.get('state'), url.searchParams.get('redirect_uri')]).toEqual(['offline', 'st', config.redirectUri]);
  });

  it('exchanges the code for a refresh token and the account email', async () => {
    const http = jest.fn().mockResolvedValueOnce(reply({ access_token: 'at', refresh_token: 'rt' })).mockResolvedValueOnce(reply({ email: 'me@example.com' }));
    expect(await exchangeCode(config, 'code', http as unknown as typeof fetch)).toEqual({ refreshToken: 'rt', email: 'me@example.com' });
    await expect(exchangeCode(config, 'code', jest.fn().mockResolvedValue(reply({ access_token: 'at' })) as unknown as typeof fetch)).rejects.toThrow('refresh token');
  });

  it('creates the folder on first use and uploads into it', async () => {
    const http = jest
      .fn()
      .mockResolvedValueOnce(reply({ access_token: 'at' }))
      .mockResolvedValueOnce(reply({ files: [] }))
      .mockResolvedValueOnce(reply({ id: 'folder-1' }))
      .mockResolvedValueOnce(reply({ id: 'file-1' }));
    expect(await uploadToDrive(config, 'rt', 'shop.json.gz', Buffer.from('data'), http as unknown as typeof fetch)).toBe('file-1');
    const upload = http.mock.calls[3];
    expect(upload[0]).toContain('uploadType=multipart');
    expect(upload[1].body.toString()).toContain('"parents":["folder-1"]');
    expect(upload[1].headers.authorization).toBe('Bearer at');
  });

  it('reports what Google said when an upload is refused', async () => {
    const http = jest.fn().mockResolvedValueOnce(reply({ error: 'invalid_grant' }, 400));
    await expect(uploadToDrive(config, 'rt', 'f', Buffer.from('x'), http as unknown as typeof fetch)).rejects.toThrow('token refresh failed (400)');
  });
});
