import { createHash, createPublicKey, createPrivateKey, sign, verify } from 'node:crypto';

const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');

export class AppleAuth {
  constructor({ clientID, teamID, keyID, privateKey, fetcher = fetch }) {
    Object.assign(this, { clientID, teamID, keyID, privateKey, fetcher });
    this.keys = []; this.keysExpireAt = 0;
  }

  async validate(token, nonce) {
    if (typeof token !== 'string' || token.length > 16_000 || typeof nonce !== 'string' || nonce.length < 32 || nonce.length > 128) throw new Error('Invalid Apple credential');
    const parts = token.split('.');
    if (parts.length !== 3) throw new Error('Invalid Apple credential');
    const header = JSON.parse(Buffer.from(parts[0], 'base64url'));
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url'));
    if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new Error('Invalid Apple credential');
    if (Date.now() >= this.keysExpireAt) {
      const response = await this.fetcher('https://appleid.apple.com/auth/keys', { signal: AbortSignal.timeout(10_000) });
      if (!response.ok) throw new Error('Apple sign-in is unavailable');
      this.keys = (await response.json()).keys;
      this.keysExpireAt = Date.now() + 3_600_000;
    }
    const jwk = this.keys.find(key => key.kid === header.kid && key.kty === 'RSA' && key.use === 'sig');
    if (!jwk) { this.keysExpireAt = 0; throw new Error('Apple signing key changed. Try again.'); }
    const valid = verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(parts[2], 'base64url'));
    const now = Math.floor(Date.now() / 1000);
    if (!valid || claims.iss !== 'https://appleid.apple.com' || claims.aud !== this.clientID
        || typeof claims.sub !== 'string' || !claims.sub || !Number.isFinite(claims.exp) || claims.exp <= now
        || !Number.isFinite(claims.iat) || claims.iat > now + 60 || now - claims.iat > 600
        || claims.nonce !== createHash('sha256').update(nonce).digest('hex')) throw new Error('Invalid or expired Apple credential');
    return claims.sub;
  }

  clientSecret() {
    const now = Math.floor(Date.now() / 1000);
    const content = `${encode({ alg: 'ES256', kid: this.keyID })}.${encode({ iss: this.teamID, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: this.clientID })}`;
    const signature = sign('sha256', Buffer.from(content), { key: createPrivateKey(this.privateKey), dsaEncoding: 'ieee-p1363' });
    return `${content}.${signature.toString('base64url')}`;
  }

  async login({ identityToken, nonce, authorizationCode }) {
    const subject = await this.validate(identityToken, nonce);
    if (typeof authorizationCode !== 'string' || !authorizationCode || authorizationCode.length > 4_000) throw new Error('Missing Apple authorization');
    const response = await this.fetcher('https://appleid.apple.com/auth/token', {
      method: 'POST', signal: AbortSignal.timeout(15_000),
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: this.clientID, client_secret: this.clientSecret(), code: authorizationCode, grant_type: 'authorization_code' })
    });
    if (!response.ok) throw new Error('Apple sign-in could not be completed. Try again.');
    const tokens = await response.json();
    if (await this.validate(tokens.id_token, nonce) !== subject || typeof tokens.refresh_token !== 'string' || !tokens.refresh_token) throw new Error('Apple credential mismatch');
    return { subject, refreshToken: tokens.refresh_token };
  }

  async revoke(refreshToken) {
    const response = await this.fetcher('https://appleid.apple.com/auth/revoke', {
      method: 'POST', signal: AbortSignal.timeout(15_000),
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: this.clientID, client_secret: this.clientSecret(), token: refreshToken, token_type_hint: 'refresh_token' })
    });
    if (!response.ok) throw new Error('Apple account access could not be revoked. Please try again.');
  }
}
