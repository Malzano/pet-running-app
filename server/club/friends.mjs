import { randomBytes, randomUUID } from 'node:crypto';

// Called inside the service's authenticated command transaction. The feed has
// no location/heart-rate fields and no public account-search endpoint.
export function makeFriends({ db, now, requireValue, activities }) {
  const get = (sql, ...p) => db.prepare(sql).get(...p);
  const all = (sql, ...p) => db.prepare(sql).all(...p);
  const run = (sql, ...p) => db.prepare(sql).run(...p);
  const iso = n => new Date(n).toISOString();
  const uuid = v => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
  db.exec(`
    CREATE TABLE IF NOT EXISTS friend_codes(userID TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, code TEXT UNIQUE NOT NULL);
    CREATE TABLE IF NOT EXISTS friendships(lowID TEXT REFERENCES users(id) ON DELETE CASCADE, highID TEXT REFERENCES users(id) ON DELETE CASCADE, requesterID TEXT NOT NULL, acceptedAt INTEGER, createdAt INTEGER NOT NULL, PRIMARY KEY(lowID,highID));
    CREATE TABLE IF NOT EXISTS friend_blocks(userID TEXT REFERENCES users(id) ON DELETE CASCADE, blockedID TEXT REFERENCES users(id) ON DELETE CASCADE, PRIMARY KEY(userID,blockedID));
    CREATE TABLE IF NOT EXISTS friend_posts(id TEXT PRIMARY KEY, authorID TEXT REFERENCES users(id) ON DELETE CASCADE, workoutID TEXT NOT NULL, activity TEXT NOT NULL, endedAt INTEGER NOT NULL, elapsedSeconds INTEGER NOT NULL, distanceMeters REAL, createdAt INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, UNIQUE(authorID,workoutID));
    CREATE TABLE IF NOT EXISTS friend_cheers(postID TEXT REFERENCES friend_posts(id) ON DELETE CASCADE, userID TEXT REFERENCES users(id) ON DELETE CASCADE, PRIMARY KEY(postID,userID));
    CREATE INDEX IF NOT EXISTS friend_posts_author_date ON friend_posts(authorID,createdAt);
  `);
  function code(userID, rotate = false) {
    const saved = get('SELECT code FROM friend_codes WHERE userID=?', userID);
    if (saved && !rotate) return saved.code;
    const value = randomBytes(8).toString('hex').toUpperCase();
    run('INSERT INTO friend_codes VALUES(?,?) ON CONFLICT(userID) DO UPDATE SET code=excluded.code', userID, value);
    return value;
  }
  const pair = (a,b) => [a,b].sort();
  const edge = (a,b) => get('SELECT * FROM friendships WHERE lowID=? AND highID=?', ...pair(a,b));
  const blocked = (a,b) => get('SELECT 1 FROM friend_blocks WHERE (userID=? AND blockedID=?) OR (userID=? AND blockedID=?)', a,b,b,a);
  function canSee(userID, post) {
    if (!post || post.deleted) return false;
    if (post.authorID === userID) return true;
    const friendship = edge(userID, post.authorID);
    return friendship?.acceptedAt != null && post.createdAt >= friendship.acceptedAt && !blocked(userID, post.authorID);
  }
  function snapshot(user) {
    const connections = all(`SELECT f.*,u.id,u.alias FROM friendships f JOIN users u ON u.id=CASE WHEN f.lowID=? THEN f.highID ELSE f.lowID END WHERE f.lowID=? OR f.highID=? ORDER BY f.createdAt DESC`, user.id,user.id,user.id)
      .map(row => ({ id: row.id, alias: row.alias, status: row.acceptedAt != null ? 'accepted' : row.requesterID === user.id ? 'outgoing' : 'incoming', since: iso(row.acceptedAt ?? row.createdAt) }));
    const posts = all(`SELECT p.*,u.alias FROM friend_posts p JOIN users u ON u.id=p.authorID
      WHERE p.deleted=0 AND p.createdAt>? AND (p.authorID=? OR EXISTS(SELECT 1 FROM friendships f WHERE ((f.lowID=? AND f.highID=p.authorID) OR (f.highID=? AND f.lowID=p.authorID)) AND f.acceptedAt IS NOT NULL AND p.createdAt>=f.acceptedAt))
      ORDER BY p.createdAt DESC,p.id DESC LIMIT 100`, now()-30*86_400_000,user.id,user.id,user.id)
      .filter(post => canSee(user.id, post)).map(post => ({ id: post.id, authorID: post.authorID, alias: post.alias, workoutID: post.workoutID,
        activity: post.activity, endedAt: iso(post.endedAt), elapsedSeconds: post.elapsedSeconds, distanceMeters: post.distanceMeters,
        createdAt: iso(post.createdAt), cheerCount: get('SELECT COUNT(*) AS n FROM friend_cheers WHERE postID=?', post.id).n,
        cheeredByMe: !!get('SELECT 1 FROM friend_cheers WHERE postID=? AND userID=?', post.id,user.id) }));
    const blocks = all('SELECT u.id,u.alias FROM friend_blocks b JOIN users u ON u.id=b.blockedID WHERE b.userID=?', user.id);
    return { friendCode: code(user.id), connections, posts, blocks };
  }
  function command(user, input) {
    const d = input.data ?? {}, action = input.action;
    if (action === 'friendCode') { code(user.id, true); return {}; }
    if (action === 'friendRequest') {
      requireValue(typeof d.token === 'string' && /^[A-Fa-f0-9]{16}$/.test(d.token), 'Paste your friend’s 16-character code.');
      const target = get('SELECT userID FROM friend_codes WHERE code=?', d.token.toUpperCase())?.userID;
      requireValue(target && target !== user.id && !blocked(user.id,target), 'This friend code isn’t available.', 404);
      requireValue(get('SELECT COUNT(*) AS n FROM friendships WHERE lowID=? OR highID=?', user.id,user.id).n < 100 && get('SELECT COUNT(*) AS n FROM friendships WHERE lowID=? OR highID=?', target,target).n < 100, 'The friend limit has been reached.');
      run('INSERT OR IGNORE INTO friendships VALUES(?,?,?,NULL,?)', ...pair(user.id,target),user.id,now());
      return {};
    }
    if (['friendAccept','friendRemove','friendBlock','friendUnblock'].includes(action)) {
      requireValue(uuid(d.memberID) && d.memberID !== user.id, 'Choose a friend.');
      const p = pair(user.id,d.memberID), friendship = edge(...p);
      if (action === 'friendAccept') {
        requireValue(friendship && friendship.requesterID !== user.id && !blocked(...p), 'This request is no longer available.', 403);
        run('UPDATE friendships SET acceptedAt=COALESCE(acceptedAt,?) WHERE lowID=? AND highID=?', now(),...p);
      } else if (action === 'friendUnblock') {
        run('DELETE FROM friend_blocks WHERE userID=? AND blockedID=?', user.id,d.memberID);
      } else {
        // Remove this pair's old encouragements as well as access to posts.
        run('DELETE FROM friend_cheers WHERE (userID=? AND postID IN (SELECT id FROM friend_posts WHERE authorID=?)) OR (userID=? AND postID IN (SELECT id FROM friend_posts WHERE authorID=?))', ...p,...p.slice().reverse());
        run('DELETE FROM friendships WHERE lowID=? AND highID=?', ...p);
        if (action === 'friendBlock') {
          requireValue(get('SELECT id FROM users WHERE id=?', d.memberID), 'This account is no longer available.',404);
          run('INSERT OR IGNORE INTO friend_blocks VALUES(?,?)', user.id,d.memberID);
        }
      }
      return {};
    }
    if (action === 'friendPost') {
      const allowed = new Set(['workoutID','activity','earnedAt','elapsedSeconds','distanceMeters']);
      requireValue(Object.keys(d).every(k => allowed.has(k)), 'Only the displayed workout result can be shared.');
      const endedAt = Date.parse(d.earnedAt);
      requireValue(uuid(d.workoutID) && activities.has(d.activity) && Number.isFinite(endedAt) && endedAt <= now()+60_000 && endedAt >= now()-30*86_400_000
        && Number.isInteger(d.elapsedSeconds) && d.elapsedSeconds > 0 && d.elapsedSeconds <= 86_400
        && (d.distanceMeters == null || (Number.isFinite(d.distanceMeters) && d.distanceMeters >= 0 && d.distanceMeters <= 1_000_000)), 'Choose a saved workout from the last 30 days with valid results.');
      requireValue(!get('SELECT deleted FROM friend_posts WHERE authorID=? AND workoutID=?', user.id,d.workoutID)?.deleted, 'This shared workout was removed. Choose another workout to post.',409);
      run('INSERT OR IGNORE INTO friend_posts VALUES(?,?,?,?,?,?,?,?,0)', randomUUID(),user.id,d.workoutID,d.activity,endedAt,d.elapsedSeconds,d.distanceMeters ?? null,now());
      return {};
    }
    if (action === 'friendDeletePost') {
      requireValue(uuid(d.postID), 'Choose a post.');
      // Keep the identity tombstone so a delayed duplicate cannot undo deletion.
      run('DELETE FROM friend_cheers WHERE postID IN (SELECT id FROM friend_posts WHERE id=? AND authorID=?)', d.postID,user.id);
      run("UPDATE friend_posts SET deleted=1,distanceMeters=NULL,elapsedSeconds=0,activity='other',endedAt=0 WHERE id=? AND authorID=?", d.postID,user.id);
      return {};
    }
    if (action === 'friendCheer') {
      requireValue(uuid(d.postID), 'Choose a post.');
      const post = get('SELECT * FROM friend_posts WHERE id=?', d.postID);
      requireValue(canSee(user.id,post) && post.authorID !== user.id, 'This post is no longer available.',403);
      run('INSERT OR IGNORE INTO friend_cheers VALUES(?,?)', d.postID,user.id);
      return {};
    }
    requireValue(false,'Unknown friend action.');
  }
  return { snapshot, command };
}
