import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { createHash, randomUUID, randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { AppleAuth } from './apple-auth.mjs';
import { makeFriends } from './friends.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const iso = value => new Date(value).toISOString();
const activityTypes = new Set(['walking', 'running', 'cycling', 'hiking', 'swimming', 'yoga', 'functionalStrengthTraining', 'traditionalStrengthTraining', 'cardioDance', 'mindAndBody']);
const cheers = new Set(['wellDone', 'withYou', 'welcome', 'restWell']);
const uuid = value => typeof value === 'string' && /^[0-9a-f-]{36}$/i.test(value);
const requireValue = (condition, message, status = 400) => { if (!condition) throw new APIError(status, message); };
export class APIError extends Error { constructor(status, message) { super(message); this.status = status; } }

export function dayKey(time, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(time));
  const get = name => parts.find(part => part.type === name).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}
export function weekKey(time, zone) {
  const day = new Date(`${dayKey(time, zone)}T12:00:00Z`);
  day.setUTCDate(day.getUTCDate() - (day.getUTCDay() + 6) % 7);
  return day.toISOString().slice(0, 10);
}

export function makeClubService({ databasePath = ':memory:', encryptionKey, apple, now = () => Date.now() }) {
  requireValue(Buffer.isBuffer(encryptionKey) && encryptionKey.length === 32, 'A 32-byte encryption key is required');
  if (databasePath !== ':memory:') mkdirSync(dirname(databasePath), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(databasePath);
  db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, appleSubject TEXT UNIQUE NOT NULL, alias TEXT NOT NULL, refreshToken TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions(tokenHash TEXT PRIMARY KEY, userID TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, expiresAt INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS clubs(id TEXT PRIMARY KEY, ownerID TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL, timeZone TEXT NOT NULL, weeklyTarget INTEGER NOT NULL, createdAt INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS members(clubID TEXT REFERENCES clubs(id) ON DELETE CASCADE, userID TEXT REFERENCES users(id) ON DELETE CASCADE, joinedAt INTEGER NOT NULL, sharesActivity INTEGER NOT NULL DEFAULT 0, sharingSince INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(clubID,userID));
    CREATE TABLE IF NOT EXISTS invites(tokenHash TEXT PRIMARY KEY, clubID TEXT REFERENCES clubs(id) ON DELETE CASCADE, expiresAt INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS days(id TEXT PRIMARY KEY, clubID TEXT NOT NULL, userID TEXT NOT NULL, day TEXT NOT NULL, earnedAt INTEGER NOT NULL, UNIQUE(clubID,userID,day), FOREIGN KEY(clubID,userID) REFERENCES members(clubID,userID) ON DELETE CASCADE);
    CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY, clubID TEXT REFERENCES clubs(id) ON DELETE CASCADE, activity TEXT NOT NULL, scheduledAt INTEGER NOT NULL, durationMinutes INTEGER NOT NULL, cancelled INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS cheers(id TEXT PRIMARY KEY, clubID TEXT NOT NULL, senderID TEXT NOT NULL, recipientID TEXT NOT NULL, kind TEXT NOT NULL, day TEXT NOT NULL, createdAt INTEGER NOT NULL, UNIQUE(clubID,senderID,recipientID,kind,day), FOREIGN KEY(clubID,senderID) REFERENCES members(clubID,userID) ON DELETE CASCADE, FOREIGN KEY(clubID,recipientID) REFERENCES members(clubID,userID) ON DELETE CASCADE);
    CREATE TABLE IF NOT EXISTS commands(userID TEXT REFERENCES users(id) ON DELETE CASCADE, id TEXT NOT NULL, fingerprint TEXT NOT NULL, result TEXT NOT NULL, createdAt INTEGER NOT NULL, PRIMARY KEY(userID,id));
  `);
  const get = (sql, ...params) => db.prepare(sql).get(...params);
  const all = (sql, ...params) => db.prepare(sql).all(...params);
  const run = (sql, ...params) => db.prepare(sql).run(...params);
  const friends = makeFriends({ db, now, requireValue, activities: new Set(['americanFootball', 'archery', 'australianFootball', 'badminton', 'baseball', 'basketball', 'bowling', 'boxing', 'climbing', 'cricket', 'crossTraining', 'curling', 'cycling', 'elliptical', 'equestrianSports', 'fencing', 'fishing', 'functionalStrengthTraining', 'golf', 'gymnastics', 'handball', 'hiking', 'hockey', 'hunting', 'lacrosse', 'martialArts', 'mindAndBody', 'paddleSports', 'play', 'preparationAndRecovery', 'racquetball', 'rowing', 'rugby', 'running', 'sailing', 'skatingSports', 'snowSports', 'soccer', 'softball', 'squash', 'stairClimbing', 'surfingSports', 'swimming', 'tableTennis', 'tennis', 'trackAndField', 'traditionalStrengthTraining', 'volleyball', 'walking', 'waterFitness', 'waterPolo', 'waterSports', 'wrestling', 'yoga', 'barre', 'coreTraining', 'crossCountrySkiing', 'downhillSkiing', 'flexibility', 'highIntensityIntervalTraining', 'jumpRope', 'kickboxing', 'pilates', 'snowboarding', 'stairs', 'stepTraining', 'wheelchairWalkPace', 'wheelchairRunPace', 'taiChi', 'mixedCardio', 'handCycling', 'discSports', 'fitnessGaming', 'cardioDance', 'socialDance', 'pickleball', 'cooldown', 'swimBikeRun', 'underwaterDiving', 'other']) });
  function seal(value) {
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', encryptionKey, iv);
    const body = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]).toString('base64');
  }
  function unseal(value) {
    const data = Buffer.from(value, 'base64'), cipher = createDecipheriv('aes-256-gcm', encryptionKey, data.subarray(0, 12));
    cipher.setAuthTag(data.subarray(12, 28));
    return Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]).toString('utf8');
  }
  function transaction(action) {
    db.exec('BEGIN IMMEDIATE');
    try { const result = action(); db.exec('COMMIT'); return result; }
    catch (error) { db.exec('ROLLBACK'); throw error; }
  }
  function account(token) {
    requireValue(typeof token === 'string' && token.length <= 100, 'Sign in again to use Club.', 401);
    const user = get('SELECT users.* FROM users JOIN sessions ON sessions.userID=users.id WHERE tokenHash=? AND expiresAt>?', hash(token), now());
    requireValue(user, 'Sign in again to use Club.', 401);
    return user;
  }
  function membership(user, id, ownerOnly = false) {
    const club = get('SELECT clubs.*,members.joinedAt,members.sharesActivity,members.sharingSince FROM clubs JOIN members ON members.clubID=clubs.id WHERE clubs.id=? AND members.userID=?', id, user.id);
    requireValue(club, 'This club is no longer available to you.', 403);
    requireValue(!ownerOnly || club.ownerID === user.id, 'Only the club host can do that.', 403);
    return club;
  }
  function snapshot(user) {
    const clubs = all('SELECT clubs.* FROM clubs JOIN members ON members.clubID=clubs.id WHERE members.userID=? ORDER BY clubs.createdAt', user.id).map(club => {
      const weekStart = weekKey(now(), club.timeZone);
      const weekEnd = iso(Date.parse(`${weekStart}T12:00:00Z`) + 7 * 86_400_000).slice(0, 10);
      return {
        ...club, createdAt: iso(club.createdAt), weekStart, weekEnd,
        totalDays: get('SELECT COUNT(*) AS n FROM days WHERE clubID=?', club.id).n,
        members: all('SELECT users.id,users.alias,members.joinedAt,members.sharesActivity FROM members JOIN users ON users.id=members.userID WHERE clubID=? ORDER BY joinedAt,users.id', club.id).map(member => ({ ...member, joinedAt: iso(member.joinedAt), sharesActivity: !!member.sharesActivity })),
        days: all('SELECT id,userID AS memberID,day,earnedAt FROM days WHERE clubID=? AND day>=? AND day<? ORDER BY day,id', club.id, weekStart, weekEnd).map(day => ({ ...day, earnedAt: iso(day.earnedAt) })),
        events: all('SELECT * FROM events WHERE clubID=? AND scheduledAt>? ORDER BY scheduledAt,id', club.id, now() - 7 * 86_400_000).map(event => ({ ...event, scheduledAt: iso(event.scheduledAt), cancelled: !!event.cancelled })),
        cheers: all('SELECT * FROM cheers WHERE clubID=? AND createdAt>? ORDER BY createdAt DESC LIMIT 50', club.id, now() - 30 * 86_400_000).map(cheer => ({ ...cheer, createdAt: iso(cheer.createdAt) }))
      };
    });
    return { account: { id: user.id, alias: user.alias }, clubs, social: friends.snapshot(user), fetchedAt: iso(now()) };
  }

  function command(user, input) {
    requireValue(uuid(input.id) && typeof input.action === 'string', 'Invalid club action.');
    const fingerprint = hash(JSON.stringify(canonical(input)));
    return transaction(() => {
      const previous = get('SELECT * FROM commands WHERE userID=? AND id=?', user.id, input.id);
      if (previous) {
        requireValue(previous.fingerprint === fingerprint, 'This action identifier was already used.', 409);
        return JSON.parse(unseal(previous.result));
      }
      // A small social club is not a bulk event or messaging service.
      requireValue(get('SELECT COUNT(*) AS n FROM commands WHERE userID=? AND createdAt>?', user.id, now() - 60_000).n < 60, 'Please wait a minute before trying again.', 429);
      const data = input.data ?? {};
      let result = {};
      if (input.action.startsWith('friend')) {
        result = friends.command(user,input);
      } else if (input.action === 'create') {
        requireValue(typeof data.name === 'string' && data.name.trim().length >= 2 && data.name.trim().length <= 40, 'Give your club a name from 2 to 40 characters.');
        requireValue(Number.isInteger(data.weeklyTarget) && data.weeklyTarget >= 2 && data.weeklyTarget <= 70, 'Choose a weekly target from 2 to 70 days.');
        requireValue(typeof data.timeZone === 'string' && data.timeZone.length < 80, 'Choose a valid club time zone.');
        try { dayKey(now(), data.timeZone); } catch { throw new APIError(400, 'Choose a valid club time zone.'); }
        requireValue(get('SELECT COUNT(*) AS n FROM members WHERE userID=?', user.id).n < 10, 'You can belong to up to 10 clubs.');
        requireValue(get('SELECT COUNT(*) AS n FROM clubs WHERE ownerID=?', user.id).n < 5, 'You can host up to 5 clubs.');
        const id = randomUUID();
        run('INSERT INTO clubs VALUES(?,?,?,?,?,?)', id, user.id, data.name.trim(), data.timeZone, data.weeklyTarget, now());
        run('INSERT INTO members(clubID,userID,joinedAt) VALUES(?,?,?)', id, user.id, now());
        result = { clubID: id };
      } else if (input.action === 'join') {
        requireValue(typeof data.token === 'string' && /^[A-Za-z0-9_-]{40,60}$/.test(data.token), 'Paste a valid private invitation.');
        const invitation = get('SELECT * FROM invites WHERE tokenHash=? AND expiresAt>?', hash(data.token), now());
        requireValue(invitation, 'This invitation expired or was replaced. Ask the host for a new one.', 410);
        const existing = get('SELECT * FROM members WHERE clubID=? AND userID=?', invitation.clubID, user.id);
        if (!existing) {
          requireValue(get('SELECT COUNT(*) AS n FROM members WHERE userID=?', user.id).n < 10, 'You can belong to up to 10 clubs.');
          requireValue(get('SELECT COUNT(*) AS n FROM members WHERE clubID=?', invitation.clubID).n < 30, 'This club has reached its 30-member limit.');
          run('INSERT INTO members(clubID,userID,joinedAt) VALUES(?,?,?)', invitation.clubID, user.id, now());
        }
        result = { clubID: invitation.clubID };
      } else {
        requireValue(uuid(input.clubID), 'Choose a club.');
        const club = membership(user, input.clubID, ['invite', 'event', 'cancelEvent', 'removeMember', 'deleteClub'].includes(input.action));
        switch (input.action) {
        case 'invite': {
          const token = randomBytes(32).toString('base64url'), expiresAt = now() + 7 * 86_400_000;
          run('DELETE FROM invites WHERE clubID=?', club.id);
          run('INSERT INTO invites VALUES(?,?,?)', hash(token), club.id, expiresAt);
          result = { invitationURL: `pawpace://club/join?token=${token}`, expiresAt: iso(expiresAt) };
          break;
        }
        case 'sharing':
          requireValue(typeof data.enabled === 'boolean', 'Choose an activity-sharing preference.');
          run('UPDATE members SET sharesActivity=?,sharingSince=? WHERE clubID=? AND userID=?', +data.enabled, now(), club.id, user.id);
          break;
        case 'day': {
          requireValue(club.sharesActivity, 'Activity sharing is off for this club.', 403);
          const earnedAt = Date.parse(data.earnedAt);
          requireValue(Number.isFinite(earnedAt) && earnedAt >= Math.max(club.joinedAt, club.sharingSince) - 1_000 && earnedAt <= now() + 60_000 && earnedAt >= now() - 7 * 86_400_000,
                       'This activity day is too old to share. Only days since joining and from the last week can sync.');
          run('INSERT OR IGNORE INTO days VALUES(?,?,?,?,?)', input.id, club.id, user.id, dayKey(earnedAt, club.timeZone), earnedAt);
          break;
        }
        case 'eraseDays':
          run('DELETE FROM days WHERE clubID=? AND userID=?', club.id, user.id);
          run('UPDATE members SET sharesActivity=0 WHERE clubID=? AND userID=?', club.id, user.id);
          break;
        case 'event': {
          const time = Date.parse(data.scheduledAt);
          requireValue(activityTypes.has(data.activity) && Number.isFinite(time) && time > now() && time < now() + 366 * 86_400_000
            && Number.isInteger(data.durationMinutes) && data.durationMinutes >= 5 && data.durationMinutes <= 240, 'Choose a future activity and 5–240 minutes.');
          run('INSERT INTO events VALUES(?,?,?,?,?,0)', input.id, club.id, data.activity, time, data.durationMinutes);
          break;
        }
        case 'cancelEvent':
          requireValue(uuid(data.eventID) && get('SELECT id FROM events WHERE id=? AND clubID=?', data.eventID, club.id), 'That activity is no longer available.', 404);
          run('UPDATE events SET cancelled=1 WHERE id=? AND clubID=?', data.eventID, club.id);
          break;
        case 'cheer':
          requireValue(uuid(data.recipientID) && data.recipientID !== user.id && cheers.has(data.kind), 'Choose a friend and an encouragement.');
          requireValue(get('SELECT userID FROM members WHERE clubID=? AND userID=?', club.id, data.recipientID), 'That friend has left this club.', 409);
          requireValue(get('SELECT COUNT(*) AS n FROM cheers WHERE clubID=? AND senderID=? AND day=?', club.id, user.id, dayKey(now(), club.timeZone)).n < 10, 'You’ve sent 10 encouragements today. Come back tomorrow.');
          run('INSERT OR IGNORE INTO cheers VALUES(?,?,?,?,?,?,?)', input.id, club.id, user.id, data.recipientID, data.kind, dayKey(now(), club.timeZone), now());
          break;
        case 'removeMember':
          requireValue(uuid(data.memberID) && data.memberID !== user.id, 'Choose another member.');
          run('DELETE FROM members WHERE clubID=? AND userID=?', club.id, data.memberID);
          // A removed member cannot rejoin using an older private link.
          run('DELETE FROM invites WHERE clubID=?', club.id);
          break;
        case 'leave':
          requireValue(club.ownerID !== user.id, 'Hosts must close their club before leaving.');
          run('DELETE FROM members WHERE clubID=? AND userID=?', club.id, user.id);
          break;
        case 'deleteClub': run('DELETE FROM clubs WHERE id=?', club.id); break;
        default: throw new APIError(400, 'Unknown club action.');
        }
      }
      run('INSERT INTO commands VALUES(?,?,?,?,?)', user.id, input.id, fingerprint, seal(JSON.stringify(result)), now());
      return result;
    });
  }

  const loginAttempts = new Map();
  async function route(method, path, token, input, address) {
    if (method === 'GET' && path === '/health') return { ok: true };
    if (method === 'POST' && path === '/v1/auth/apple') {
      const prior = loginAttempts.get(address);
      const attempt = prior && prior.until > now() ? prior : { count: 0, until: now() + 60_000 };
      requireValue(++attempt.count <= 10, 'Please wait before signing in again.', 429);
      if (loginAttempts.size > 10_000) for (const [key, value] of loginAttempts) if (value.until < now()) loginAttempts.delete(key);
      loginAttempts.set(address, attempt);
      let credential;
      try { credential = await apple.login(input); } catch { throw new APIError(401, 'Apple sign-in could not be verified. Please try again.'); }
      const sessionToken = randomBytes(32).toString('base64url');
      return transaction(() => {
        let user = get('SELECT * FROM users WHERE appleSubject=?', credential.subject);
        if (!user) {
          const id = randomUUID(), plants = ['Maple', 'Cedar', 'Willow', 'Clover', 'Fern', 'Aspen'];
          const salt = parseInt(hash(id).slice(0, 8), 16);
          user = { id, alias: `${plants[salt % plants.length]} ${String(salt % 1000).padStart(3, '0')}` };
          run('INSERT INTO users VALUES(?,?,?,?)', id, credential.subject, user.alias, seal(credential.refreshToken));
        } else { run('UPDATE users SET refreshToken=? WHERE id=?', seal(credential.refreshToken), user.id); }
        const expiresAt = now() + 30 * 86_400_000;
        run('DELETE FROM sessions WHERE expiresAt<=?', now());
        run('INSERT INTO sessions VALUES(?,?,?)', hash(sessionToken), user.id, expiresAt);
        return { token: sessionToken, account: { id: user.id, alias: user.alias }, appleUserID: credential.subject, expiresAt: iso(expiresAt) };
      });
    }
    const user = account(token);
    if (method === 'GET' && path === '/v1/clubs') return snapshot(user);
    if (method === 'POST' && path === '/v1/commands') return command(user, input);
    if (method === 'POST' && path === '/v1/auth/logout') { run('DELETE FROM sessions WHERE tokenHash=?', hash(token)); return {}; }
    if (method === 'DELETE' && path === '/v1/account') {
      await apple.revoke(unseal(user.refreshToken));
      transaction(() => run('DELETE FROM users WHERE id=?', user.id));
      return {};
    }
    throw new APIError(404, 'This request is not available.');
  }
  const server = createServer(async (request, response) => {
    response.setHeader('Content-Type', 'application/json');
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      const chunks = []; let size = 0;
      for await (const chunk of request) { size += chunk.length; requireValue(size <= 32_768, 'Request too large.', 413); chunks.push(chunk); }
      let input = {};
      try { if (size) input = JSON.parse(Buffer.concat(chunks)); } catch { throw new APIError(400, 'Invalid request.'); }
      requireValue(input && typeof input === 'object' && !Array.isArray(input), 'Invalid request.');
      const authorization = request.headers.authorization ?? '';
      const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
      const result = await route(request.method, new URL(request.url, 'http://localhost').pathname, token, input, request.socket.remoteAddress ?? 'unknown');
      response.end(JSON.stringify(result));
    } catch (error) {
      response.statusCode = error instanceof APIError ? error.status : 503;
      response.end(JSON.stringify({ message: error instanceof APIError ? error.message : 'Club is temporarily unavailable. Please try again.' }));
    }
  });
  server.requestTimeout = 20_000; server.headersTimeout = 10_000;
  return { server, close: () => db.close() };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  for (const key of ['CLUB_ENCRYPTION_KEY', 'APPLE_CLIENT_ID', 'APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY_PATH']) {
    if (!process.env[key]) throw new Error(`Missing required server configuration: ${key}`);
  }
  const service = makeClubService({
    databasePath: resolve(process.env.CLUB_DATABASE_PATH ?? './data/club.sqlite'),
    encryptionKey: Buffer.from(process.env.CLUB_ENCRYPTION_KEY, 'hex'),
    apple: new AppleAuth({ clientID: process.env.APPLE_CLIENT_ID, teamID: process.env.APPLE_TEAM_ID, keyID: process.env.APPLE_KEY_ID,
      privateKey: readFileSync(process.env.APPLE_PRIVATE_KEY_PATH, 'utf8') })
  });
  service.server.listen(Number(process.env.PORT ?? 8080), process.env.HOST ?? '127.0.0.1');
  process.on('SIGTERM', () => service.server.close(() => { service.close(); process.exit(0); }));
}
