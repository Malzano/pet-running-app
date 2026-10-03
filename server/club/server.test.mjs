import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID, generateKeyPairSync, sign, createHash } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { makeClubService, dayKey, weekKey } from './server.mjs';
import { AppleAuth } from './apple-auth.mjs';

async function fixture(context, options = {}) {
  let current = Date.parse('2026-09-26T08:00:00Z');
  const revoked = [];
  const service = makeClubService({ encryptionKey: randomBytes(32), now: () => current,
    // Only this test supplies an identity provider. There is no development
    // authentication endpoint or bypass in the executable server.
    apple: { login: async input => { assert.ok(input.identityToken); return { subject: input.identityToken, refreshToken: `refresh-${input.identityToken}` }; }, revoke: async token => { revoked.push(token); } }, ...options });
  await new Promise(resolve => service.server.listen(0, '127.0.0.1', resolve));
  context.after(async () => { await new Promise(resolve => service.server.close(resolve)); service.close(); });
  const base = `http://127.0.0.1:${service.server.address().port}`;
  async function request(path, { token, body, method = body ? 'POST' : 'GET' } = {}) {
    const response = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: response.status, data: await response.json() };
  }
  const login = async subject => {
    const result = await request('/v1/auth/apple', { body: { identityToken: subject } });
    assert.equal(result.status, 200); return result.data;
  };
  const command = (session, action, clubID, data = {}, id = randomUUID()) => request('/v1/commands', { token: session.token, body: { id, action, clubID, data } });
  return { request, login, command, revoked, time: () => current, advance: ms => { current += ms; } };
}

async function joined(context) {
  const f = await fixture(context), host = await f.login('host'), friend = await f.login('friend');
  const created = await f.command(host, 'create', undefined, { name: 'Morning paths', timeZone: 'Asia/Bangkok', weeklyTarget: 7 });
  assert.equal(created.status, 200);
  const id = created.data.clubID;
  const invitation = await f.command(host, 'invite', id);
  const token = new URL(invitation.data.invitationURL).searchParams.get('token');
  assert.equal((await f.command(friend, 'join', undefined, { token })).status, 200);
  return { ...f, host, friend, id, token };
}

test('two accounts share one real club; invitation expiry, replacement and roles are enforced', async t => {
  const f = await joined(t);
  const outsider = await f.login('outsider');
  let snapshot = await f.request('/v1/clubs', { token: f.friend.token });
  assert.equal(snapshot.data.clubs.length, 1); assert.equal(snapshot.data.clubs[0].members.length, 2);
  assert.equal(snapshot.data.clubs[0].days.length, 0);
  assert.equal((await f.command(outsider, 'day', f.id, { earnedAt: new Date(f.time()).toISOString() })).status, 403);
  assert.equal((await f.command(f.friend, 'invite', f.id)).status, 403);
  assert.equal((await f.command(f.friend, 'event', f.id)).status, 403);
  await f.command(f.host, 'invite', f.id);
  assert.equal((await f.command(outsider, 'join', undefined, { token: f.token })).status, 410);
  const next = await f.command(f.host, 'invite', f.id);
  f.advance(8 * 86_400_000);
  assert.equal((await f.command(outsider, 'join', undefined, { token: new URL(next.data.invitationURL).searchParams.get('token') })).status, 410);
});

test('sharing requires consent, retries and copied day contributions count once', async t => {
  const f = await joined(t), data = { earnedAt: new Date(f.time()).toISOString() };
  assert.equal((await f.command(f.friend, 'day', f.id, data)).status, 403);
  assert.equal((await f.command(f.friend, 'sharing', f.id, { enabled: true })).status, 200);
  const id = randomUUID();
  assert.equal((await f.command(f.friend, 'day', f.id, data, id)).status, 200);
  assert.equal((await f.command(f.friend, 'day', f.id, data, id)).status, 200);
  assert.equal((await f.command(f.friend, 'day', f.id, data)).status, 200);
  let club = (await f.request('/v1/clubs', { token: f.host.token })).data.clubs[0];
  assert.equal(club.days.length, 1); assert.equal(club.totalDays, 1);
  assert.equal((await f.command(f.friend, 'day', f.id, { earnedAt: 'bad date' })).status, 400);
  assert.equal((await f.command(f.friend, 'day', f.id, { earnedAt: new Date(f.time() + 120_000).toISOString() })).status, 400);
  await f.command(f.friend, 'eraseDays', f.id);
  club = (await f.request('/v1/clubs', { token: f.host.token })).data.clubs[0];
  assert.equal(club.days.length, 0); assert.equal(club.totalDays, 0);
  // A lost acknowledgement replay must not recreate an erased contribution.
  await f.command(f.friend, 'day', f.id, data, id);
  assert.equal((await f.request('/v1/clubs', { token: f.host.token })).data.clubs[0].totalDays, 0);
  f.advance(60_000); await f.command(f.friend, 'sharing', f.id, { enabled: true });
  assert.equal((await f.command(f.friend, 'day', f.id, data)).status, 400);
});

test('idempotent creation survives reordered JSON and rejects reused IDs with different actions', async t => {
  const f = await fixture(t), host = await f.login('host'), id = randomUUID();
  const body = { id, action: 'create', data: { name: 'Trail friends', timeZone: 'UTC', weeklyTarget: 4 } };
  const first = await f.request('/v1/commands', { token: host.token, body });
  const repeated = await f.request('/v1/commands', { token: host.token, body: { data: { weeklyTarget: 4, name: 'Trail friends', timeZone: 'UTC' }, action: 'create', id } });
  assert.deepEqual(repeated.data, first.data);
  assert.equal((await f.request('/v1/clubs', { token: host.token })).data.clubs.length, 1);
  assert.equal((await f.command(host, 'create', undefined, { ...body.data, weeklyTarget: 5 }, id)).status, 409);
});

test('group events, fixed encouragements and member removal use shared server state', async t => {
  const f = await joined(t);
  const eventID = randomUUID();
  assert.equal((await f.command(f.host, 'event', f.id, { activity: 'walking', scheduledAt: new Date(f.time() + 3_600_000).toISOString(), durationMinutes: 20 }, eventID)).status, 200);
  assert.equal((await f.command(f.friend, 'cancelEvent', f.id, { eventID })).status, 403);
  let club = (await f.request('/v1/clubs', { token: f.friend.token })).data.clubs[0];
  assert.equal(club.events[0].id, eventID); assert.equal(club.events[0].cancelled, false);
  await f.command(f.host, 'cancelEvent', f.id, { eventID });
  assert.equal((await f.request('/v1/clubs', { token: f.friend.token })).data.clubs[0].events[0].cancelled, true);
  await f.command(f.friend, 'cheer', f.id, { recipientID: f.host.account.id, kind: 'wellDone' });
  await f.command(f.friend, 'cheer', f.id, { recipientID: f.host.account.id, kind: 'wellDone' });
  assert.equal((await f.request('/v1/clubs', { token: f.host.token })).data.clubs[0].cheers.length, 1);
  assert.equal((await f.command(f.friend, 'cheer', f.id, { recipientID: f.host.account.id, kind: 'custom text' })).status, 400);
  await f.command(f.host, 'removeMember', f.id, { memberID: f.friend.account.id });
  assert.equal((await f.request('/v1/clubs', { token: f.friend.token })).data.clubs.length, 0);
  assert.equal((await f.command(f.friend, 'join', undefined, { token: f.token })).status, 410);
  assert.equal((await f.request('/v1/clubs', { token: f.host.token })).data.clubs[0].cheers.length, 0);
});

test('logout and deletion revoke access and delete hosted clubs for all members', async t => {
  const f = await joined(t);
  assert.equal((await f.request('/v1/account', { token: f.host.token, method: 'DELETE' })).status, 200);
  assert.deepEqual(f.revoked, ['refresh-host']);
  assert.equal((await f.request('/v1/clubs', { token: f.host.token })).status, 401);
  assert.equal((await f.request('/v1/clubs', { token: f.friend.token })).data.clubs.length, 0);
  await f.request('/v1/auth/logout', { token: f.friend.token, method: 'POST' });
  assert.equal((await f.request('/v1/clubs', { token: f.friend.token })).status, 401);
});

test('private SQLite state and idempotency survive server restart', async t => {
  const folder = mkdtempSync(join(tmpdir(), 'pawpace-club-'));
  t.after(() => rmSync(folder, { recursive: true, force: true }));
  const encryptionKey = randomBytes(32), databasePath = join(folder, 'club.sqlite');
  // Separate nested test lifetimes ensure the first DB is actually closed.
  let host, commandID = randomUUID(), clubID;
  await t.test('write', async t => {
    const f = await fixture(t, { encryptionKey, databasePath }); host = await f.login('durable');
    clubID = (await f.command(host, 'create', undefined, { name: 'Persistent paths', timeZone: 'UTC', weeklyTarget: 7 }, commandID)).data.clubID;
  });
  await t.test('read and replay', async t => {
    const f = await fixture(t, { encryptionKey, databasePath });
    assert.equal((await f.request('/v1/clubs', { token: host.token })).data.clubs[0].id, clubID);
    assert.equal((await f.command(host, 'create', undefined, { name: 'Persistent paths', timeZone: 'UTC', weeklyTarget: 7 }, commandID)).data.clubID, clubID);
  });
});

test('club week boundaries use the chosen time zone across DST and Sunday', () => {
  assert.equal(dayKey(Date.parse('2026-09-27T18:00:00Z'), 'Asia/Bangkok'), '2026-09-28');
  assert.equal(weekKey(Date.parse('2026-09-27T18:00:00Z'), 'Asia/Bangkok'), '2026-09-28');
  assert.equal(weekKey(Date.parse('2026-09-27T18:00:00Z'), 'America/Los_Angeles'), '2026-09-21');
  assert.equal(weekKey(Date.parse('2026-03-08T10:30:00Z'), 'America/Los_Angeles'), '2026-03-02');
});

test('Apple tokens require a trusted RSA signature, audience, issuer, expiry and nonce', async () => {
  const pair = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...pair.publicKey.export({ format: 'jwk' }), kid: 'test', use: 'sig' };
  const auth = new AppleAuth({ clientID: 'com.pawpace.app', fetcher: async () => ({ ok: true, json: async () => ({ keys: [jwk] }) }) });
  const nonce = randomBytes(32).toString('base64url'), now = Math.floor(Date.now() / 1000);
  const claims = { sub: 'verified-account', iss: 'https://appleid.apple.com', aud: 'com.pawpace.app', iat: now, exp: now + 600, nonce: createHash('sha256').update(nonce).digest('hex') };
  function token(overrides = {}, privateKey = pair.privateKey) {
    const content = `${Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'test' })).toString('base64url')}.${Buffer.from(JSON.stringify({ ...claims, ...overrides })).toString('base64url')}`;
    return `${content}.${sign('RSA-SHA256', Buffer.from(content), privateKey).toString('base64url')}`;
  }
  assert.equal(await auth.validate(token(), nonce), 'verified-account');
  for (const invalid of [{ aud: 'another.app' }, { iss: 'https://wrong.example' }, { exp: now - 1 }, { nonce: 'wrong' }, { iat: now + 300 }]) {
    await assert.rejects(auth.validate(token(invalid), nonce));
  }
  await assert.rejects(auth.validate(token({}, generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey), nonce));
  await assert.rejects(auth.validate(token(), randomBytes(32).toString('base64url')));
});

test('private friendship requires acceptance; posts, cheers and removal enforce both accounts', async t => {
  const f = await fixture(t), a = await f.login('a'), b = await f.login('b'), outsider = await f.login('outsider');
  const social = async account => (await f.request('/v1/clubs', { token: account.token })).data.social;
  const bCode = (await social(b)).friendCode;
  assert.equal((await f.command(a,'friendRequest',undefined,{ token:bCode })).status,200);
  assert.equal((await social(a)).connections[0].status,'outgoing');
  assert.equal((await social(b)).connections[0].status,'incoming');
  assert.equal((await f.command(a,'friendAccept',undefined,{ memberID:b.account.id })).status,403);
  const post = { workoutID:randomUUID(),activity:'running',earnedAt:new Date(f.time()).toISOString(),elapsedSeconds:900,distanceMeters:2200 };
  await f.command(a,'friendPost',undefined,post);
  assert.equal((await social(b)).posts.length,0);
  assert.equal((await social(outsider)).posts.length,0);
  f.advance(1000);
  await f.command(b,'friendAccept',undefined,{ memberID:a.account.id });
  assert.equal((await social(b)).posts.length,0,'No historical posts exposed on accepting');
  f.advance(1000);
  const newPost = { ...post,workoutID:randomUUID() }, commandID = randomUUID();
  assert.equal((await f.command(a,'friendPost',undefined,newPost,commandID)).status,200);
  await f.command(a,'friendPost',undefined,newPost,commandID);
  await f.command(a,'friendPost',undefined,newPost);
  const feed = (await social(b)).posts;
  assert.equal(feed.length,1); assert.equal(feed[0].elapsedSeconds,900); assert.equal(feed[0].distanceMeters,2200);
  const id = feed[0].id;
  assert.equal((await f.command(outsider,'friendCheer',undefined,{ postID:id })).status,403);
  await f.command(b,'friendCheer',undefined,{ postID:id });
  await f.command(b,'friendCheer',undefined,{ postID:id });
  assert.equal((await social(a)).posts[0].cheerCount,1);
  await f.command(outsider,'friendDeletePost',undefined,{ postID:id });
  assert.equal((await social(b)).posts.length,1);
  await f.command(a,'friendDeletePost',undefined,{ postID:id });
  await f.command(a,'friendPost',undefined,newPost,commandID);
  await f.command(a,'friendPost',undefined,newPost);
  assert.equal((await social(b)).posts.length,0,'Delayed retries cannot revive a deleted post');
  await f.command(a,'friendPost',undefined,{ ...post,workoutID:randomUUID() });
  await f.command(b,'friendRemove',undefined,{ memberID:a.account.id });
  assert.equal((await social(b)).posts.length,0);
  assert.equal((await social(a)).connections.length,0);
});

test('friend blocks, replaced codes, malformed payloads and account deletion protect the feed', async t => {
  const f = await fixture(t), a = await f.login('a'), b = await f.login('b');
  const social = async account => (await f.request('/v1/clubs', { token: account.token })).data.social;
  const old = (await social(b)).friendCode;
  await f.command(b,'friendCode');
  assert.equal((await f.command(a,'friendRequest',undefined,{ token:old })).status,404);
  const next = (await social(b)).friendCode;
  await f.command(a,'friendRequest',undefined,{ token:next });
  await f.command(b,'friendBlock',undefined,{ memberID:a.account.id });
  assert.equal((await f.command(a,'friendRequest',undefined,{ token:next })).status,404);
  assert.equal((await social(b)).blocks.length,1);
  await f.command(b,'friendUnblock',undefined,{ memberID:a.account.id });
  assert.equal((await social(a)).connections.length,0);
  await f.command(a,'friendRequest',undefined,{ token:next });
  await f.command(b,'friendAccept',undefined,{ memberID:a.account.id });
  const post = { workoutID:randomUUID(),activity:'running',earnedAt:new Date(f.time()).toISOString(),elapsedSeconds:600 };
  for (const bad of [{ latitude:13 },{ heartRate:150 },{ elapsedSeconds:-1 },{ distanceMeters:-2 },{ activity:'invented' },{ elapsedSeconds:90000 },{ earnedAt:'bad' }]) {
    assert.equal((await f.command(a,'friendPost',undefined,{ ...post,...bad })).status,400);
  }
  await f.command(a,'friendPost',undefined,post);
  assert.equal((await social(b)).posts[0].distanceMeters,null);
  await f.request('/v1/account',{ token:a.token,method:'DELETE' });
  assert.equal((await social(b)).posts.length,0);
  assert.equal((await social(b)).connections.length,0);
});
