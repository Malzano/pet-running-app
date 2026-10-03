import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, randomBytes, sign, verify } from 'node:crypto';
import { AppleAuth } from './apple-auth.mjs';

// Exercise the complete protocol with generated signing keys and an injected
// Apple HTTP transport. This does not claim verification against Apple's service.
test('Apple code exchange binds identities and signs secrets; revocation fails closed', async () => {
  const applePair = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const clientPair = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const nonce = randomBytes(32).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  function token(subject = 'test-subject') {
    const content = `${encode({ alg: 'RS256', kid: 'apple-test' })}.${encode({ iss: 'https://appleid.apple.com', aud: 'com.pawpace.app', sub: subject, iat: now, exp: now + 600, nonce: createHash('sha256').update(nonce).digest('hex') })}`;
    return `${content}.${sign('RSA-SHA256', Buffer.from(content), applePair.privateKey).toString('base64url')}`;
  }
  let exchangedSubject = 'test-subject', refreshToken = 'test-refresh', failRevocation = false;
  const requests = [];
  const auth = new AppleAuth({ clientID: 'com.pawpace.app', teamID: 'TESTTEAM', keyID: 'TESTKEY',
    privateKey: clientPair.privateKey.export({ type: 'pkcs8', format: 'pem' }),
    fetcher: async (url, options) => {
      if (url.endsWith('/auth/keys')) return { ok: true, json: async () => ({ keys: [{ ...applePair.publicKey.export({ format: 'jwk' }), kid: 'apple-test', use: 'sig' }] }) };
      requests.push(url);
      assert.equal(options.method, 'POST');
      assert.equal(options.body.get('client_id'), 'com.pawpace.app');
      const [header, payload, signature] = options.body.get('client_secret').split('.');
      assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'TESTKEY' });
      const claims = JSON.parse(Buffer.from(payload, 'base64url'));
      assert.equal(claims.iss, 'TESTTEAM'); assert.equal(claims.sub, 'com.pawpace.app');
      assert.equal(claims.aud, 'https://appleid.apple.com'); assert.equal(claims.exp - claims.iat, 300);
      assert.ok(verify('sha256', Buffer.from(`${header}.${payload}`), { key: clientPair.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
      if (url.endsWith('/auth/token')) {
        assert.equal(options.body.get('code'), 'single-use-code');
        assert.equal(options.body.get('grant_type'), 'authorization_code');
        return { ok: true, json: async () => ({ id_token: token(exchangedSubject), refresh_token: refreshToken }) };
      }
      assert.equal(url, 'https://appleid.apple.com/auth/revoke');
      assert.equal(options.body.get('token'), 'test-refresh');
      assert.equal(options.body.get('token_type_hint'), 'refresh_token');
      return { ok: !failRevocation };
    }
  });
  const input = { identityToken: token(), nonce, authorizationCode: 'single-use-code' };
  assert.deepEqual(await auth.login(input), { subject: 'test-subject', refreshToken: 'test-refresh' });
  exchangedSubject = 'different-account'; await assert.rejects(auth.login(input));
  exchangedSubject = 'test-subject'; refreshToken = ''; await assert.rejects(auth.login(input));
  await auth.revoke('test-refresh'); failRevocation = true; await assert.rejects(auth.revoke('test-refresh'));
  assert.equal(requests.filter(url => url.endsWith('/auth/revoke')).length, 2);
});
