# PawPace private Club service

The native client and this service implement private clubs. **No hosted instance or real Apple sign-in has been configured or verified.** Local tests use a test-only injected identity provider and generated cryptographic keys. The executable server has no test account, public authentication bypass, or fake members.

## Run and connect

Use Node 22.13 or later with `node:sqlite` (tested here on Node 22.23.2). There are no npm dependencies. `npm test` runs real local HTTP/SQLite tests plus Apple token protocol tests with an injected transport.

The publisher must choose its Apple Developer team, phone bundle identifier and hosting account. Enable Sign in with Apple on that actual app identifier, create its associated server-side key, and keep the `.p8` file in the host's secret storage. Do not commit the key or paste it into a conversation.

Required server configuration:

| Environment variable | Value |
| --- | --- |
| `APPLE_CLIENT_ID` | Actual iPhone bundle ID; currently `com.pawpace.app`. This must match the signed client's token audience. |
| `APPLE_TEAM_ID` | The publisher's Apple Developer team ID. |
| `APPLE_KEY_ID` | ID of the configured Sign in with Apple key. |
| `APPLE_PRIVATE_KEY_PATH` | Host-local path to the private `.p8` secret. |
| `CLUB_ENCRYPTION_KEY` | A stable cryptographically random 32-byte key encoded as 64 hexadecimal characters, supplied by a secret manager. Protect and back it up separately from the database. Losing it prevents decryption of saved Apple refresh tokens. |
| `CLUB_DATABASE_PATH` | Optional persistent SQLite path; defaults to `./data/club.sqlite`. |
| `HOST` / `PORT` | Optional listen address/port; defaults to loopback `127.0.0.1:8080`. |

After supplying secrets in the process environment, run `npm start` from this directory. The process fails closed if required configuration is missing. `GET /health` reports process availability; it does not prove Apple configuration or disk durability.

Deploy one service instance with a persistent private disk and HTTPS termination. The current synchronous SQLite implementation is not a multi-replica database. Keep the database, WAL files, encryption key and Apple key out of public/static directories. Use host disk encryption, restrictive access and the publisher's backup/retention policy. The Node process should remain behind TLS and a reverse proxy. The current login limit keys on the direct remote address; configure per-client limits at the trusted proxy as well, rather than trusting arbitrary forwarded headers. Do not log request bodies, bearer/invitation tokens, Apple credentials or activity dates.

Set the phone's `PAWPACE_CLUB_API_URL` build setting to the deployed HTTPS origin, regenerate with XcodeGen if editing `project.yml`, and build with the owner's signing team. There is no HTTP client exception or fallback demonstration account. Requests reject redirects so credentials cannot be forwarded elsewhere. The Sign in with Apple entitlement is already present; its real provisioning is still required. Buddy and Planner remain usable if the Club URL is empty.

## Protocol and behavior

- `POST /v1/auth/apple` verifies Apple RS256 identity tokens, issuer, audience, freshness and a SHA-256 nonce. It exchanges the single-use code using an ES256 client secret, verifies the returned identity and stores an encrypted refresh token for revocation. It returns a random bearer session that expires in 30 days; only its hash is stored.
- `GET /v1/clubs` returns the authenticated user's memberships, current-week activity days, relevant events and recent encouragements. Read/write authorization is enforced on the server.
- `POST /v1/commands` accepts a UUID command ID, an action and structured parameters. Results are durable and encrypted. Repeated identical IDs return the original response; mismatched payloads fail. The Swift encoder and server canonicalization permit field-order changes.
- `POST /v1/auth/logout` invalidates the current session. Local sign-out also clears cached Club data and unsent actions even if the service cannot be reached.
- `DELETE /v1/account` first revokes the Apple refresh token, then removes the account and dependent data. If Apple revocation fails, deletion reports failure and can be retried. Deleting a host removes their clubs for every member. The user's personal Planner copies, Buddy and Apple Health records are not changed.

Invitations contain a random 256-bit bearer token, are stored as a hash and expire after seven days. Any signed-in person given the link can join. Only a host can replace a link, schedule/cancel group activities, remove members or close a club. Removing a member also replaces access by deleting the current invite. There is no public directory. Limits are 30 members per club, 10 clubs per account, five hosted clubs per account, 60 new commands per minute per account and 10 preset encouragements per sender/club/day.

Activity sharing defaults to off. The phone observes only its current local day with at least five credited movement minutes. It uploads a timestamped achievement, never a workout or step count. The service assigns that timestamp to a date in the club's chosen time zone and permits one contribution per member/date. No pre-join or pre-consent day is accepted; pending timestamps older than seven days expire. Historical backfill is not performed. Current implementation trusts the authorized client for movement qualification; it is not workout attestation and must not be used for prize, money or competitive rankings.

A club's Monday week and fixed target use its creation time zone; event times display in the phone's local time zone. Personal Planner copies have stable source event IDs and remain independently editable. Group cancellation does not delete a personal plan. The campsite uses aggregate contributions across all weeks; erasing days or leaving can reduce that total.

## Data and retention

| Data stored by service | Retention and controls |
| --- | --- |
| Apple subject, random account ID, generated plant alias, encrypted Apple refresh token | Until account deletion. Name and email scopes are not requested. |
| Hashed bearer sessions | Valid for 30 days; expired rows are cleaned on sign-in. Logout deletes the current session; account deletion removes every session. |
| Club names, host, time zone, goal, memberships and sharing consent timestamps | Until the relevant membership, club or account is deleted. The host owns group plans. |
| Hashed invite and expiration | Deleted when replaced, a member is removed, or the club is closed; an expired token cannot join. |
| Per-member activity date and earned timestamp | Until that member erases days, leaves/is removed, closes the club, or deletes their account. Current-week dates and aggregate lifetime total are returned to members. |
| Activity plans and preset encouragements | Group plans remain until club deletion. Encouragements are removed with either involved membership or club deletion; snapshots return at most 50 from the past 30 days. |
| Command ID, payload hash and encrypted result | Retained with the account to prevent retry replay, including replay after an activity day is erased. Raw command bodies are not stored. Results may include a generated club ID or invite, but never workout measurements. |

The database deletion controls operate on live records. The publisher must define and test backup expiration and restore procedures so restored backups cannot resurrect deleted accounts or days. No production backup policy exists yet. Do not claim immediate erasure from unspecified backups. Network infrastructure may process IP addresses; configure its logging and privacy disclosures for the actual host before launch.

The phone checks Apple authorization before sending queued actions, including after a cold launch, and listens for credential-revocation notifications. Revoked, missing, transferred or unknown credentials conceal the cached account and require sign-in again. Unsent data remains account-scoped; an unavailable check does not discard it. The app attempts to log out the revoked service session, but a request already in flight cannot be recalled. Real device and service verification remains outstanding.

The phone stores a device-only Keychain session and a protected, backup-excluded account cache/outbox. Memory photos, pet identities and underlying activity history are not part of the service schema. The phone privacy manifest declares linked User ID, Fitness, Health and Other User Content for app functionality, with no tracking. Health/Fitness cover the optional derived achievement, including HealthKit-derived activity. The public privacy policy and App Store answers must describe the final deployed service; the former Data Not Collected label is no longer appropriate with Club.

## Outstanding real-service acceptance

Use two separate Apple accounts on independently installed signed clients. Record results against the deployed build and service revision, without copying credentials into logs.

1. Complete real Sign in with Apple on both accounts; verify first/repeated sign-in, the actual code exchange, expiry, logout and account switching. Confirm the correct bundle audience. Test revoking Apple authorization. The phone checks Apple credential state before each sync and handles the Apple revocation notification, concealing the account and stopping later uploads. A failed state check retains offline data without sending it. Confirm these with the actual signed app. Server-to-server Apple revocation notifications, needed to invalidate sessions independently of an opened client, remain production hardening work.
2. Host creates a club and sends a private invite through the system share sheet. A second account joins; a third unrelated account cannot read or modify it. Replace the invite and verify its old link fails.
3. Check zero contributions before opt-in. Each account completes five qualifying minutes; both see two shared days after refresh. Repeat sync and imported/source copies; counts remain unchanged. Exercise a club/phone time-zone difference.
4. Queue encouragement and a qualifying day offline, relaunch, and reconnect. Confirm each appears once. Turn sharing off offline; queued days must not upload. Remove shared days and retry a previously acknowledged request; deleted days must stay absent.
5. Schedule an activity, add it to each Planner, and try adding it twice. Cancel from the host, verify the cancellation on the other client and the explanation for the independent personal copy.
6. Try host-only actions as a member. Remove a member; their contributions and encouragements disappear and the old invite no longer rejoins them. Verify the removed client's cache updates after reconnection.
7. Delete a real Apple-linked account and verify Apple token revocation, rejected old sessions, closure of hosted clubs and deletion of the account's dependent data. Verify Apple revocation failure is recoverable.
8. Restart the deployed service, verify durable state and idempotency, and exercise a backup/restore and deletion-retention drill. Confirm TLS, secret access, proxy limits and payload-free operational monitoring on the chosen host.

Local tests are evidence for rules, persistence and cryptographic validation, not for these real external interactions or production capacity. No service has been deployed and no account credentials have been supplied in this workspace.

## Primary references

- [Sign in with Apple token exchange](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens)
- [Apple credential states and revocation notifications](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider)
- [Apple token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens)
- [Apple health and health research rules](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research): the iCloud health-data restriction is why Club uses a separate service.
- [Privacy manifest collection categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)

## Friends and result feed (27 September)

The same authenticated snapshot now includes `social`. Accounts exchange a replaceable random 16-character private code and explicitly accept requests. There is no account-search endpoint. Each account can have at most 100 accepted/pending connections. A blocked account cannot request again; unblocking leaves both accounts disconnected. Removing a friendship also removes their mutual post cheers.

`friendPost` accepts only a saved workout ID, activity identifier, completion date, active seconds and optional distance. It rejects unknown fields, invalid metrics, future/older-than-30-day results and duplicate workout copies. Clients present this exact reduced payload for explicit posting; joining a club or recording a workout never auto-posts. The feed returns at most 100 posts shared in the last 30 days, newest first. Only the author and friends accepted before a post was created can read or cheer it. New friends cannot see historical posts. Counts on the dashboard describe shared posts, not someone's entire exercise history or live location. No live workout presence is transmitted.

Posts remain in the database until removed or the account is deleted. Deletion clears result fields and preserves a minimal author/workout identity tombstone to prevent delayed retries resurrecting it. Friendships, blocks, codes, posts, cheers and tombstones cascade on account deletion. Raw route, heart rate, calories, photos and companion identity have no feed schema fields. The account-scoped native outbox persists explicit actions and their stable command IDs across offline relaunches. Removed posts/people hide locally while their remote removal is pending; other clients update after syncing.

Additional real-service acceptance: exchange codes on two signed clients; request/accept; post with distance off/on; verify a third account and a newly accepted friend cannot see earlier posts; cheer once; go offline/relaunch/reconnect; remove a post and retry; remove/block/unblock; rotate a code; delete an account and verify all dependent records disappear. Local HTTP tests cover these rules with injected test identities, not actual Apple accounts.
