# GetWorkout

Single source of truth for this app. Any agent, in any tool, resumes from here.
To resume, read down to Feature notes; read those only for the feature at hand.

## Product

A workout app for everyone who trains, beginner to advanced. The core loop:
pick or build a program, log today's workout set by set, see progress. Its
signature is an interactive 3D body model used to browse exercises by muscle
and to show weekly training volume. Written from scratch; nothing is taken
from the earlier FitLab app.

## Decisions

App-wide decisions only. How each feature behaves is under Feature notes.

- **Identity**: display name GetWorkout, bundle id `com.getworkout.app`
  (permanent), repo `yigit-cuhadar/get_workout`.
- **Environments**: Firebase projects `getworkout-dev` and `getworkout-prod`,
  Firestore in `eur3`. Debug and profile builds use dev, release builds use
  prod; there are no flavors and one bundle id.
- **Repository**: public by the user's choice, so no secrets and no service
  account files are ever committed. Firebase client config files are not
  secrets; security rests on Firestore and Storage rules.
- **Platforms**: iOS + Android. Admin panel is Flutter web from this repo.
- **Language**: English only in v1. Every UI string goes through `gen_l10n`
  ARB files; exercise and program text is stored per language (`l10n.en`), so
  a language is added without schema or code changes.
- **Accounts**: starts as an anonymous Firebase user. Linking email, Google or
  Apple keeps the uid and all data. Signing in to an *existing* account from a
  guest session discards the guest data after a warning; there is no merge.
- **Monetization** (owner's picks, 2026-11-19): freemium via RevenueCat with
  a soft paywall. Monthly 7.99 USD and yearly 39.99 USD (regional prices per
  store), a 7-day trial on yearly only. The paywall shows once at the end of
  onboarding (after the program suggestion), after every workout's summary
  of a free user (owner's pick, 2026-11-20; it was once, after the first
  workout), and whenever a Premium feature is touched or from Profile; it can
  always be closed. Which paywall shows comes from RevenueCat offerings, not
  from app code, so that later, once ads run, installs attributed to ads
  (Apple Search Ads via AdServices, Play Install Referrer; an MMP only by a
  later decision) can get a hard paywall without an app update. Paid
  traffic (owner's pick, 2026-11-20): installs attributed to Apple Search
  Ads campaigns get the hard (not dismissible) onboarding paywall, with the
  same plans and the yearly 7-day trial; everyone else, and anything
  uncertain, keeps the soft one. Apple Search Ads only for now: no
  tracking prompt (ATT), no MMP, no Play Install Referrer yet. A hard
  paywall locks the app (owner's pick, 2026-11-20): past onboarding, a
  user whose current offering is hard and who has no Premium (a trial
  counts as Premium) gets the full-screen hard paywall on every app open,
  cold start or back from the background, until they start the trial or
  subscribe, and again if Premium lapses; Restore stays on it. Anything
  not known (the entitlement or the offering: loading, offline, an
  error) lets the user in until it is known or the next open.
  Premium = the program generator, 19 of 25 ready-made programs, history
  in charts beyond 2 weeks (every window that was 12 weeks free is now 2
  weeks: the strength and body charts; the Progress cards' lines show 2
  weeks for everyone, Premium too, longer history living on the chart
  pages), the weekly volume trend (earlier weeks stay free to browse one
  by one), and later progressive overload suggestions. There is no limit
  on programs (the "more than 3 own programs" rule was dropped,
  2026-11-19). A hard paywall (from the offering) stays open while a
  purchase awaits approval. Free forever: logging, history and calendar,
  exercises and custom exercises, the 3D model, the summary's comparison, body measurements
  and progress photos with compare, cardio and steps, calculators, the Live
  Activity, and later the Watch app, home screen widgets and exercise videos.
  Until store accounts exist, purchases run against a fake gateway.
- **Backend**: Blaze plan. Cloud Functions are used only where a client cannot
  be trusted or cannot do the job: RevenueCat webhook, account deletion,
  sending push announcements. The program generator runs on device.
- **Offline**: Firestore's persistent cache is the local database. The workout
  in progress is also kept in a local file so a crash never loses sets.
  Derived numbers are computed from workouts on read wherever the query is
  small; the only stored summary is `exerciseStats`.
- **Privacy**: minimal set. In-app account deletion, privacy policy link,
  analytics and crash reports on by default with an opt-out switch
  (owner's pick, 2026-11-20, replacing the asked consent; see Feature
  notes › Analytics). No age gate, health notice or data
  export (the user accepted the EU risk). Remote Config (the paywall A/B
  test, the update and maintenance gate) sends the Firebase installation ID for every user, consent or not.
- **Cloud Functions** (`functions/`): TypeScript, Node 22, 2nd gen, all in
  `europe-west1` (`src/config.ts`, set once with `setGlobalOptions`; the
  app's one Dart constant `functionsRegion` in
  `lib/app/functions_region.dart`, used by the app and the admin panel,
  must match). One file per
  function, exported from `src/index.ts`; logic takes its Admin SDK
  access as a parameter so `npm test` (lint, build, `node --test`) runs
  without an emulator; CI runs it. Deploying is the Architect's step
  (`firebase deploy --only functions --project <id>`), never an agent's.
- **Notifications**: local for rest end, workout reminders and measurement
  reminders; FCM topic push for announcements.
- **UX pass** (2026-11-13, owner's call): before the design phase the
  structure and flows are reworked with the default theme, as ordinary
  features (Group 10). Subscription stays open meanwhile. No feature is
  removed without the owner saying so. On 2026-11-13 the owner withdrew
  every pick made from questions and grey-box wireframes and asked for each
  screen to be designed afresh as simple mock-ups with variants, judged on
  repetition, clutter, what the eye misses and what makes a user give up.
  Until a screen is picked again, the app as built is the baseline:
  five tabs (Navigation), the Exercises tab and list (Exercise list).
  Picks are recorded here per screen as they are made.
- **Blocked on accounts the user will open when needed**: Google Play
  Console, RevenueCat. The Apple Developer account exists (2026-11-17,
  team A8J42TV74R); iOS push and Live Activity on a real device still need
  their setup. Development continues without them.

## Vocabulary

Stored as these string codes.

- **loggingType**: `reps`, `weight_reps`, `weighted_bodyweight`,
  `assisted_bodyweight`, `duration`, `weight_duration`
- **muscle** (19, equal to the model's groups): `pec`, `lat`, `trap`,
  `front_delt`, `mid_delt`, `rear_delt`, `biceps`, `triceps`, `forearm`,
  `abdominal`, `oblique`, `erector`, `glute`, `hip_flexor`, `abductor`,
  `adductor`, `quads`, `hamstring`, `calf`. Muscles the model lacks are filed
  under the nearest group (rhomboids → `trap`, serratus → `pec`, neck → `trap`,
  tibialis → `calf`, rotator cuff → `rear_delt`, brachioradialis →
  `forearm`). The mesh for `forearm` is named `wrist_*`.
- **equipment** (25): `barbell`, `ez_bar`, `trap_bar`, `dumbbell`,
  `kettlebell`, `plate`, `cable`, `machine`, `smith_machine`, `bench`, `box`,
  `back_extension_bench`, `pull_up_bar`, `dip_station`, `resistance_band`,
  `suspension_trainer`, `rings`, `medicine_ball`, `stability_ball`,
  `ab_wheel`, `landmine`, `sled`, `jump_rope`, `bodyweight`, `other`.
  `box` is any plyo box, step or raised surface; `back_extension_bench`
  covers back extension and GHD benches. `bodyweight` means no equipment at
  all, so it is only ever listed alone.
- **movementPattern** (14): `squat`, `hinge`, `lunge`, `horizontal_push`,
  `vertical_push`, `horizontal_pull`, `vertical_pull`, `carry`,
  `core_flexion`, `core_stability`, `rotation`, `explosive`, `isolation`,
  `mobility`
- **mechanic**: `compound`, `isolation`
- **laterality**: `bilateral`, `unilateral`, `alternating`. A unilateral set
  is logged once and means "per side".
- **level**: `beginner`, `intermediate`, `advanced`
- **force**: `push`, `pull`, `static`
- **position**: `standing`, `seated`, `supine`, `prone`, `incline`, `decline`,
  `hanging`, `supported` (on the arms: dips, L-sit, ring support),
  `inverted` (head down: handstands), `kneeling`, `side_lying`, `quadruped`
- **grip** (optional): `overhand`, `underhand`, `neutral`, `mixed`;
  **gripWidth** (optional): `narrow`, `shoulder`, `wide`
- **setType**: `normal`, `warmup`, `drop`
- **goal**: `build_muscle`, `get_stronger`, `lose_fat`, `general_fitness`

## Data model

Firestore. Timestamps are server timestamps; ids are generated on the client.

### Content (read: any signed-in user, guests included; write: admin claim)

**`exercises/{id}`**

| Field | Type | Notes |
|---|---|---|
| `status` | `draft` \| `live` \| `retired` | Clients read every status and show only `live`; never hard-deleted |
| `loggingType`, `mechanic`, `laterality`, `level`, `force`, `movementPattern`, `position` | code | |
| `grip`, `gripWidth` | code? | |
| `equipment` | code[] | 1+ |
| `equipmentAlternatives` | `{items: code[]}[]`? | 0-3 other equipment sets, each 1+ codes, none equal to `equipment` or each other; the exercise can be done with `equipment` or any one set. Content files write `code[][]`; Firestore has no arrays of arrays, so the import stores each set as `{items}` |
| `mainMuscles` | code[] | 1-2 |
| `secondaryMuscles` | code[] | 0-4 |
| `family` | string | Groups variations, e.g. `bench_press` |
| `familyRank` | int | Easier → harder within the family |
| `pinnedAlternatives`, `excludedAlternatives` | id[] | Admin overrides of the computed list |
| `defaultRestS` | int | |
| `incrementKg` | number? | Step for "add weight"; the import stores a double, but a web client (the admin panel) stores a whole number as an integer, so readers accept int or double and hashing treats `2` and `2.0` alike |
| `popularity` | int | Lower sorts first |
| `l10n.<lang>` | map | `name`, `aliases[]`, `setup[]`, `execution[]`, `mistakes[]`, `safety?`, `cues[]` |
| `updatedAt` | timestamp | Clients sync incrementally on this |
| `contentHash` | string | SHA-256 of the stored content, written by the import; a mismatch marks a document edited elsewhere |

Alternatives are computed on device: same main muscle and movement pattern,
the user's equipment first (an exercise fits when `equipment` or any of its
`equipmentAlternatives` sets fits), then popularity; pinned first, excluded
removed.
Variations are the other exercises of the same `family`, ordered by rank.

**`programs/{id}`** (catalog card): `status`, `premium`, `level`, `goal`,
`daysPerWeek`, `lengthWeeks?`, `equipment[]` (the primary `equipment` of
every exercise used, computed by the validator), `minutes` (`{min, max}`,
the shortest and longest session by the app's `estimateDay`, each day
rounded to whole minutes and at least 1; checked by the validator; the app
shows a card without a readable one without minutes), `dayList[]`
(`{name, exercises}` per day, computed from the days and checked by the
validator, so a locked premium program can list its days; a card without
a readable one lists none), `equipmentProfile`
(`full_gym` \| `home_gym` \| `dumbbells` \| `bodyweight` \| `bands`, for
filtering; every exercise fits it through `equipment` or an alternative set),
`order` (unique int, the catalogue's default sort),
`l10n.<lang>.{name, summary}`, `updatedAt`, `contentHash`. Seeded from
`content/programs/<id>.json`, which holds the card and `days` together.

**`programs/{id}/detail/main`**: `days[]` (shape below, without `targetKg`),
`updatedAt`, `contentHash`. Readable when the program is not premium or the
reader has an active entitlement.

### Per user (read/write: owner only)

**`users/{uid}`**: `profile` (goal, level, daysPerWeek, equipment[], sex,
birthYear, heightCm, weightKg, targetWeightKg), `settings` (units,
effortScale, askEffort (absent is true), weekStart (`monday` \| `sunday` \| `saturday`; absent, or a
value this version does not know, is automatic), restTimer, warmups
(autoWarmups for older versions), seenTips[],
keepScreenOn, bar and plates (`barWeightKg`, `ezBarWeightKg`, `trapBarWeightKg`,
`plates[]`; each only while customised), stepGoal,
reminder times,
trackedMeasurements[], analyticsConsent), `favoriteExerciseIds[]`,
`exerciseNotes` (exercise id → the user's own note, at most 500
characters),
`activeProgram` (`programId`, `schedule` (ISO weekday `"1"`-`"7"` → the
program day index done on it; 1-7 entries, a day may be on several
weekdays or on none), `nextDayIndex`, `nextDate` `YYYY-MM-DD`,
`movedFrom?` `YYYY-MM-DD` (the date the next day was planned for before it
was moved earlier; training weekdays up to it rest), `startedAt`
device-clock timestamp). Documents written before 2026-11-19 have
`weekdays[]` (ISO 1-7) instead: they read as those weekdays doing the days
in turn by ascending weekday (0, 1, 2…), forever, and the next write of
the active program stores `schedule` and deletes `weekdays`. Rules check
`schedule` (keys `"1"`-`"7"`, int values 0-6, 1-7 entries).

**`users/{uid}/customExercises/{id}`**: `name`, `loggingType`,
`mainMuscles[]`, `secondaryMuscles[]`, `equipment[]`, `note`. Max 500.

**`users/{uid}/programs/{id}`**: `name`, `origin` (`own` \| `catalog` \|
`generated`), `sourceId?`, `lengthWeeks?` (1-52), `days[]` (1-7),
`premium?` (true on a copy of a premium ready-made program and on its
duplicates; see Feature notes, Programs), `updatedAt`. Starting a catalog program copies it here, so later catalog
edits do not change it. `name` is 1-60 characters.

- `days[]`: `name` (at most 40 characters, may be empty), `items[]` (1-20)
- `items[]`: `exerciseId`, `sets` (1-10), `repMin`/`repMax` or `durationS`,
  `restS`, `targetKg?`, `group?` (items sharing a group letter form a superset
  of 2 or a circuit of 3+; rest runs after the last item of each round)

**`users/{uid}/workouts/{id}`**: `startedAt`, `finishedAt`, `programId?`,
`dayIndex?`, `name`, `note?`, `exerciseIds[]` (for lookups), `exercises[]`.

- `exercises[]`: `exerciseId`, `name`, `loggingType`, `mainMuscles[]`,
  `secondaryMuscles[]` (copied so history survives edits and deletions),
  `group?`, `note?`, `sets[]`
- `sets[]`: `type`, `weightKg?`, `reps?`, `durationS?`, `toFailure`, `rir?`,
  `note?`, `drops[]?` (`weightKg`, `reps`), `done`

**`users/{uid}/exerciseStats/{exerciseId}`**: `records` (keys
`heaviestWeight`, `bestE1rm`, `bestSetVolume`, `mostReps`,
`longestDuration`; each `value`, `date`, `workoutId`), `last` (`date`,
`workoutId` and `sets` of the latest workout, shown as "last time"),
`history[]` (`date`, `workoutId`, `bestE1rmKg?`, `volumeKg`, `set`,
`workoutName`; one point per workout). A record's and a point's `set`
(`weightKg?`, `reps?`, `durationS?`) is the set that made the record, or
the workout's best working set (`bestSetOf`). Rebuilt from that exercise's
workouts whenever one is edited or deleted; stats stored before `set` and
`workoutName` were kept are rebuilt when their Strength page opens.

**`users/{uid}/cardio/{id}`**: `type`, `date`, `durationS`, `distanceKm?`,
`calories?`, `avgHeartRate?`, `incline?`, `note?`.

**`users/{uid}/bodyEntries/{id}`**: `date`, `weightKg?`, `measurements` (map
of cm values: neck, shoulders, chest, waist, abdomen, hips, and left/right
upper arm, forearm, thigh, calf; body fat is derived from them and the
profile, never stored), `photos` (map of `front` \| `right` \|
`left` \| `back` → storage path, which holds the photo's revision; see
Storage). A quick weight log is an entry with only `weightKg`; a
measurement day fills all three.

**`users/{uid}/pushTokens/{token}`**: `platform`, `updatedAt`.

**`users/{uid}/feedback/{id}`** (Help & feedback): `uid` (equal to the
path's), `email?` (where to reply, 3-254 characters; absent when left
empty), `message` (1-2000 characters), `source` (`profile` \| `rating`),
`appVersion` ("1.0.0+1"), `platform` (`ios` \| `android`), `osVersion`,
`deviceModel`, `locale` (the device's, "en-GB"; each detail a string of at
most 100, empty when unreadable), `status` (`open` \| `closed`),
`createdAt` (server time). The owner, guests included, may only create
them (validated, `status` open); nobody reads them back but admins, who
read them as the collection group `feedback` (index on `status`,
`createdAt` descending in `firestore.indexes.json`) and change only
`status`. Deleting the account deletes them with the rest of `users/{uid}`.

### Server-written

**`entitlements/{uid}`**: `premium`, `expiresAt` (a Firestore timestamp; the
webhook converts), `productId` (absent when no event named a product),
and the webhook's `lastEventMs` and `lastEventIds` (ordering and
redelivery). Written only by the RevenueCat webhook (and
`tool/set_premium.sh` on dev); readable by its owner. The rules read only
`premium` and `expiresAt`.

**`announcements/{requestId}`**: `locale`, `title`, `body`, `status`
(`sending`, `sent`, `failed`), `sentBy` (uid), `requestedAt`, and once
sent `sentAt` and `messageId` (FCM's). Written only by `sendAnnouncement`;
readable by admins.

### Storage

`users/{uid}/photos/{entryId}/{pose}-{revision}.jpg`, revision the capture
time in ms (a retake is a new file; the replaced one is deleted): owner
only, JPEG, max 5 MB.

### Cloud Functions

- `revenueCatWebhook` (HTTPS, `functions/src/revenuecat_webhook.ts`) →
  writes `entitlements/{uid}`; see the RevenueCat webhook decision.
- `deleteAccount` (callable, `functions/src/delete_account.ts`) → for the
  signed-in caller: `users/{uid}` with every subcollection (customExercises,
  programs, workouts, exerciseStats, cardio, bodyEntries, pushTokens, feedback and any
  added later) by recursive delete, `entitlements/{uid}`, Storage
  `users/{uid}/` (photos; a project without a default bucket has none,
  logged), then the auth user last, so a partial failure can be retried;
  every step succeeds when nothing is left. Refusals carry a
  machine-readable `details.reason`, which the app maps on: `recent-sign-in`
  (`failed-precondition`, a non-guest signed in more than 5 minutes ago)
  and `sign-in-not-deleted` (`internal`, the data is gone but the auth user
  is not; calling again finishes), and `apple-revoke-failed`
  (`failed-precondition`, nothing deleted). With `data.appleCode` (a fresh
  Apple authorization code) it first, after the recent sign-in check,
  exchanges the code at Apple and revokes the refresh token (else the
  access token) with a client secret it signs (ES256) with the
  `APPLE_SIGN_IN_KEY` secret (the .p8 PEM of key W3KP8AP8K2; team, key and
  client id are constants in `functions/src/apple.ts`); a refusal logs
  Apple's status and body and deletes nothing. Once the auth user is gone it deletes
  `entitlements/{uid}` once more (a failure is logged), so a webhook event
  racing the deletion leaves nothing; later events skip the uid. RevenueCat
  keeps its customer and its events keep coming until the store
  subscription, the user's to cancel, ends.
- `sendAnnouncement` (callable, `functions/src/send_announcement.ts`) →
  for a caller with the `admin` claim, input `{requestId, locale, title,
  body}`: claims `announcements/{requestId}` in a transaction, sends a
  notification message to topic `announcements_<locale>`, then records it
  sent. Only an FCM error that certainly means it was not accepted
  (invalid argument, payload or recipient, mismatched credential, auth
  errors, rate limits) records it `failed`, which a retry of the same id
  may send again; any other error (timeouts, `internal-error`,
  `server-unavailable`, unknown) leaves it `sending`, never sent again.
  Returns
  `{id, messageId, alreadySent}`; a request id already sent returns the
  first send without sending. Refusals carry `details.reason`:
  `not-admin` (`permission-denied`), `invalid-input` (`invalid-argument`,
  with `details.field`), `request-id-reused` (`invalid-argument`, the id
  holds other text), `in-progress` (`already-exists`, the id is
  `sending`; `details.requestedAt` in epoch milliseconds, which the panel
  uses to tell a stale one), `send-failed` (`internal`, FCM certainly
  refused; nothing was sent) and `outcome-unknown` (`unknown`, FCM may have
  taken it). A request left `sending` stays refused as in progress;
  different text gets a new id.

Admin access is a custom claim set by `tool/set_admin.sh`, using the project
owner's gcloud access token passed in `GOOGLE_ACCESS_TOKEN`.

## Features

Ordered. Tick when merged to main. Each: name — screens — acceptance.

Group 1, foundation
- [x] Scaffold and Firebase — dev and prod projects, rules deployed — app runs on the simulator against dev
- [x] Guest start and account linking — account sheet, sign-in — a guest's data survives linking; existing-account sign-in warns and replaces
- [x] App shell — five tabs, l10n, settings skeleton — tabs switch and keep state

Group 2, the model
- [x] 3D renderer — rotate, zoom, tap a muscle, press-and-slide across muscles with label and haptic — smooth on a mid-range phone, picks the right mesh
- [x] Muscle coloring API — per-muscle intensity — used later by exercise detail and volume

Group 3, exercises
- [x] Exercise domain and sync — incremental sync by `updatedAt` — library works offline after first sync
- [x] Admin panel — sign-in, exercise list, exercise editor with validation, draft/live/retire — an edit appears in the app after sync
- [x] Exercise content — 400+ exercises in English, loaded through the admin import — every muscle and equipment profile is covered
- [x] Library — model tab with muscle sheet (main vs secondary), list, search, filters, sort — find any exercise in a few taps
- [x] Exercise detail — text sections, model with worked muscles, alternatives, variations, favorite, add to workout or program
- [x] Custom exercises — short form, edit, delete — shown with a "Custom" label everywhere

Group 4, programs
- [x] Program builder — days, exercise picker, sets and rep range, rest, supersets and circuits, reorder
- [x] My programs and schedule — start a program, pick its training days (a fixed program day per weekday), missed-day prompt (do today, move, skip)

Group 5, workout
- [x] Active workout — single list, set rows with last time and goal, set types, drop sets, failure, RIR/RPE, notes, swap, add, reorder, minimize bar, crash recovery
- [x] Workout screen redesign — one exercise open at a time, set bar, set bubbles (long-press for type and removal), exercise cards reordered by holding a header, effort by feel / RIR / RPE with Failed, exercise details from the workout, add set by kind
- [x] Free workout — start empty (not in progress until an exercise is added), save as program at the end
- [x] Rest timer — auto start, +15 s, skip, notification
- [x] Rest timer on the lock screen — iOS Live Activity, Android ongoing notification
- [x] Workout on the lock screen — iOS Live Activity and Android ongoing notifications for the whole workout (workout and rest modes, tap opens it)
- [x] Finish and summary — records with a short celebration, `exerciseStats` update
- [x] History — list, workout detail, edit, delete, add a past workout; stats rebuilt

Group 6, progress
- [x] Calendar — month view of planned and done workouts and cardio
- [x] Weekly volume — model coloring and bar list against the 10-20 band; 12-week trend (Premium)
- [x] Strength — per-exercise records and e1RM chart (beyond 2 weeks Premium)
- [x] Today tab — next workout and week strip, quick actions, volume card, steps card

Group 7, programs for everyone
- [x] Catalog — 25 ready-made programs (6 free), filters, detail, premium lock, admin program editor
- [x] Program generator (Premium) — questions (goal, level, days, session length, equipment, focus muscles, excluded exercises, area to go easy on, preferred split), preview, save as an editable program

Group 8, body and extras
- [x] Weight log and measurement day — steps for weight, tracked measurements, four photos with ghost overlay, reminders, photo backup, compare
- [x] Cardio — log, list, detail, weekly chart
- [x] Steps — health permission, today, week and 30-day chart, daily goal
- [x] Calculators — calories (Mifflin-St Jeor), body fat (US Navy), 1RM, plates, macros, BMI and FFMI
- [x] Measurement summary — one summary/compare screen (baseline choice, body fat and lean mass, changes, target estimate, photo slider), opened after saving a measurement day, and as Compare on the Body page and from a measurement day's page; where-to-measure hints; body-fat box unticks; one waist mapping for body fat and calculators

Group 9, launch readiness
- [x] Onboarding — nine questions, suggested free program
- [x] Notifications — workout and measurement reminders, FCM announcements
- [ ] Subscription — paywall, RevenueCat, entitlement checks, restore
- [x] Account — delete account, privacy policy link, analytics consent

Group 10, UX pass (see Decisions; each screen is picked by the owner from mock-up variants before it is built)
- [x] Navigation — four tabs (Today / Train / Progress / Profile), Programs and Exercises merged, quick actions moved to their tabs — every existing screen is still reachable
- [x] Train, exercises view — model with a search box; one list page with search, filters, sort and +, opened by the box or filtered by a tapped muscle
- [x] Onboarding — a welcome page, then one question per page, all nine mandatory: goal, level, days, equipment, sex, birth year, height, weight, target weight. Choice questions are a list anchored to the bottom; number questions use a ruler
- [x] Today — week card, one prominent workout card with the only Start of a program day, sets this week for four muscles with the total, a calculators card with a chip per calculator, then steps with the goal and a bar
- [x] Train, My program — the day list has no Start; Ready-made, Generate, New program and Start empty workout stay
- [x] Programs and Exercises tabs — five tabs (Today / Programs / Exercises / Progress / Profile), Train and its segmented control gone; each tab its own stack, workouts start from Programs, every location and link lands as before
- [x] Workout, set entry — minus/plus steppers; tapping the number types it
- [x] Workout, rest — after a set the panel asks the effort (four options in a grid plus Failed, one line of explanation each, Skip) above a slim timer bar; the RPE scale uses the same layout with RPE 6 or less, 7, 8, 9, 10 and Failed. Once answered only the timer bar shows (time, +15 s, Skip); the next set's entry appears when the rest ends or is skipped. Superseded by the owner's design pick (see Design): the effort is asked in the set panel as rows with their meaning, a thin rest line above, then the panel becomes the countdown (+15 s, Skip rest)
- [x] Progress — one small widget per area, each opening its page: Body (last weight, curve, last body fat, Log weight, Measurement day), the calendar week, weekly volume, strength, cardio, steps with a bar
- [x] Calendar with workout history — one page: a week strip that opens to the month, then one list by day with workouts, cardio, planned days (with Start) and missed days, Show older workouts; Add past workout in the app bar. Workout history as its own page goes away
- [x] Body with Compare — two views, Overview (one chart with up to three series picked from weight, body fat, fat mass, lean mass, each measurement, weekly sets and daily steps, plus a target weight line; Log weight, Measurement day, history) and Compare (Previous / First / Other date, photos slider with poses, body fat, all changes, target weight)
- [x] Onboarding, birth year — a wheel showing the year only
- [x] Steps — today as a ring, the daily goal edited in place (steps of 100, tap the number to type), one chart switching between this week and the last 30 days
- [x] Workout summary — one prominent card with the name and four stats, records below, Done and Save as program at the bottom
- [x] Profile — every setting on one page in groups; Premium is a distinct card with Get Premium
- [x] Paywall — two layouts kept for an A/B test: plans as a list, plans as cards side by side; Remote Config `paywall_layout` assigns them
- [x] Program detail — a summary card (state, weekdays, length, Change days, Stop), days collapse
- [x] Program builder — stays as built: day chips, sets and reps in a sheet
- [x] Exercise detail — model with main and secondary muscles, a table of facts (equipment, level, mechanic, pattern, sides, logged as, also called), Setup and How to do it as numbered steps, Common mistakes, Safety and Cues each as their own card, Note, then one Similar exercises list tagged Alternative or Variation. One Add button in the app bar (workout or program). The Records and progress row leaves this page; the strength page stays reachable from Progress
- [x] Workout detail (history) — the summary card of the workout summary (date, program link, four stats), the workout note as its own card, sets as a table per exercise
- [x] Ready-made programs — cards with tags; the filters show as chips above the list and open the filters sheet
- [x] Generator — questions use the onboarding question layout; the preview shows weekly sets as bars and days that collapse, Regenerate and Save fixed at the bottom
- [x] Cardio — this week's summary on top, the 12-week chart, sessions by week; Log cardio is a full-width button fixed at the bottom
- [x] Weekly volume — stays as built with one body model, the legend and the muscle bars
- [x] Remaining pages (strength, calculators, account, sign-in with the Google mark on its button, your profile, warm-up settings, cardio form, workout edit, ready-made program page) keep their structure; their look is settled in the design phase

Group 11, design in code (the owner's plan; the studios are the target, see Design)
- [x] Theme — `ForgePreset` → `ForgeTheme` in forge_ui with the studio's colours, type scale, radii and borders, light and dark; Slate is the one preset (Measure and Graphite and the dev picker were removed, 2026-11-17); fonts bundled; the studio's own line icons (not an icon package), with the heavier form for the selected tab — `lib/app/theme.dart` swaps in and screens change without edits
- [x] Forge components — the MobileAppForge Studio cards built in forge_ui with every form and state on their card, widget tests for their behaviour; merged and tagged before the app uses them
- [x] App components — the GetWorkout Studio components in the app, every state on their card
- [x] Key screens — Today, Workout and Programs with every state on their boards, approved by the owner before the rest
- [x] The remaining screens by studio group (Ana sekmeler, Antrenman ve programlar, İlerleme, Formlar, Kurulum, hesap ve abonelik) — one group at a time, each with its owner-approved flow changes from Design built along with the look
- [x] Widget tests for the critical flows once the UI is stable; the final preset picked on a device (Slate, 2026-11-17)

How it runs: the theme and the key screens are done in the main session;
then Forge components and screen groups go to up to three implementers,
each on its own branch, and every device check is done one at a time in
the main session. Each group ends with a side-by-side page (simulator
screenshot next to the studio board, every state) that the owner approves
or sends back. A look the studio does not draw is a question for the owner
and is drawn in the studio first.

Where it stands (2026-11-18, end of Group 11):
- Ana sekmeler: done and merged (#105–#107).
- Antrenman ve programlar: done, checked on the iOS simulator and approved
  by the owner (2026-11-15); merged as #108–#111, studio #113, Forge
  v0.21.1 (search-field border). The device check's picks K1–K3 are under
  Design. The approval page and its canvases were local HTML, not kept.
- GetWorkout Studio's published link matches `design/studio.html` on main
  again (published 2026-11-16 from the owner's account).
- Sheets open on the root navigator over the tab bar (#114, Forge v0.21.2);
  checked on the simulator with a direct sheet (exercise filters) and a
  Forge sheet (Profile › Weight).
- Every ForgeMenu item in the app has an icon (checked 2026-11-16); menus
  built later get theirs as they are built.
- Content: getworkout-dev has the ready-made `dayList`; getworkout-prod has
  no content at all yet (a dry-run on 2026-11-16 would create all 466
  documents), so the first prod import belongs to Release.
- İlerleme: done, checked on the iOS simulator and approved by the owner
  (2026-11-16); merged as #116 (Weekly volume, Strength, Strength list,
  with the stats data change), #117 (Body overview, Body compare,
  Measurement summary), #118 (Calendar, Workout detail, Cardio, Steps,
  health cardio sessions), studio #119; Forge v0.22.0–v0.22.2. Every answer
  is a row of the canvas https://claude.ai/artifact/UdSCdEHtjQ17AMTiDD9qAR
  (codes in each PR body) and is written into the Design bullets.
- Owner to do: the Play Console Health apps declaration must list
  exercise, distance, total calories burned and heart rate (#118 reads
  cardio from Health Connect).
- To check on a device with fuller data (the dev account has one weigh-in,
  no measurement day, no steps): Body with several weigh-ins and
  measurement days and photos; the past-workout band's four figures with a
  large volume ("12,400 kg" may be cut); the Cardio session's distance
  tile ("18.4 km" may wrap); health cardio sessions on a real device;
  users who allowed steps before #118 are asked for workouts only through
  Allow access again.
- Formlar: done, checked on the iOS simulator and approved by the owner
  (2026-11-16); merged as #122 (Custom exercise, filters sheet, Bar and
  plates), #123 (Your profile, Profile question, Warm-up sets, Onboarding
  number questions), #124 (Log weight, Measurement day, Log cardio),
  studio #128; Forge v0.23.0–v0.24.3. The picks are under Design ›
  "Formlar, before the build" and "during the build"; the device check's
  own pick: Log cardio asks "Discard this cardio session?" when left with
  changes.
- Kurulum, hesap ve abonelik: done, checked on the iOS simulator and
  approved by the owner (2026-11-17); merged as #136 (the check branch
  joining #133 splash, onboarding, sign-in, guest sheet; #132 calculators;
  #134 account, delete account, paywall, generator preview; and the
  device-check fixes), studio #135; Forge v0.25.0–v0.25.6. The picks are
  under Design › "Kurulum, hesap ve abonelik, before the build", "during
  the build" and "Device check of Kurulum".
- Not checked on a device: Account and Delete account (need a real
  account; covered by #138's flow tests), the real Apple Health / Health
  Connect prompts, Android, large text.
- Sign in with Apple: done (#137), checked on the owner's iPhone.
- Critical-flow widget tests: done (#138 first run, guest to account,
  Account and Delete account, Premium, calculators; #139 logging a
  workout, programs and missed days, the builder, the generator, body
  logging), through the real router over fakes; no production bug found.
  Not covered: dragging the weight ruler, taking a measurement photo.
- Done: the final preset is picked (Slate, 2026-11-17); Measure, Graphite
  and the dev picker are removed. Next phase: Release (AGENTS.md › Phases).
- Next, in this order (2026-11-18 handoff):
  1. Subscription (the last unticked feature): the owner opens RevenueCat;
     App Store products first (the paid team A8J42TV74R is ready), then
     deploy `revenueCatWebhook` with its secret and try purchase and
     restore on the phone. Google Play waits for the Play Console.
  2. Deploy `deleteAccount` to dev, check deletion on the phone, then prod.
     (2026-11-18: live on dev; a Google-only account was deleted from the
     owner's iPhone with the provider re-sign-in (#145); deployed to prod the same
     day.)
  3. Photo backup: create the default bucket, deploy `storage.rules`, check
     the camera and backup on the phone.
  4. iOS push and the workout Live Activity on the phone (paid team).
     (2026-11-18: the Live Activity and an announcement push both arrive
     on the owner's iPhone.)
  5. An Android round: Google sign-in, Health Connect, the launch screen.
  6. Release: the first prod content import, then the store automation.
- Both studios' links match main again (published 2026-11-18 from a
  session: they belong to the owner's account, so a session publishes
  them directly). Owner to do: the Play Console Health declaration
  (above); the female body model before release.
- Small: the Forge Widgetbook use case "ListRow · Info hint" is broken.

Group 12, analytics (owner's plan, 2026-11-20; before the admin panel rework)
- [x] Opt-out collection — analytics and crash reports on by default for every user, the Profile → Privacy switch turns them off; the onboarding and over-the-tabs consent page removed; privacy policy and labels updated
- [x] Event plan in code — one typed analytics API in the app, screen views from the router, user properties and the user id, every event of the catalog (Feature notes › Analytics) — each event seen in DebugView on dev
- [ ] BigQuery export — Firebase Analytics linked to BigQuery daily on prod (and dev for checks) — raw events queryable
- [ ] Admin dashboard — a Dashboard page in the admin panel (drawn first) fed by an admin-only function over BigQuery and RevenueCat's metrics — funnel, retention, conversion and revenue at a glance

After release (owner's list, 2026-11-19; not before the first release):
- Health improvements.
- Apple Watch improvements.
- Home screen widgets.
- Streaks, weekly goals, achievements and the like.
- Progressive overload suggestions.
- Quick routines and templates outside programs.
- Exercise images and videos.
- Turkish and other languages.
- Timers for time-based sets and exercises, and rest set per series.

## Design

How anything looks lives only in the two studios; a design change is made
there, never here. The studio rules (tags, build check, components chosen
before drawing) are in AGENTS.md › Design studios.
- GetWorkout Studio https://claude.ai/artifact/PuK5WUbeyhVHMxA6THNDC2: the
  app's presets, rules, components and every screen with its states. Its
  saved settings download as tokens.json, which `lib/app/theme.dart` follows.
- MobileAppForge Studio https://claude.ai/artifact/6G4XXrCwoijEmEcFhNQDCU:
  the shared Forge components, drawn once; each card is that component's rule.

Decisions (the canvases they were drawn on are deleted):
- Colours stay muted. Loud directions (scoreboard, soft, night, block) and the
  Stone preset were rejected; black is not a default accent.
- Slate ships (owner's pick on the phone, 2026-11-17); Measure, Graphite and
  the dev preset picker are removed. Users still choose Light / Dark / System
  (Profile › Appearance). 2026-11-15: the Cobalt & Graphite preview made
  outside the studio was dropped and its branches deleted.
- Forge owns the theme engine (`ForgePreset` → `ForgeTheme`), type scale,
  controls, cards and feedback states; the app keeps what is about its product
  (set bubbles, set panel, exercise cards, the meaning of calendar marks).
- Every widget with more than one reasonable look was picked by the owner on
  a variants canvas; StepperField takes the workout screen's look.
- Review additions (owner's picks): restored program states (no active
  program, finished, Premium ended), the Front / Back toggle, exercise stars,
  favourites, Setup and Safety, own notes, workout minimize, the exercise ⋯
  menu, Add exercise and the workout note, circuits, reminder rows, Strength
  ranges (12 weeks free, 2 weeks since Monetization; 6 months, 1 year and All Premium), cardio session detail, the steps
  no-permission state, the workout edit page, Estimate body fat. New: the
  rest-day card, Duplicate program and day, the program's weekly sets, "Fits
  you" and a recommended row, the progress photo reminder, rest sound and
  vibration, bar and plates, keep screen on, Connected apps, the progression
  hint, plate breakdown, per-exercise rest, summary compared with last time,
  calendar filter and moving a planned day, the Body 7-day average, cardio
  from the health app, Measurement day as three steps, onboarding
  notification and health permission steps, generator swap / keep per
  exercise, Today while a workout runs, the ready-made program page, Add past
  workout, the paywall's three layouts and the sign-in page.
- Rounds of picks, applied in both studios: loose parts placed as components;
  consistency (calendar circles, set type menu, featured card, muscle model
  forms, Save placement, +15 s, effort tag); Bileşen uyumu and Kalan
  uyumsuzluklar (screens follow their components); the Exercise picker page;
  Forge independence (2026-11-15); Forge components drawn once, listed in
  GetWorkout Studio with links (2026-11-15); Tekrarlar (2026-11-15):
  screen-sized cards and the Forge sample pages that repeat their cards
  removed, ExerciseCard one card, Forge rules and the hand-kept component
  tables gone from GetWorkout's rules, looks live only in the studios.
- Açık kararlar (2026-11-15): the measurement-day camera is the app's own
  PoseCamera component (forge_camera stays the engine); the splash and its
  "Couldn't start" state are a Forge SplashScreen component; the macros
  calculator uses a new Forge Slider; the plate breakdown is Menu's info form
  (a floating card of facts, closed by tapping outside); a multi-series
  chart's target line takes its series' colour, dashed, labelled "Target";
  Today's missed day hides Start until it is answered; progress photo poses
  are Front, Right side, Left side, Back.
- Çelişkiler (2026-11-15), where the studio and these notes disagreed: the
  paywall keeps three layouts (A/B/C); the lock screen has +15 s and Skip on
  the right during a rest only; a cardio session opens a detail first; the
  set type menu lists the three types with the current one ticked; loading
  is shimmering grey bars in every component that loads; the step goal is
  typed in place. The feature notes above say each in its place.
- Görünüm kararları (2026-11-15): Retry is Button's outline form (40px) everywhere;
  every app bar has a centred 17px title, tab roots included; the selected tab
  is a heavier line icon with a bold label; buttons are 40px / 14px and the
  full-width primary at a page's bottom 48px / 15px; the Premium tag is filled
  with a lock everywhere; locked controls stay full colour with a lock and open
  the paywall; effort answers are rows with their meaning everywhere, also when
  editing a done set; choice pickers open as bottom sheets (time: the system
  picker; confirmations stay dialogs); Restore's result is a snackbar and a
  success closes the paywall. 
- Formlar, before the build (owner's picks, 2026-11-16; canvas was local
  HTML). Custom exercise: Main muscle, Also works, Equipment and Logged as
  are rows opening a Forge bottom sheet (checkbox list + Save; Logged as
  single choice) (CE12); a missing muscle or equipment shows the row's
  missing form (CE14); while saving a thin indeterminate bar under the app
  bar and Save off (CE15); several main muscles stay, comma-joined.
  Filters sheet: Muscle (all 19), Equipment, Movement pattern and Level
  are rows like Custom exercise's, each opening a checkbox sheet (owner's
  own answer), each row's value the chosen names ("Chest, Lats", "Any",
  cut with …) (FS14); My equipment's picker stacks
  over the filters sheet and returns to it (FS12); Clear all shows
  disabled when nothing is set (FS13); every equipment item scrolls in the
  picker. Bar and plates: the sheet's Remove in danger (BP2). Your
  profile: equipment matching no preset reads "Custom" (YP6); an
  unanswered field "—" (YP7); errors keep ErrorView's two lines. Profile
  question: choice and equipment questions load as title bars and ListRow
  skeleton rows (PQ7); height in ft in is typed as feet and inches (PQ9);
  the equipment answer follows the 2026-11-15 pick. Warm-up sets: no
  example card when off (WS8); a lb user's example "Bench Press at 175
  lb", rounded to 5 lb (WS9); the Custom row shows its sets (WS10); the
  last custom set's × faded and off (WS11); an invalid row has one danger
  line naming only the invalid field(s) (WS12). Log weight: the ruler
  starts at the last weigh-in, else the profile weight (LW05); a failed
  save is a snackbar over the sheet (LW06). Measurement day: Estimate
  body fat is the Body fat tracking rule with a live estimate (MD10); the
  weight step cannot be skipped (MD11, supersedes "every step can be
  skipped" for weight); the tune icon only on step 2 (MD12); the camera,
  empty photo slot and camera-off follow the PoseCamera, PhotoTile and
  PermissionPrompt cards. Log cardio: Save faded while Duration is empty,
  the row in its missing form (CL06); each row opens its picker (type
  sheet, date dialog then time wheel, h:mm:ss wheel, number sheet, note
  sheet) (CL08); speed types show "Speed 22.4 km/h" (CL09); heart rate and
  incline rows stay.
- Formlar, during the build (owner's picks, 2026-11-16; canvases were
  local HTML). Filter rows show two names and the rest counted ("Chest,
  Lats +2") (E1). Check lists (the filters' and Custom exercise's sheets,
  My equipment) are a Forge check sheet with 44px near-flush rows (E2,
  E6). Custom exercise's optional rows with nothing chosen read a muted
  "Optional" (E3). My equipment shows no count until equipment is chosen
  (E4); Only my equipment keeps "Pick your equipment first" and opens the
  picker first (E5). Rulers and wheels draw no label (screen readers keep
  it) (P1); in ft in the ruler reads "5 ft 11 in" (P2). An invalid warm-up
  box is the board's 40px left-aligned box with a danger border and the
  line (P3). The ft in entry sheet marks both fields and puts one message
  under the pair (P4). Number questions (Profile question, Onboarding,
  Measurement day step 1) keep the question at the top and put the unit
  switch, value, ruler and hint just above Save / Continue, close to the
  thumb (P5, owner's own direction). Cardio's distance, calories, heart
  rate and incline open a sheet with a typed number field (B2). With the
  camera off only the bottom bar's "Skip this photo" shows (B3). Log
  weight from Progress opens the sheet over Progress (B4). Editing a
  measurement day without a weight adds the ruler's weight (B5). Estimate
  body fat without sex or height is a row leading to Your profile (B6). A
  kept photo not on this device shows PhotoTile's loading form (B7). The
  note hint is "Add a note" (B8). A snackbar shows over an open sheet
  (Forge).
- Kurulum, hesap ve abonelik, before the build (owner's picks,
  2026-11-17; canvas was local HTML). Splash: the failed state keeps the
  mark and name with one line "Couldn't start. Check your connection and
  try again." and an outline Retry (SP3, a Forge change); the slow-start
  line after 2 s (SP4). Onboarding: the health step names Health Connect
  on Android and hides without a health store (ON5); a denied reminder
  goes on silently, reminder off (ON6); the suggestion page has no "Not
  now" (ON8); "Why this one" is written from the user's answers with the
  catalogue description under it (ON10); the equipment answer stays the
  2026-11-15 pick. Sign in: server email errors inline under the field
  (SI6); "Continue as guest" hidden for a guest (SI7). Guest account
  sheet: opened by the guest's Profile header; Account's Create account
  still opens Sign in in create mode (GA6); its "Use email instead" opens
  the email form in Create account mode (GA7). Account: the Data row says
  "Backed up" or "Waiting to sync", no time (AC-Q1); the Subscription row
  opens the paywall when free and Manage subscription when Premium
  (AC-Q2). Paywall: layout C as the board ("Yearly · 7 days free", "That
  is $5.00 a month.", "See monthly plan") (PW-Q1); the full renewal terms
  under the button, 11px muted (PW-Q2); with no prices a disabled
  "Subscribe" and no terms (PW-Q3); Forge's SubscriptionPlans is aligned
  with the board and the paywall built on it (PW-F1). Generator preview:
  Keep when regenerating uses the history icon (GP-Q1); Swap opens the
  picker's Swap form (GP-Q2); Change sets and reps opens the builder's
  targets sheet (GP-Q3); weekly sets as VolumeBand "n sets" (GP-Q4); days
  collapse, the first open (GP-Q5). Calculators: every calculator's
  inputs are chevron rows, each opening a number sheet (CP11, extended by
  the owner to all); a missing input shows "—" and the result area
  CalculatorResult.missing with "Add your <input> to see the result."
  (CP12, CP10); no "(cm)" in titles when the unit is in the box (CP9);
  activity short labels in the "Moderate · 3–5 days" pattern (CP14);
  Calories rows "Lose 0.5 kg a week" (−550), "Keep weight", "Gain 0.25 kg
  a week" (+275), 7,700 kcal per kg, lb labels for lb users (CP16); the
  daily-minimum states are muted row notes (CP17); plates "closest"
  keeps PlateCalculator's form (CP20).
- Kurulum, during the build (owner's picks, 2026-11-17, canvases
  apps/_review/kurulum2.html and kurulum3.html, local): lb users lose 1 lb
  and gain 0.5 lb a week (KC1 A); activity labels Sedentary · no exercise,
  Light · 1–3 days, Moderate · 3–5 days, Hard · 6–7 days, Very hard ·
  physical job (KC2 A); a number sheet's label has no unit, the unit sits
  muted inside the box, Log cardio too (KC3 B, Forge TextField unit
  v0.25.2–v0.25.3); Age reads "31" (KC4 A); LinkAccountSheet is a Forge
  component (KA1 A); sign-in error snackbars keep the error icon (KA2 A);
  a pushed sign-in page has a round back button (KA3 A, Forge v0.25.1);
  the suggestion's Start saves the copy without starting it (SG1); the
  suggestion card is FeaturedCard's outline form (SG2 A); "Why this one"
  is a sentence from the answers (SG3 A); the health step also shows when
  access was refused or is undetermined (SG4 B); a pending purchase's Got
  it closes the paywall (AP1 A); the store unavailable shows a disabled
  Subscribe (AP2 A).
- Device check of Kurulum (2026-11-17, canvas apps/_review/kurulum4.html,
  local): "Why this one" names only the answers the program matches, so a
  days count it does not match is not mentioned (CK1 B); the generator's
  goal question is onboarding's (CK2 A). Board rules fixed with it: the
  native launch screen on the featured colour (iOS and Android); the
  permission steps' buttons at the page bottom (Forge v0.25.6), their icon
  and title as the PermissionPrompt card draws them (CK3 A); sign-in from
  Profile full screen; the paywall lists
  Yearly first with Best value at the row's end (Forge v0.25.5); the
  generator preview title in sans; calorie rates unrounded ("0.25 kg");
  calculator rows "Weight", values sans muted.
- Delete account's sign-in check (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/NWzAVU8uZU6aUd9JdYx3w1): a user without a
  password confirms with their provider in the same "Confirm it's you"
  dialog, its field replaced by "Continue with Google" or "… Apple", and
  deletion goes on by itself after it (YG1 A); a user with a password
  also gets "or" and a button per linked provider under the field (YG2 B); the
  "or" is a new Forge component, OrDivider (YG3 B); picking another
  account in the provider's sheet brings the dialog back with "That's a
  different account. Sign in with the one you use here." (YG4 A). A user
  with Apple linked confirms "Delete everything?" with "Continue with
  Apple" in place of Delete ("…Sign in with Apple to confirm."), which
  revokes the app's Apple sign-in before deleting (YG5 B). The revocation
  asks Apple natively for a fresh authorization code, which the
  `deleteAccount` function revokes at Apple (Firebase's revocation refused
  it with `invalid-credential` on the owner's iPhone). A failure on this path never
  shows the password text: offline keeps "You're offline…", another
  Apple account keeps "That's a different account…", and the
  password-looking codes (`invalid-credential`, `wrong-password`) and
  anything else show "Couldn't delete your data"; a closed Apple sheet
  says nothing.
- Screen review (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/LTkRmeAmV7YSz6MdZJeS66): a workout open 4 h
  ends itself at its last set with a notification, and its summary gets an
  Edit button at the bottom right (K1 B, the button to be drawn); the
  number keyboard has a Next/Done bar and one tap moves weight→reps
  keeping the value (K2 A+B); notification permission is asked when Start
  is tapped on the first workout (K3 B); the muscle model fills its box,
  worked muscles in accent tones (K4 A); in dark mode the featured card
  keeps its fill with a muted line-strong border (K5 B); the app is named
  "GetWorkout" everywhere (K6 A); the Live Activity's names end with "…"
  while the set count and time stay whole (K7 A); analytics consent is a
  full-page step, also in onboarding, its buttons equal (K8, to be drawn);
  analytics and crash reports stay asked (K9 A); the target-weight step
  has its own title and a "Now 70 kg" marker on the ruler (K10 A);
  equipment is a bottom-anchored radio list like the goal question, no
  images, sub-equipment only in its details (K11, K12; to be drawn);
  onboarding's single-choice questions keep radio rows and Continue (K13
  withdrawn); Today without an active program but with saved programs
  says "Choose a program to start" with "See your programs" (K14 B); an
  Apple user's Profile header reads "Apple account" / "Signed in with
  Apple" with a person icon (K15 A); a trend with one entry is hidden
  until the second (K16 B); holding a bar shows a tooltip above it, others
  fade, dragging moves it (K17 A); with no rest running the effort
  question stays until answered, Settings can turn the question off, and
  every setting's default option is labelled "(default)", e.g. "By feel
  (default)" (K18 B); onboarding skips the reminder step when
  notifications are allowed and leaves reminders off (K19 A).
- Screen review, follow-up (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/3968osDfaNKbbUwkmvXVXL): the self-ended
  workout's summary has Edit as an AppBar text action at the top right
  (L1 B); onboarding's analytics step comes right after the target-weight
  question, before the notification step, drawn like the other permission
  steps (L2 A); equipment rows look like the goal question's, a row tap
  selects and an info button opens the set's equipment as checkboxes (L3
  A); the effort setting's choices start with "Off", the default marked
  "(default)", its option titles to be redrawn (L4 A); at large text the
  value AppBar grows with the text, timer, line and Finish stacking (L5
  B); a card header's detail that does not fit moves under the title,
  right-aligned (L6 A).
- Standards (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/144uTPX6c94VzNPSEDrtS6): the effort choices
  are Off · By feel (default) · "RIR · reps in reserve" · "RPE · rated
  effort", each scale with a line naming its steps (E1 B); a new Forge
  SectionLabel (13 px semibold, muted, 8 px above and below) replaces
  every section heading (S1 A); every single-choice list uses Forge
  ChoiceGrid's list form, and the app's ChoiceRow goes (S2 A); Forge
  EmptyView and ErrorView get a card form, full size when they replace the
  page and compact inside a section (S3 A); a new Forge IconButton, 44 px
  target and 20 px icon, muted by default, ink for back and ▶,
  on-featured in dark bands (S4 A); two in-page heading sizes: hero 30
  for the screen's one featured name, and a theme heading style 22/28 for
  questions, steps and card titles (S5 A); every set circle and group
  letter is a SetBubble: the set table its small form, the group letter
  a new letter form, the set-type menu's circle 28 px with an ink label
  (S6 A); PermissionPrompt gets a dialog form (icon circle, title, line,
  Allow, text "Not now") for in-app permission asks (S7 A); Progress's
  Strength and Cardio cards become StatTile (S8 A).
- Tabs (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/NcABYovwub3DiYhWgVFgAa): each tab has one job:
  Today is now, Progress how it is going, Programs the plan (P0 A). The
  week strip is only Progress's Calendar card (P1 A); this week's sets are
  only Progress's Weekly volume, which takes Today's four muscle bands (P2
  A); a program day starts only from Today's workout card, the Programs
  band has no Start (P3 A); a missed day is asked only on Today, the
  Programs band keeps its Missed row (P4 A); steps are only Progress's
  card, Today keeps the rest day's walk (P5 B); with no active program the
  ways in and the list live on Programs and Today's card offers only its
  one way (See your programs, or See ready-made programs), no Generate
  (P6 A); "Start empty workout" is a row under Today's workout card every
  day, gone from the rest-day card, the no-program card and Programs (P7
  A); the calculators are only Today's card, Profile › More › Calculators
  goes (P8, Today only). Supersedes the Today and Programs bullets of the
  2026-11-13 to 15 design decisions above.
- Kararlar · 5 (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/SY61cw8E47RXMbs2vKFem9): Strength's Exercise
  sheet is a Forge ChoiceGrid list of radio rows ("Last done Nov 13" under
  each name) under the search; a removed exercise is a normal row (M1 B).
  Forge StatTile's regular form gets the compact form's coloured change
  line, used by Progress › Strength: mono, success when the lift goes up,
  danger when it drops (M2 A, Forge v0.30.0). In the equipment question
  (onboarding and generator), equipment that matches no set selects no
  row, and a muted line under the list reads "Custom equipment · 9 items"
  with an Edit that opens the items as checkboxes (M3 A). The compact
  "Weekly sets in this program" card (program page, ready-made program)
  drops its two small body models: the five busiest muscles as
  full-width bars (label, sets, band bar), header "49 sets" and chevron
  unchanged; the full weekly sets page keeps its model (N1 B). The
  Programs tab no longer shows that card; it stays on the program page. A
  tap anywhere on the Programs tab's active-program band (not its ⋯ or
  day rows) opens the program's page, with no chevron or other mark
  (supersedes "the band opens nothing", 2026-11-15).
- Renkler · 6 (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/PZUvzt8A5QH2MKSRgeyCxx): R1 A, R2 A, R3 B,
  R4 A, R5 shared scale with the model's top end green. The muscle heat
  map and its legend run from `heat-low` to `heat-high` (Slate light
  #D3E3DA → #3F7D62, dark #3A4F47 → #79B597) by weekly sets, full at 20;
  a muscle over 20 stays full green, with no danger outline and no red on
  the model or legend (R1 A, R2 A, R5). Volume bars everywhere (Weekly
  volume, Weekly sets, a program's weekly sets) fill `band-below` /
  `band-in` / `band-over`: light #B9D3C4 / #3F7D62 / #A6473C, dark
  #3F5A4E / #79B597 / #E0907F (R4 A). Model, legend and bars share the
  band's numbers, 10 and 20 sets (R5). The Exercises tab's "Tap or slide
  across a muscle" hint is a TipBanner under the model card, gone for
  good after "Got it" (R3 B). Supersedes the accent ramp and danger
  outline above.
- Egzersiz · 7 (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/4aGCQch1LfGQFd78xFe3Fh): X1 A, X2 A, X3 A, X4
  Similar exercises card with Variations and Alternatives as separate
  groups and a see-all, X5 all favourite stars ink-muted when off and
  accent when on, X6 B. The exercise detail keeps only the star (and a
  custom exercise's ⋯) in its app bar; a stacked ForgeBottomActionBar holds
  "Add to workout" (primary) above "Add to program" (secondary) (X1 A).
  Models without a heat map use the green family: main muscles
  `heat-high`, secondary `muscle-secondary` (light #8FB3A0, dark
  #567A6A), the muscle under the finger `heat-high` ringed in `ink` and
  the scrub bar's dot `heat-high` (X2 A). Only the grey search pill flies
  between the Exercises tab and the list page (ForgeSearchField heroTag),
  its width easing; the filter button moves with its page (X3 A). The
  library row's star is a toggled ForgeIconButton; ForgeAppBar's toggled
  star is ink-muted while off too (X5). On Compare without photos the
  dates line ends in a small text button "Later day" opening the later
  days (X6 B). Same pass: the workout card's and generator row's ⋯ and the
  set panel's plates are ForgeIconButtons, and the program name field has
  no hint repeating its label.
- Egzersizler · 8 (owner's picks, 2026-11-18, canvas
  https://claude.ai/artifact/LACjPRwMzutXTieTMxgQZS): Y1 A, Y2 B, Y3 A
  kept, Y4 A. On the exercise list page only the search field and its
  filter button stay pinned under the title; the active filter chips,
  Clear all, Main · N / Also works · N, the count and the sort scroll away
  with the rows, and once they have gone a selected chip between the
  pill and the filter button names them ("5 filters", "Chest · Main"), a
  tap on it scrolling back to the top (ForgeSearchField summary, Forge
  v0.33.0) (Y1 A). The exercise picker's Add and Leave out forms open from
  the root navigator, so from inside a tab the iOS sheet (and Android's
  full-screen dialog) covers the tab bar too; Swap and Replace stay pushed
  in their tab, at `…/swap` (Y2 B). The analytics consent page stays a
  full-screen page (Y3 A); "New exercise" from the picker stays a full
  page over it (Y4 A).
- Programlar ve Profil (owner's picks, 2026-11-19, canvas
  https://claude.ai/artifact/WmZQNYSPgohJ4y3wJSmR6w): PA1 A, PP1 A, PA2 A.
  While a program day's workout runs, that day's row in the Programs
  band reads "In progress · 23 min" with Resume at its end, and a tap
  opens the workout (a free workout leaves the band as it is) (PA1). A
  free user's Premium card on Profile is a light card: "GetWorkout
  Premium", the store's trial as a tag when there is one, the three
  benefits with checks, Get Premium (PP1; a subscriber's card is
  unchanged). Cards titled with a program, workout or day name show it
  on one line, shrinking from 26 px to 18 px at least, then ending in
  "…" (PA2).
  Also PD1 B, PC1 B, PU1 kept. A program's own page, while active, shows
  in its top card only the training days as the eyebrow, "Next: <day>"
  with its date, "Week 2 of 8" and "1 of 3 days this week" over the bar
  in weeks, and Change days and Stop; no Start (it starts from Today)
  (PD1). Ready-made programs lists the active program first under "Your
  active program", "Week 2 of 8 · opens your copy", a tap opening the
  user's copy; all programs follow (PC1). The catalogue page and the
  copy's page keep their own layouts (PU1).
  Focus on open: the workout, exercise, "Your note" and cardio note
  sheets, the Bar weight dialog and the plate dialog's weight field;
  Save as program and the new custom exercise page stay unfocused (the
  set sheet's note too).
- Live Activity ve antrenman sayfası (owner's picks, 2026-11-19, canvas
  https://claude.ai/artifact/P7BEPoJoM524GsYGfBnqn6): LA1 A (without the
  workout's name), LA2 A, LA3 B, LA4 B, WO1 B. Lock screen while a set
  is due: the app icon with "Exercise 3 of 6" and the small elapsed time
  on top, the exercise's name large, "Set 2 of 3 · 80 kg × 8" and one dot
  per set (LA1). During a rest: the countdown, a bar emptying, and
  −15 s, +15 s and Skip working without opening the app (iOS 17+) (LA2).
  Compact Dynamic Island: as before while working; during a rest an
  emptying ring instead of the timer symbol (LA3). Expanded island
  during a rest: the large countdown and the emptying bar, no buttons
  (LA4). The workout in progress opens full screen from the bottom with
  ⌄ at the top left; a drag down closes it to the running bar (WO1).
- Programlar · çift giriş (owner's pick, 2026-11-19, canvas
  https://claude.ai/artifact/YaFwy2eH5tHzVFa1H1pNAn): PR1 A. Without an
  active program the Programs tab's "No active program" card has no
  button; Ready-made programs, Generate a program and New program are the
  rows below it, each once. Start empty workout stays on Today alone (P7).
- Egzersiz · düğmeler (owner's pick, 2026-11-19, canvas
  https://claude.ai/artifact/TDYNW9cLpTVgihVFauueeN): EB1 G, the owner's
  own answer after A–F were turned down. The exercise detail's app bar
  holds only ⋯, its menu: Add to workout, Add to program, Add to / Remove
  from favourites, and for a custom exercise Edit and Delete. No bottom
  bar. Supersedes X1 A.
- Widget önerileri (owner's picks, 2026-11-19, canvas
  https://claude.ai/artifact/NrdtEdUxNYu39V78ArNteh): W3 A, W5 A, W6 A,
  W7 A, W12 A, W13 A; W1, W2, W4, W8, W9, W10, W11 and W14 stay as they
  are. Progress's Body card shows the change and body fat beside the
  weight in its dark band, and the 12-week line has its end values and
  dates (W3). Weekly volume reads "7 of 49 planned sets" and keys its band
  colours: Under 10 · N, 10–20 · N, Over 20 · N (W5). The Strength card
  adds the e1RM's 12-week line, last point marked (W6). The Cardio card
  adds Mon–Sun minute bars in the cardio colour, an empty day a grey line
  (W7). The workout summary's top card shows each number's difference
  from the same day's last session, and long durations as "1 h 12 min"
  (W12). The active program band's bar has one segment per week, this week
  filling by days, with "1 of 3 days this week" above it (W13).
- Device check of Antrenman ve programlar (2026-11-15): K1 the swap note
  names logged warm-ups apart; K2 a program band's title is the day
  alone, when it is ("Today", "Mon, Nov 16") muted under it; K3 a
  snackbar sits above a screen's fixed bottom button, which therefore
  lives in the Scaffold's bottom bar.
- Asked afterwards (2026-11-15), where the studio had been changed without
  the owner: the program page's ⋯ holds Edit, Duplicate and Delete; a
  program workout's summary also offers Save as program; Delete account opens
  its page, then a dialog; the custom exercise detail has no history card;
  Strength ranges are 12 weeks free (2 weeks since Monetization) and 6 months, 1 year, All Premium; the
  effort question keeps its own Skip (removed by the owner, 2026-11-18); the onboarding health step says the app
  reads steps and cardio sessions and writes nothing; while one sign-in runs
  the other options are disabled; catalogue programs are list rows.
- Feature and flow decisions made during the design phase (owner's picks,
  2026-11-13 to 15). They supersede older feature notes and the code, which
  will be changed to match; the studio draws each:
  - Today: the week strip card, the next workout as a featured block (the
    only Start of a program day), sets this week (four muscles and the total),
    a calculators card (a chip per calculator), steps; a rest-day card (next
    day, suggestions) on rest days; while a workout runs, Resume in the
    featured block and the workout bar above the tabs.
  - Programs: the active program in a header band (week, progress, Start,
    this week's days Done / Missed / Next / Planned) with the missed-day
    prompt inside it under the missed row (Do it today, Move, Skip); "No
    active program" is an outline suggestion as on Today; finished and
    Premium-ended states; Duplicate in ⋯; the program's weekly sets.
  - Program page: ⋯ (Edit, Duplicate, Delete) in the app bar; state,
    weekdays, next day, progress, Start, Change days, Stop; days open and close.
  - Ready-made programs: search, filter chips (four or fewer as a chip bar,
    more as the filter sheet; active ones removable), the count, programs as
    list rows with the Premium lock; "Fits you" tags and a recommended row.
    The ready-made program page: tags, summary rows, weekly sets, days, Start
    this program, Duplicate in ⋯, Get Premium to start when locked.
  - Program builder: name and length, day chips with + Day, a day menu
    (Rename, Duplicate, Move earlier, Move later, Delete day), builder rows
    in one card, Add exercises, circuits; Save in the app bar.
  - Exercises: the search pill over the body model with a Front / Back
    toggle; a tap or a slide's release opens the list at once. The list:
    active filters as removable chips with Clear all, count and sort on one
    line, Main / Also works tabs from a muscle, A–Z as one list, stars.
  - Exercise picker: the exercise list itself with square checkboxes, chosen
    rows tinted, the count and "Add n exercises" in a bottom bar, "Create
    custom exercise" on no match. Swap from the workout is the same page in
    single choice: Similar first (Alternative / Variation), a tap swaps, a
    note says logged sets stay.
  - Exercise detail: front and back models, facts table, Setup and How to do
    it as numbered steps, Common mistakes, Safety, Cues, own note, Similar;
    favourite and Add in the app bar.
  - Workout: elapsed time and Finish in the header; one exercise card open at
    a time; set bubbles (done filled without a tick); the long-press set type
    menu; after Log set the set panel asks the effort as rows, then becomes
    the countdown (+15 s, Skip rest), with no rest strip on the workout
    screen; the progression hint; the plate breakdown on tapping the weight;
    the exercise ⋯ (swap, details, note, rest time, warm-up, remove); Add
    exercise and the workout note at the end; minimize to the workout bar;
    per-exercise rest.
  - Summary: one featured block with 2 × 2 stats compared with last time,
    records, a small front and back model of the muscles worked, Done and
    Save as program at the bottom, no tab bar.
  - Calendar: the month card always open, day rows with a date box (Start on
    a planned day, "Do it today" on a missed one), This week and Earlier, Show
    older workouts, + (Add past workout) in the app bar, All / Workouts /
    Cardio filter, moving a planned day.
  - Body: Overview (three boxes, the multi-series chart with chips and the
    target line, the 7-day average, Log weight, Measurement day, history) and
    Compare (photo slider with poses first, Previous / First / Other date,
    changes, the target estimate).
  - Measurement day: three steps (weight, measurements, photos) with Back /
    Next and a saved summary; Estimate body fat; the pose camera with the
    last photo as a ghost.
  - Weekly volume: week selector, one rotatable model painted by weekly sets
    (one accent ramp, an outline over 20), muscle bars against 10–20, the
    12-week trend on the page (Premium).
  - Strength: the exercise picked with a list row; records as rows;
    sessions.
  - Cardio: the week's summary in a header band, the 12-week chart,
    sessions by week, Log cardio fixed at the bottom; sessions from the
    health app.
  - Steps: a large ring, the daily goal as a pill stepper, one chart
    switching This week / Last 30 days with the goal line.
  - Forms: a form that edits something has Save in the top bar; an action
    that ends or starts a flow is a full-width button at the bottom.
  - Onboarding: a welcome page (logo, title, three numbered benefits, Get
    started, "I already have an account"), one question per page with
    Continue, notification and health permission steps, the result with a
    recommended free program.
  - Profile: a plain header, Premium as an outline card, Your profile and
    Calculators, setting groups; reminder rows, rest sound and vibration, bar
    and plates, keep screen on, Connected apps; Appearance as a segmented
    control.
- Moving the design into Flutter (owner's picks, 2026-11-14): each icon has
  one drawing in the studios (the named set, else the most used one) and the
  app draws that set, not an icon package; the presets' fonts are bundled
  with the app (Google Fonts, OFL); Slate is the one preset
  (the others were removed, 2026-11-17); its dark cards are a tonal fill.
- Building the components (owner's picks, 2026-11-14 to 15), drawn in the
  studios: the set panel's weight is typed on a tap and a plate button
  beside it (barbell, EZ bar and trap bar exercises only, not the Smith
  machine) opens the plate breakdown; a done set's
  effort has no Skip, and the no-rest effort question one Skip (removed by
  the owner, 2026-11-18); a card's
  count includes warm-ups; a collapsed group with every set done keeps its
  letter with a muted name; a lifted card leaves an empty gap; a superset or
  circuit keeps its items in step (one rounds count, one rest after the
  group); every plate has its own size and a muted competition colour (25
  red, 20 blue, 15 yellow, 10 green, 5 white, 2.5 red, 1.25 grey; pounds take
  their kilo match; a weight between two plates takes the heavier), an
  accepted exception to muted colours like Measure; "Fits you" is Forge's
  record tag; the exercise list's star stays a button on every row; muscles
  over 20 weekly sets get a 2px danger outline outside the edge; one mark per
  day (workout > cardio > today > missed or planned; today with a finished
  workout keeps its ring); Weekly volume has no Front / Back toggle; the
  measurement camera keeps the preview's aspect ratio, its top line reads
  "Front · match last photo" (first time "Front · first photo") and "1 / 4",
  camera access off offers Open settings and Skip photo, no camera offers
  Skip photo; the program's weekly sets card uses the compact band. Error
  and empty states the boards don't draw keep interim texts until the
  screen step draws them; the plate breakdown's undrawn cases and the
  camera's Close or Skip are drawn and asked there.
- Workout screen (owner's picks, 2026-11-15): the header is Forge
  AppBar's value form (minimize, the elapsed time large, "Push · exercise N
  of M" with N the selected set's exercise, the name alone once every set
  is done), Finish shows its loading state while finishing, with a thin
  indeterminate bar under the header (the owner reversed "no bar"); the
  empty free workout is an untitled EmptyView ("Add exercises to start
  logging.", Add exercises); a card's "Last time" shows the best working
  set (heaviest, then most reps); the progression hint shows when every
  working set last time reached the top of the rep range (weight × reps
  with a range), one weight step up (2.5 kg / 5 lb), and a tap fills every
  working set not done yet, then it goes; the rest panel's line is "next:
  set 4 · 82.5 × 8", the exercise named when it changes, using the panel's
  width; the RIR and RPE question titles are just "RIR" and "RPE"; answer
  rows carry short meanings ("4+ reps left", "last rep missed"), the help
  the long ones; the exercise ⋯ keeps Superset / Circuit with next and
  Ungroup, adds "Rest time · 2:00" (a sheet of 1:00–4:00 for this workout)
  and "Warm-up sets" (adds the scheme's warm-ups or removes the untouched
  ones); a set picked during a rest shows its entry under the rest's thin
  line; once every set is done the panel offers "Finish workout".
- Workout screen, rest of the board (owner's picks, 2026-11-15): swapping
  an exercise with done sets keeps them on it as a finished card and moves
  the sets not done to the new exercise right after it (in a superset or
  circuit the new one takes its place and the finished one leaves the
  group, just before it); the picker's Swap form says "Sets 1 and 2 are
  logged; the rest move to the new exercise."; with nothing done it is a
  plain replace; Swap leaves the ⋯ once every set of the exercise is done.
  The workout note is a plain card titled "Workout note" with Add (empty,
  no body) or Edit (the note as its body), opening the note sheet (the
  three-line field and Save), as the exercise note. The plate breakdown: plates that can't make the weight
  show the target, Bar, Each side and "Closest · 82.5 kg"; below the bar
  Bar and the info card's muted note "Lighter than the 20 kg bar."; at the bar "Each side · No
  plates". The rest-alert question is "Notify when a rest ends?" with "Get
  a notification when a rest is over while GetWorkout is in the
  background." (Allow · Not now). Log set is always on (owner,
  2026-11-18): an empty value is logged as its hint, and one with neither
  is refused with the field ringed and the reason under it. Dialogs' Cancel is the secondary button; every ⋯ menu row has
  an icon (exercise ⋯: Swap sync, Exercise details info, Add note edit,
  Superset / Circuit with next dragHandle, Ungroup remove, Rest time timer,
  Warm-up sets trendingUp, Remove exercise delete; Discard workout delete).
- Workout summary (owner's picks, 2026-11-15): a page of its own with a
  Summary app bar whose back does what Done does; the featured block reads
  "Workout done · Fri, Nov 13", the day's name, "Push Pull Legs · week 3 ·
  vs Fri, Nov 6" and duration, volume, sets and records two by two, the
  first three with their change since the program day's previous finished
  workout (more volume or sets in success, less in danger, duration and
  "=" muted; free workouts and a day's first time show no "vs" and no
  change); records are RecordList rows, one per exercise that beat a
  record (its heaviest working set, the gain over the previous heaviest,
  "+2 reps" / "+5 s" without a weight), counted by the records figure;
  none beaten is one sentence on a plain card ("No new records this time.
  Bench Press was 2.5 kg off your best.", the first workout "Records start
  from this workout."); a program not moved on is a NoticeBanner ("Program
  not updated", the reason, Open Programs); "Worked today" shows small front and back models
  shaded by this workout's sets on Weekly volume's 0–20 scale and up to
  three busiest muscles; the bottom bar has Done and, for a free workout,
  Save as program (a dialog with "Its exercises and sets become a new
  one-day program."; once saved it goes and a snackbar offers View
  program), for a program day only "Save changes to Push" when the workout
  changed the day (an exercise added, removed or swapped, the order, a
  working set count or a rest; not reps or weights), which asks "Update
  Push?" / "Your next Push workouts use these exercises and sets." first,
  then goes, and a snackbar says "Push updated.";
  kept items keep their targets, new ones take them from their sets.
- Add past workout and Edit workout (owner's picks, 2026-11-15): one page.
  The calendar's + first opens a sheet (Date with the system picker up to
  today, Start time on the Forge time wheel, Duration on the Forge wheel in
  hours and minutes, and with an active program "Program day · Fills the
  exercises from the day", None first), then Continue opens the page. The
  page has Save in the app bar, "Date and time" and Duration rows with
  chevrons opening the same pickers, a set table per exercise (values typed
  in boxes, the bubble ticks a set: filled accent ticked, an outline not;
  holding it opens the set type menu; the effort tag opens the effort rows
  in a sheet titled as the workout screen asks it, "How hard was set 1?" or
  RIR / RPE, with the set's values under it), Add exercises, the workout
  note card (as on the workout screen), and Discard (new) or Delete
  workout at the end. While it saves a thin indeterminate bar runs under
  the app bar; a change elsewhere is a NoticeBanner ("Changed elsewhere" /
  "Deleted elsewhere", the sentence, Discard and Reload / Discard).
  There is no name field: a past workout is named after its program day,
  else "Workout"; the day only fills the exercises, the program is left
  alone. Saving with unticked sets asks "1 set isn't ticked. It will be
  left out."
- Today screen step (owner's picks, 2026-11-15): the featured block follows
  the FeaturedCard card (chevron, the whole block opens the program, the
  dumbbell on its line, no divider); a rest day (the next day planned
  later, nothing trained today) shows the rest-day card with "Start <day>
  early" above Start empty workout; trained today with the next day later
  shows a "Done today · <day>" block (working sets and duration, See summary)
  over a "Next: <day>" row opening the program; a program ending before
  another training day shows its next day undated with Start; a missed day
  takes the Programs band form (Missed tag, Do it today, Move, Skip; no
  Start); while a workout runs the block reads "Exercise N of M · K sets
  done" (N the first exercise with a set not done, K every done set) and the
  elapsed time, ticking; no program or finished keeps Generate a program
  (locked without Premium) with See ready-made programs and Start empty
  workout, in the outline card's 20px form with stacked buttons; steps are
  Progress.bar (figure, "to go", bar); a card's error is SectionCard.error;
  no step access is SectionCard.empty "See your steps"; loading is per card
  and Calculators always shows; a rest day keeps the zones and "to go"
  lines; the locked note has no lock icon.
- Programs screen step (owner's picks, 2026-11-15): the band's days are
  ListRow date-box rows (Done with a check, Missed, Next, Planned; today
  ringed); while a day is missed Start is hidden and Do it today / Move /
  Skip sit under its row; the band opens nothing, ⋯ holds Open program,
  Change days, Duplicate (opens the copy) and Stop program, which asks
  first (also on the program page); a finished band reads "n workouts"
  with Run it again (Training days sheet first) and New program (the builder);
  a locked Premium copy keeps its band (lock in the eyebrow, Start opens
  the paywall) with a "Premium has ended" NoticeBanner under it; the
  program lists stay in every state; undrawn states use the components'
  standard forms (EmptyView, SectionCard.loading / error, button loading,
  ForgeSnackbar) and are drawn on the board afterwards. Follow-up picks:
  no programs at all is an EmptyView without a button (the prompt above
  leads to the catalogue); the weekly sets card (with a chevron) opens the
  weekly volume page's model and muscle list for the program, pushed
  above Programs, "<name> · per week" and its total in place of the week
  picker, every muscle listed, no trend, and nothing there opens a muscle
  (the model only turns: "Drag to turn"); loading is LoadingView and the error
  ErrorView with its second line for now; locked rows keep an ink title
  and the Premium tag without a chevron; a locked copy's ⋯ has no Change
  days; the weekly sets card is hidden while the premium status is
  unknown.
- Profile tab (owner's picks, 2026-11-15): the account header names a
  signed-in user (name over email; without a name the email is the name,
  no second line; no workout count), a guest "Guest" / "Create an account
  to keep your workouts"; Premium is a FeaturedCard prompt (free: the pitch
  and Get Premium; otherwise the state as the title, muted while checking,
  danger on a payment problem, the pitch under it and one secondary Manage
  subscription; dates "Nov 20", the year only when not this one); the
  groups are More, Units, Workout, Reminders, Connected apps, Appearance,
  Privacy; choices open choice sheets; with the rest timer off its rows
  hide; new: Rest sound and vibration, Keep screen on (on by default),
  Bar and plates (its own page, which the Plates calculator links to),
  Connected apps (the health store, "Steps and cardio in", On / Off); the reminder
  time is Forge's wheel, saved as it turns; the permission dialogs carry
  titles ("Allow notifications?", "Notifications are off") and the rest
  notification asks as the reminders do; "Notifications are off" leads
  Reminders whenever the device refuses, its button "Allow notifications"
  (asks) on a device never asked, else "Open settings"; the rest sound is
  a bundled chime played in the app with audioplayers, the background
  rest notification uses it or is silent.
- Exercises tab and shell (owner's picks, 2026-11-15): the tab's search
  pill is Forge SearchField's tap-only form and opens the Exercise list
  page as before (search, filters, sort and + live there; the board's
  search and no-results states belong to that page); the model shows "Tap
  or slide across a muscle" at its bottom while nothing slides, the
  muscle bar while sliding; a model that cannot load shows "Couldn't load
  the body model", "Search still works." and Retry (Weekly volume: "Try
  again."); the pill always shows "Search exercises"; a search matching
  nothing (no filter on) shows the search text, "Check the spelling or add
  it as your own exercise." and Create custom exercise, which opens the
  form with the name filled in; with a filter on, "No exercises match",
  "Clear a filter or turn off Only my equipment.", Clear all and, with
  search text, Create custom exercise too; exercise rows keep the star
  button and the chevron; tab labels stop growing at 1.5x text (Forge
  v0.20); the tabs are Forge NavigationBar with the workout bar above it,
  and the shell's notices are Forge snackbars (4 s, "Open" on a restored
  workout).
- Progress screen step (owner's picks, 2026-11-15): Body is the featured
  band (the latest weight as its title, the change since the previous
  weigh-in as its line, "−0.4 since Nov 8", with the newest body fat at
  its end, the app's own bare line, Log weight and Measurement day); the
  whole band opens Body; a single weigh-in has no trend at all until the
  second (K16 B); a failed body list keeps the band's eyebrow, the error
  with Retry on one line and both buttons; the measurement-day prompt
  (TipBanner) shows under Body while the measurement reminder is on, from
  two days before its next date through that day, until a measurement
  day is saved in that time; swiping it away hides it until the next date
  (kept on the device); a card's error is SectionCard.error and no step
  access SectionCard.empty "See your steps", as on Today; a drop in
  strength is written in danger, a gain in success.
- Exercise pages (owner's picks, 2026-11-15): the Exercise list keeps the
  title "Exercises" and shows a model-chosen muscle as a removable chip
  with Clear all, "Main · 42 | Also works · 18" as a segmented control
  under it and the count with the sort under that; the count ("9
  exercises") and the sort ("Most popular ▾", a menu with the current
  sort ticked) share one line; active filters are removable chips that
  wrap, with Clear all under them; the filter button carries their count;
  the page opens from the pill on an empty search, filters and sort kept;
  rows sit in one card; loading is shimmering rows and an error ErrorView
  in a card, both under the search. Exercise detail: the model's pair form
  (Worked muscles, Front / Back, Main / Secondary) for every exercise,
  each figure filling its half of the card, the body very light and the
  main muscles heat-high and secondary muscle-secondary (Egzersiz · 7
  X2 A, superseding K4 A's accent tones);
  facts as plain rows (label left, value right), equipment alternatives
  as extra lines and Also called last; a custom exercise shows its Custom
  tag with "Logged as …" under the model and only Equipment as a fact;
  Setup and How to do it as numbered circles; Common mistakes, Safety and
  Cues as bulleted lines in plain cards; a catalogue exercise has a "Your
  note" card (only its title and Add while empty; the note with Edit
  once written; a sheet with Save);
  a "Similar exercises" SectionCard (total count and chevron) previews
  Variations · N and Alternatives · N, up to three names each, and opens
  a sheet listing every one by group, a row closing it and opening that
  exercise; the app bar's star is an ink-muted outline that fills accent
  when a favourite, a custom exercise has ⋯ (Edit, Delete after a dialog),
  and the bottom bar stacks Add to workout over Add to program; the program and day
  sheets are list rows, a full day shown off ("Lower A · Full") and not
  tappable, the day sheet titled "Add to which day of Upper Lower?"; no
  programs asks "No programs yet" first; not found is one untitled line.
  Exercise picker: "Add exercises" with close, the count bar ("None
  chosen", "3 chosen", at the limit "2 chosen · 40 is the most" with the
  other rows greyed and not tappable) and "Add 3 exercises"; the
  generator's is "Leave out exercises" / "Leave out 3 exercises"; no
  match offers Create custom exercise ("…it is added here once saved"),
  which comes back chosen (single choice: picked at once), and with a
  filter on the list's filter form; Swap ("Swap Bench Press", back) and
  Replace ("Replace Bench Press", or "Replace exercise" for one no longer
  in the library) list up to eight similar exercises first under
  "Similar" (narrowed by the search and filters, hidden when none match)
  and the rest under "All exercises", no count or sort; a tap picks; Swap
  notes the logged sets ("Set 1 is logged; …", "Sets 1 and 2 are logged;
  the rest move to the new exercise.", "Sets 1–3 are logged; …"; none
  while nothing is logged; logged warm-ups are named apart, "2 warm-ups
  and set 1 are logged; …", "1 warm-up is logged; …", K1 2026-11-15). Menus carry an icon per
  item: sort Most popular (trending up) / A–Z (list); Add to workout
  (dumbbell) / Add to program (plus); Edit (edit) / Delete (delete).
- Program detail (owner's picks, 2026-11-15): the FeaturedCard band at the
  card's size: "Active · week 3 of 8 · Mon, Wed, Fri" over "Next: Push"
  with a muted "Today" ("Mon, Nov 16" later) under it (K2), the week's progress, Start
  <day>, then Change days and Stop (danger) side by side; not active
  "8 weeks · 3 days" / "Not active" with Start program (Replace your
  active program? first when another runs, then the Training days sheet);
  finished "… · Mon, Wed, Fri" / "Finished" with Run it again (Training
  days sheet) and New program, no Stop; a missed day takes the Today missed
  form (You missed Legs on Wed, Nov 11, Missed, Do it today, Move to
  Monday and Skip, no Start; the progress bar stays) with Change days and
  Stop under it; the days
  mismatch is a danger line over the progress; a locked Premium copy
  keeps the lock in the eyebrow and Start in place (it opens the
  paywall), its note without an icon, no Change days, Stop kept; the
  weekly sets card shows (also on a locked copy, hidden while the premium
  status is unknown); then "Days": each day a card "Day 1 · Push" /
  "6 exercises · ~55 min" that opens and closes (chevron down / up; the
  next day open while active), its exercises "4 × 6–8 · Rest 2:00", not
  tappable; a superset or circuit gets a muted "Superset A · rest after
  each round 1:30" over it and its exercises lose their own rest; ▶ on
  each day row, in front of the chevron, starts that day (a locked copy
  opens the paywall); ⋯ Edit,
  Duplicate, Delete (each with an icon); dialogs are ForgeDialogs; days
  are picked on the Training days sheet (SD2 E); load
  error is ErrorView with its second line, not found an untitled
  EmptyView.
- Ready-made program (owner's picks, 2026-11-15): no app-bar title; the
  name at 24px, Fits you (Forge record tag; the program is for the
  user's goal, level and days per week) or the Premium tag and the goal
  tag, the summary; standard ListRows Days "3 a week", Level, Length
  ("8 weeks · 45–60 min", "~55 min" when every day is as long), Goal,
  Equipment (the setup); the weekly sets card (opens the program's
  weekly sets page); "Days" whose cards open in place ("6 exercises",
  exercise rows with a chevron open the exercise); a locked Premium
  program lists its days' names and exercise counts from the card,
  opening nothing, and no weekly sets; Start this program in the bottom
  bar (Get Premium to start when locked): the user's copy is offered
  first (Open my copy / Add another copy), then Replace your active
  program?, then the Training days sheet; only once the days are picked is
  the copy made and started, then its page opens; cancelling leaves the
  page unchanged; a copy that cannot be started stays, not started, with
  "Added, but couldn't start the program. Try again."; ⋯ Duplicate copies it and opens the builder on the
  copy, hidden for a locked program; unlocking is Forge NoticeBanner
  ("Unlocking this program" / "Premium is active. This takes a
  moment." / Retry); a program with an exercise no longer available has
  Start disabled and the muted reason at the end of the page; offline
  "You're offline. Connect once to load the ready-made programs." and
  errors are ErrorView with the second line, not found an untitled
  EmptyView.
- Ready-made programs (owner's picks, 2026-11-15): a search by the name in
  the app language, live and ANDed with the filters, cleared when the
  page is left; the filters as one sideways line of chips (Only my
  equipment, Level, Days per week, Goal, Equipment; unset ones the name
  with ▾, chosen values removable ×), each opening the sheet; while
  filtering "3 filters on" and Clear; otherwise the best match as one
  recommended row with "Matches your goal and level" in success, then
  "12 programs · 6 free" ("12 programs" with Premium); programs as
  ProgramCard rows with Fits you or the Premium tag (locked rows: no
  chevron); no results: "No programs match" with "Try another name." and
  Clear search while searching, "Remove a filter to see more programs."
  and Clear filters while filtering; the filter sheet is a
  ForgeBottomSheet (a switch row, chip groups, Clear, Done).
- Generator questions (owner's picks, 2026-11-15; the goal question is
  onboarding's since CK2, 2026-11-17): full screen above the
  tabs (pushed; Back on the first question returns); the OnboardingQuestion
  page with the mono "n / 9" counter after the progress (onboarding too)
  and "Generate a program" over each question; Continue, "Create my
  program" on the last; the equipment answer is the OnboardingQuestion
  question's (one radio row per set; see Onboarding, L3); focus muscles
  as chips under "Focus muscles (2 of 3)"; left-out exercises as rows with
  × and a secondary "Add exercises to leave out".
- Program builder (owner's picks, 2026-11-15): the name, then "Length in
  weeks (optional)" with "Leave empty to run until you stop it" under it;
  the day chips (selected: accent fill and border, no check, a ⋯ at its
  end; a day with a problem carries a danger alert icon) and "+ Day", which
  adds the day and opens the Rename dialog ("Rename day", "Shown on the
  day's chip and in your workouts.", field "Day name" with hint "Day n",
  Save · Cancel); the ⋯, a second tap on the selected chip or a long press
  opens the day menu: Rename day, Duplicate day (the copy follows and is
  selected, a named day's copy is "Push copy"), Move earlier, Move later, Delete day, each with an icon, the
  ones that cannot apply hidden; deleting a day with exercises asks
  ("Delete this day and its exercises?", "Its 5 exercises are removed
  too.", one: "Its exercise is removed too."); cancelling the Rename
  dialog after "+ Day" keeps "Day n". Under the chips "Push · 6 exercises · ~55 min"; the rows in one
  card follow the BuilderRow card (two-line handle, no Weight chip, a
  circuit's items only Reps or Time with the accent rule and "rest after
  each round"); an unavailable item is the row's unavailable form with ⋯
  (Replace exercise, Remove). An empty day is an EmptyView in a card ("No
  exercises on this day"), after a failed save the danger line instead;
  Add exercises stays, disabled, with "A day holds up to 20 exercises."
  under it once full. The sets-and-reps sheet is titled with the exercise; Rest is a
  tap-only field opening the minutes:seconds wheel (0:00–10:00, 15 s steps). Leaving with changes:
  "Your edits to <name> will be lost." ("…this program…" unnamed), Discard
  in danger. Not found is the untitled EmptyView, a load failure ErrorView
  with both lines; loading is a skeleton of the page; every menu item has
  an icon (a row's: tune, sync, the two-line handle for Superset / Circuit
  with next, remove for Ungroup, delete); the Rename field takes the focus.
- Calendar (owner's picks, 2026-11-16): a PeriodSelector over Forge
  MonthGrid, the month always open and months ahead browsable (planned
  days); tapping the month opens the system date picker. The card has the
  count line ("4 workouts · 4 cardio · 1 missed", zero parts left out, no
  line for a month with nothing) and
  the legend (Workout, Cardio, Planned, Missed, Today); a load failure is
  MonthGrid's error form. The list follows the month shown: the current
  month "This week · Nov 9–15" (today first, then the coming planned
  days in date order, then this week's past days newest first) then
  "Earlier this month", another month
  its weeks within it as sections, newest first; days and weeks with
  nothing are left out; no "Show older workouts". All / Workouts / Cardio
  chips filter the list, the marks and the count (Workouts keeps the
  program's planned and missed days); hidden while the month has nothing
  logged. Rows are ListRows with their own date box, today's in the "today"
  form: a workout "48 min · 9,800 kg" (no volume: "48 min · 12 sets"),
  cardio "Cardio · 18.4 km" (no distance: "Cardio · 45 min"; one from the
  health store with its source tag), a planned day
  "Planned · 6 exercises" with Start, a missed one "Missed" in danger with
  Do it today. Holding the program's next day (planned or missed) opens the
  Move sheet: "Move Push", "Planned for <date>. Pick a new day this week.",
  day chips from today to the week's last day, nothing picked and Move off
  until a day is picked ("Move to Saturday"). A locked Premium copy's Start
  is locked (paywall) and its missed day has no Do it today and no Move.
  Tapping a date rings it and scrolls its rows up; a date with no rows in
  the list shows on top under its date with "Nothing on this day" or its
  rows. A month with nothing logged: "Nothing logged in November" /
  "Finished workouts and cardio show here." / Add past workout, under this
  week's planned days; a chip with nothing: "No workouts in November" /
  "Finished workouts show here." / Add past workout, or "No cardio in
  November" / "Log a run, ride or swim." / Log cardio. + in the app bar is
  the Forge icon action (ink).
- Workout detail (owner's picks, 2026-11-16): "Workout" app bar with ⋯
  (Edit, Delete workout in danger, each with its icon; off while waiting
  to sync). A FeaturedCard band: the start ("Fri, Nov 13 · 18:05"), the
  name, the program as an underlined link with the week of the active
  copy's run ("Push Pull Legs · week 3"; another run or copy: the name
  alone; "From a program you deleted"; a free workout: no line), and
  duration, volume ("—" without), sets and records in one row. Records are
  the ones the workout still holds (each exercise's stats read once): the
  figure counts the sets tagged "record". Waiting to sync is a NoticeBanner
  (danger icon, "Waiting to sync", its line, no button); the note a plain
  card "Note"; each exercise a SetTable with its set count that opens and
  closes on its header, the first open. Deleting runs a thin bar under the
  app bar.
- Cardio (owner's picks, 2026-11-16): This week as a FeaturedCard band
  ("23.6 km · 74 min", without distance "74 min", "2 sessions"), the
  12-week minutes as Forge Chart.bar (small "Nov 9" labels on every other
  week, this one labelled; minutes over the bars, none over a week
  without minutes),
  sessions under "This week" and date-range labels ("Nov 2–8") as ListRows
  ("Outdoor run · 5.2 km", "Tue, Nov 10 · 29 min"; without distance the
  type alone), Log cardio in the bottom bar. No session: the band "0 km ·
  0 min" / "No sessions yet", then "No cardio logged" in a card. Sessions
  from Apple Health or Health Connect show with the store's source tag. A
  session opens its page: the type, its start, distance / time / "per km"
  (or "km/h") tiles (without distance the time alone), rows only for the
  values it has (Calories, Average heart rate, Incline, Note), Edit in the
  app bar and Delete (danger) at the end asking "Delete this session?"; a
  health store session has neither and says "From Apple Health. Change it
  there." under its tag.
- Steps (owner's picks, 2026-11-16): Forge Progress.ring (136px) with "of
  10,000" and "3,760 to go" / "Goal reached" under it, the goal as a Forge
  StepperField ("daily goal", 100 steps, typed in place, the range under it
  when out of range), the zero hint as a NoticeBanner ("No steps showing?",
  Open Settings), This week / Last 30 days as a segmented control over the
  chart (the week as Forge Chart.bar with "goal 10,000", the 30 days as
  Forge Chart.barDense; holding a bar of either names it, "5,739 steps ·
  Mon, Nov 3", K17), then "Daily average" and
  "Goal reached · n of m days" rows on both views. Access is Forge
  PermissionPrompt: ask ("See your steps here", "GetWorkout reads steps and
  cardio from Apple Health. Nothing else is read.", Allow access, which
  asks for steps and then workouts, on iOS the note
  "Turned it off before? Open Settings, then Health."), refused ("Access is
  off", Open Health Connect, Ask again), missing ("Health Connect is
  needed", Get Health Connect, Not now), failed ("Couldn't reach Apple
  Health" / "Something went wrong. Try again in a moment." / Retry); no
  store is the untitled one line; a load failure "Couldn't read your
  steps" / "Try again in a moment." / Retry; loading is skeletons.
- Body overview (owner's picks, 2026-11-16): the app bar says "Body"; the
  Overview / Compare switch stays in every state; three boxes (Weight,
  Body fat, Lean mass; lean mass is the latest weight at the newest body
  fat) with the change since the measurement day before the newest one
  (weight: the latest weigh-in against that day's weight), the weight
  green toward the target weight and red away (ink without one), body
  fat down and lean mass up green; without body fat its two boxes show
  "—"; the chart is Forge MultiSeriesChart titled with the range, detail
  "target 78 kg" while the target line shows, weight as its daily line
  under the rolling 7-day average ("daily weight · 7-day average"), the
  target line in weight's colour labelled "Target"; a series chip opens
  "Add to chart" (Forge sheet, checkbox rows; at three picked the others
  dim and take no taps, the last one stays); the range control shows
  only with entries older than 2 weeks, a free user then sees locked
  ranges and the caption "See your older results with Premium" (opens
  the paywall); chart empty, series error and loading are Forge's forms;
  Log weight and Measurement day side by side; History rows: weight
  ("—" without one), the date (" · measurement day"), body fat or "—",
  a chevron, opening the entry; no entries: the empty view in a card
  and both buttons under it, on Compare too; a failure is the error
  view in a card. Without a target weight the weight change is neutral
  (ink-muted); a left/right pair's chart values show both sides ("36 /
  35.5 cm"); an empty range is the chart's empty form "Nothing in this
  range" / "Nothing to show in this range yet." with the range control
  and locked caption kept in the card.
- Body compare and Measurement summary (owner's picks, 2026-11-16):
  photos on Forge BeforeAfterSlider (pose name and "Oct 18 → Nov 1 ·
  −1.2 kg", without a weight change "Oct 18 → Nov 1"; chips Front / Right / Left / Back for the poses either day
  has, fading; a pose only one day has, or one day alone, shows that
  photo in the single form; one still fetched shimmers, one the backup
  lacks "Photo not on this device"); no photos on either day: a card "No progress photos
  on these days" and a muted mono "Oct 18 → Nov 1" under the
  Previous / First / Other date control; Other date (also when chosen)
  and, on Compare, the later date (accent in the photo card's line;
  without photos a small text button "Later day" at the end of the mono
  line, Egzersiz · 7 X6 B) open sheets "Compare with" / "Later
  day" listing the days with the current one ticked; change boxes
  (change large, "84.1 → 82.9 kg" under it, "—" for a side not
  measured): Weight, Body fat, Lean mass, Fat mass, then the
  measurements in the app's order, a pair as one box per side "Upper arm
  (L)"; one measurement day: a card with its date and "No earlier
  measurement day to compare with yet.", "Values" boxes, the photo; no
  body fat: NoticeBanner "No body fat yet" with the reason (the profile
  one with "Your profile"); the target is FeaturedCard's target form
  ("Target 78 kg" over "At this pace, around Dec 28." / "4.9 kg to go." /
  "Reached."); weigh-ins but no measurement day: "No measurement days
  yet" with Measurement day; a linked day that is gone: "This entry no
  longer exists."; dates without the year unless another year (the
  summary's head "Oct 18 → Nov 1, 2026" and the sheets' rows keep it).
  The summary heads with the dates and "Measurement day saved", photos
  last under "Photos", the back chevron its only exit; it opens after a
  new measurement day is saved (the Measurement day board's "Kaydedildi"
  state goes).
- Weekly volume (owner's picks, 2026-11-16): the week picker is Forge
  PeriodSelector ("Nov 9–15" for every week, the week label opens the
  system date picker up to today and shows the picked day's week); one card
  holds the model, "Drag to turn · pinch to zoom" with the turn icon and the
  8px 0 / 10 / 20 sets ramp (no outline sentence); "Sets per muscle" with
  "96 total" lists every muscle, those without sets last at "0 sets", over
  "target 10–20 per muscle · tap a muscle on the model or a bar to see its
  exercises"; the "12-week trend" card is Forge Chart.line of each week's
  total for Premium (this week's total as its detail, the first and last
  week under its ends, a tap "14 sets · Nov 9–15") and SectionCard.locked (Premium tag, chevron,
  paywall) for everyone else and while Premium is unknown. A week without
  sets is an EmptyView "No sets this week" / "No sets that week", "Weekly
  sets per muscle fill in as you train.", with the trend card under it. A
  muscle's sheet: its sets and band under the title ("14 sets · 10–20
  sets"), "Where the sets came from" ("Push · Nov 13"), a muscle without
  sets "No sets for this muscle this week."; its trend is Forge Chart.bar
  without a card, the 10–20 band behind the bars, the bars in the band
  colours (below the band 40% accent), titled "Last 12 weeks" ("12 weeks to
  Nov 15" for an earlier week), shimmering 110px while it loads. The
  program's weekly sets page: "Drag to turn" and "target 10–20 per muscle".
- Strength (owner's picks, 2026-11-16): the title is "Strength"; an
  "Exercise" row opens the Exercise sheet (search and the Strength list's
  rows as Forge ChoiceGrid radio rows, M1 B: "Last done Nov 13" under
  each name, this one selected, a removed exercise a normal row, its
  height following the rows; another exercise replaces the page, so Back still
  returns to the list); a removed exercise's row reads "Exercise no longer
  in your library". Ranges are Forge SegmentedControl (locked segments open
  the paywall); the chart is Forge Chart.line "Estimated 1RM", one dot per
  workout evenly spaced, the range's first day to the last session as its
  detail ("Aug 24 – Nov 13"), the first and last dates under its ends, a tap
  "104 kg · Nov 13"; no e1RM in the range is Chart.empty "No estimated 1RM
  in these 12 weeks" ("…6 months", "…the last year") / "Log a set of
  Bench Press to continue the line." with the range's first day to today
  as its detail;
  loading is Chart.loading. Records are all five, Best e1RM, Heaviest, Most
  reps, Best set volume, Longest time ("Best e1RM" and "Heaviest" in the
  workout summary too), each with its date ("Fri, Nov 13") and the set that
  made it ("82.5 kg × 8"; e1RM and set volume alone) in the data font,
  not tappable; session lines are in the data font too.
  Sessions are every workout in the range (all of them for an exercise
  without an e1RM), newest first: the best set as the strength page writes
  it ("82.5 × 8", "12 reps", "+10 kg × 8", "20 kg assist × 8", "1:45",
  "20 kg · 1:30") with "· e1RM 104" where there is one, "Fri, Nov 13 ·
  Push" under it, opening the workout. Dates carry the year only when it is
  not this one.
- Strength list (owner's picks, 2026-11-16): Forge SearchField and
  ListRows ("Last done Nov 13", "Last done Sep 3, 2025"); nothing yet and
  no match are untitled EmptyViews ("Finish a workout to see your records
  and progress here.", "No exercises match your search."); loading is six
  ListRow.loading rows.
- Sample dates follow November 2026 (Nov 13 is a Friday; Push is done that
  day).
- Training days (owner's picks, 2026-11-19, canvas
  https://claude.ai/artifact/PbEWe754pHbYU5EJ2yrzsJ, SD2 E; SD1 A, a
  Rest / A / B segmented row per weekday, and SD1 B, weekday chips over a
  day menu per weekday, were dropped): Start program, Run it again,
  Change days and Start this program open a "Training days" bottom sheet:
  "Tap the weekdays each day is done on; a weekday holds one day."; one
  card per program day titled with its full name (wrapping when long)
  over seven two-letter weekday chips in the user's week order, the
  picked ones being the weekdays that day is done on; picking a weekday
  another day holds moves it to this day; under the cards "5 days a week
  · Wed and Sun rest" ("7 days a week" with no rest day, nothing while
  none is picked); Cancel and Save (Start program when starting) side by
  side, Save off while no weekday is picked. Starting suggests one
  weekday per day spread over the week, the days in turn. The sheet
  scrolls when its cards do not fit (large text).
- Training days, Simple and Custom (owner's picks, 2026-11-20, canvas
  https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ, SD3 B, SD4 C, SD5):
  a "Simple | Custom" segmented control tops the sheet, above its
  scrolling part so it stays in view. Custom is the SD2 E sheet above.
  Simple: "Pick the N weekdays you train on." ("Pick the weekday you
  train on." for one day), one row of seven weekday chips and the same
  summary line; no per-day list. Exactly as many weekdays as the
  program has days: Save is on only at that count; at it, an unpicked
  weekday does nothing (it stays enabled, so nothing greys out), a
  picked one turns off. The days go onto the picked weekdays in the
  user's week order, the first day on the earliest
  (`ProgramSchedule.inWeekOrder`). The sheet opens Simple when the
  schedule is exactly that (`isInWeekOrder`) or empty, else Custom; the
  suggestion when starting is in order, so starting opens Simple
  (except a 7-day program in a Sunday-first week, whose ISO-ordered
  suggestion opens Custom). Simple to Custom carries the picks over in
  week order (too few picks leave the last days on no weekday); but if
  nothing was picked since Simple opened, Custom comes back as it was,
  so a look at Simple loses nothing. Custom to Simple keeps the
  weekdays when each day is on exactly one (`hasEachDayOnce`, then put
  in week order on Save), else starts with none picked.
- Update and maintenance (owner's picks, 2026-11-20, canvas
  https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ, U1–U3): U1 a full
  "Update required" page with one Update button and no what's-new list;
  U2 a bottom sheet, not a banner, with Update and Later; U3 a full
  "We'll be right back" page with the configured message and Try again.
  Behaviour and texts are under Feature notes › App shell, settings and
  onboarding › Update and maintenance gate.

- Release readiness (2026-11-20, canvas
  https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ): U1 A (update required:
  one-button page), U2 B (update offer: a sheet once at start), U3 A
  (maintenance with Try again), V1 A' (verify email: no "I've verified",
  detects it by itself), V2 A (wrong address: change it on the same
  account), S1 A (Help & feedback under Profile › More), S2 B (message and
  email only), R1 B (the review question as a dialog over the summary),
  R2 B' (the same dialog thanks and offers "Write to us"), review timing
  (after the 2nd workout or on the 3rd distinct day of use, then records 30
  days apart), W1 A (RevenueCat Customer Center with a 1-month-free offer at
  cancel), W2 A (win-back tag on the plan cards), D1 A (in dark mode the body
  model is halfway between surface and ink). Explicit consent for body data
  was dropped by the owner.

- Days per week recommendation (2026-11-20, canvas
  https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ): DW1 C (an info line
  under the question and a Recommended tag on the row), DW2 A (nothing
  preselected), DW3 A (beginner 3, intermediate 4, advanced 5 days).
## Open questions

- Google sign-in is offered next to email (`socialProviders` in
  `lib/app/router.dart`); both providers are enabled in both Firebase
  projects. It runs through Firebase Auth's browser flow, so iOS returns
  through the encoded Firebase app id URL schemes in `Info.plist` (dev and
  prod) and Android needs the signing certificate's SHA registered on the
  Firebase Android app: the debug keystore's SHA-1 and SHA-256 are
  registered on dev. Still open: the release (Play app signing) SHA on
  prod once the Play Console exists, and a completed sign-in on a device
  (the emulator check stopped at the browser opening).
- Sign in with Apple is offered first on iOS (2026-11-17, the owner's paid
  Apple Developer team A8J42TV74R, which now signs the app; the Sign in
  with Apple entitlement is in Runner.entitlements). Android offers Google
  alone: Apple there would need a Services ID. Checked on the owner's
  iPhone the same day: a guest linked with Apple and kept their data.
- A guest who signs in to an existing account leaves an orphaned anonymous user and its data behind; clean these up with a scheduled function when Cloud Functions arrive.
- Photo backup: the default bucket and `storage.rules` are live in both
  projects (since 2026-11-12). On the owner's iPhone (2026-11-18) a
  measurement day's four photos uploaded to the dev bucket. `deleteAccount`
  already deletes `users/{uid}/` in the bucket; the orphaned-guest cleanup
  must do the same.
- Body feature, not yet run on a device: the camera permission prompt and
  denial text, the ghost's alignment (front-camera previews are mirrored,
  saved photos are not; `mirrorGhost` in `forge_camera`), retake,
  background upload and restore against the dev bucket, the iOS backup
  exclusion channel. Android manifest drops the camera plugin's
  RECORD_AUDIO and WRITE_EXTERNAL_STORAGE and makes the camera optional
  (`tools:replace`); with the new backup rules, not built yet.
- `third_party/camera_avfoundation` (patched 0.11.1, see Camera
  orientation): not yet checked on a device. Drop the copy and its
  `dependency_overrides` entry once a `camera_avfoundation` release fixes
  flutter/flutter#196204, after checking the iPhone 17 front camera with
  it. Until then do not bump `camera` past what 0.11.1 satisfies without
  re-copying the new release and re-applying the `PATCH` lines.
- The projects are on the Blaze plan. `deleteAccount` is live on dev
  and, since 2026-11-18, on prod (with `revenueCatWebhook` since 2026-11-19; artifact cleanup policy
  set). On the owner's iPhone (2026-11-18) a Google-only user whose
  sign-in was older than the function allows got the password prompt and
  then "Please sign in again", with no way to do so from the page. Fixed
  in #145 (provider re-sign-in, Forge v0.26.0) and checked the same day:
  the Auth user, `users/{uid}` and the bucket's `users/{uid}/` were gone.
- Female body model with the same mesh names: the user supplies it before release. The 4-view drawings both new models (male and female) were generated from in Tripo 3D are in `design/body_models/{male,female}/{front,right,back,left}.png` (2026-11-20).
- Subscriptions (2026-11-20). App Store: group "GetWorkout Premium" with
  `getworkout.premium.monthly` (7.99 USD) and `getworkout.premium.yearly`
  (39.99 USD, 7-day free trial), 175 territories, equalized prices; the
  Paid Apps agreement is active. The App Store review screenshot on both is
  a placeholder (an old Profile screen): replace it with the paywall before
  submission. RevenueCat: iOS app with the In-App Purchase key, entitlement
  `premium`, offering `default` ($rc_monthly, $rc_annual, metadata
  `dismissible: true`). Webhooks: sandbox → dev, production → prod, each
  with its own REVENUECAT_WEBHOOK_AUTHORIZATION; both deployed and answer
  401 without the header. Device builds use the real store only with
  `--dart-define=REVENUECAT_IOS_KEY=...`. On the owner's iPhone both plans
  load. Not done yet: a completed sandbox purchase (the sandbox tester's
  sign-in loops after the verification code), then `entitlements/<uid>` on
  dev, Premium unlocking, the trial, restore, renewal and EXPIRATION. Until
  then the Subscription feature stays unticked. Android / Play is not set
  up (products, service account in RevenueCat, license testers, the
  merged manifest's BILLING permission).
  Win-back (W1, W2, 2026-11-20): promotional offers "1 month free" (free,
  one month) exist on both plans for the Customer Center's cancel path:
  `retention_1m_free` (monthly) and `retention_1m_free_yearly` (yearly;
  offer codes are unique per app). The win-back offers cannot be created
  until the subscriptions are approved (App Store Connect refuses with
  STATE_ERROR.NON_APPROVED_SUBSCRIPTION); after the first approval create
  one per plan: 1 month free, eligibility paid at least 1 month and
  lapsed 1 to 12 months, no wait between offers, priority high, not
  promoted on the App Store. RevenueCat (dashboard only): enable Customer
  Center (Pro plan, free below 2.5k USD monthly revenue), set its accent
  to the app's, and map both products to their promotional offer on the
  Cancel path.
- The first Android build after the rest timer needs Android platform 37
  (compileSdk, for flutter_local_notifications 23) and AGP 9.1.1
  downloaded; the disk is nearly full, so free space first. CI does not
  build Android, so nothing has compiled the Android changes yet.
- Lock-screen rest, not built yet: the `RestTimer` widget extension
  target (hand-added to `project.pbxproj`; bundle id
  `com.getworkout.app.RestTimer`, iOS 16.2, embedded before Thin Binary),
  `NSSupportsLiveActivities`, ActivityKit weak-linked in the Runner, and
  `POST_PROMOTED_NOTIFICATIONS` on Android. Shows on the owner's iPhone
  since 2026-11-18. It did not at first: the extension still carried a
  7-day profile from the free team, so iOS refused to launch it (amfid
  "not valid", seen only in the device log) and ended each activity at
  once; an `xcodebuild -allowProvisioningUpdates` build after deleting that
  profile fetched a paid-team one. Signing problems of the extension show
  only in the device log (`sudo log collect --device-udid …`).
- Workout on the lock screen (iOS), not built yet: the two widget files
  were renamed (`WorkoutActivityAttributes.swift`,
  `WorkoutLiveActivity.swift`, same entries in `project.pbxproj`), and the
  Swift was only type-checked with `swiftc` against the simulator SDK and
  Flutter.framework. Check on the simulator: it starts with the first
  exercise (not for an empty workout) and ends on finish and discard; the
  elapsed time runs on the lock screen and in the Dynamic Island; a rest
  shows its countdown and turns back into the workout at its end with the
  app in the background (the stale-date redraw) and in front, on skip and
  on +15 s; relaunching with a workout in progress keeps one activity
  (none duplicated) and without one removes the old; a tap in each
  presentation and mode opens the workout page, also from its minimized
  bar, from another tab with unsaved changes (no prompt: it is pushed),
  and from a killed app (the launch URL reaches `WorkoutActivityTaps`
  through the late-registered scene delegate); with no workout in
  progress a tap only opens the app, and with the workout page open (also
  under the exercise picker or the paywall) it stays as it is; Google
  sign-in still returns to the app; the clocks fit at 1:00:00 in every
  presentation without squeezing the labels. Since LA1–LA4 (2026-11-19;
  both targets compiled with `xcodebuild` for the simulator, nothing run):
  the set card with its dots (also 6+ sets, a warm-up, a drop set, no
  values yet, every set done), the rest card's bar emptying and the
  compact island's ring; −15 s, +15 s and Skip on iOS 17+ with the app in
  front, in the background and killed (the activity moves at once; the app
  shows the same rest when opened, and the rest notification follows when
  it ran), none below iOS 17; a tap beside the buttons still opens the
  workout; a Live Activity started by the build before stays undrawable
  until the app updates it (its content state changed); "All sets done"
  with "Finish in the app" once the last set is ticked (LA5).
- `ForgeGrabber` is on Forge branch `feat/forge-grabber` (PR #75, not
  merged or tagged); `feat/live-activity` uses it through a local
  `pubspec_overrides.yaml` only. Merge and tag it, then move every forge
  `ref` (app and `widgetbook/`) to the tag before this app's PR. An activity started by an older build (`RestActivityAttributes`)
  is no longer seen by the app and stays until iOS ends it; only matters
  for a device that had one running across the update.
- Workout on the lock screen (Android), not built yet; it needs
  `forge_notifications`' `showStopwatch` / `scheduleStopwatch` (forge
  branch `feat/ongoing-stopwatch-notification`, to be tagged and pinned).
  Check on the emulator: the notification appears with the first exercise
  and counts up from the start; a rest replaces it with the countdown and
  the next set, and the workout comes back at the end with the app in
  front, in the background and killed (with and without exact alarms
  allowed), and at once on skip; +15 s moves both; finish, discard and
  sign-out remove it and nothing comes back later; relaunching with a
  workout in progress shows it once (no duplicate) and without one
  removes it; it makes no sound, cannot be swiped away on the lock
  screen, and is promoted to a status bar chip on Android 16; a tap in
  both modes opens the workout page (also from a killed app), and with
  no workout in progress only opens the app; the channel shows as
  "Workout in progress" in the system settings (renamed from "Rest
  timer").
- Legal pages (2026-11-20): `legal/privacy.html` and `legal/terms.html`
  are live at https://getworkout-prod.web.app/privacy and `/terms`
  (hosting target `legal` on prod; deploy with `firebase deploy --only
  hosting:legal --project getworkout-prod`; the admin panel is target
  `admin`, dev only). Contact getworkout.support@gmail.com, minimum age 13
  (or the local age of digital consent), the Terms are the iOS custom EULA,
  Turkish law and Istanbul courts. Not reviewed by a lawyer. Still open
  before release: the App Store / Play privacy labels must say that the app
  contacts Firebase Remote Config with a Firebase installation ID for all
  users, declare Usage Data (Product Interaction) and Diagnostics (Crash
  Data) as collected by default (an opt-out, not opt-in), linked to the
  user (the uid is the Analytics user id), for Analytics and App
  Functionality, not tracking (Play Data safety: App activity and App info
  and performance › Crash logs, collected and linked to the user), and
  declare Advertising Data for the Apple Search Ads
  attribution (Subscription and paywall › Hard paywall for paid traffic); App Store Connect's Privacy Policy URL and custom EULA; KVKK
  (VERBİS, notifying transfer contracts) and the explicit-consent basis for
  body data, which the policy claims without an in-app consent step.
- Release blockers for steps: Health Connect's privacy-policy link opens
  `PrivacyPolicyActivity`, which opens `LegalLinks.privacyUrl` (passed in
  by the build, now the live page); Play Console
  needs the Health apps declaration for READ_STEPS; the App ID needs the
  HealthKit capability (the Runner now carries the entitlement, so a
  device build signed by a team without it fails; the simulator does
  not). The Android changes (minSdk 26, `FlutterFragmentActivity`,
  `PrivacyPolicyActivity`, manifest) have not been built yet. Check on a
  device where the iOS hint's "Open Settings" (`app-settings:`) lands.
- The admin web build now bundles and loads the RevenueCat web script,
  because `purchases_flutter` registers a web plugin. Harmless; revisit if
  the admin build is split from the app.
- `sendAnnouncement` is deployed on dev (with `deleteAccount`,
  `revenueCatWebhook`, and the rules) and was
  run end to end on the Android emulator: a non-admin is refused, an admin
  send arrives on channel `workout`, the same request id is not sent twice,
  the record reads `sent`, and tapping it from the background opens Today.
  Still open: the admin panel's Announcements page has not been opened in a
  browser (the function was called directly), and prod has none of the
  functions or the newer Firestore rules. iOS push: `aps-environment` is
  in `Runner.entitlements` and `remote-notification` in the background
  modes (2026-11-18, signs with the paid team). The APNs key W3KP8AP8K2
  is uploaded to both Firebase projects (development and production). An
  announcement sent to `announcements_en` on dev arrived on the owner's
  iPhone the same day, in front (shown by the app) and in the background
  (shown by iOS), once the app had been opened with notifications
  allowed. The first follow right after allowing may find no APNs token
  yet and subscribe only at the next start or resume.
- On a fresh Android install the first topic subscription failed twice on
  the emulator with "FCM Registration failed" and succeeded when the app
  next resumed (the existing retry). If real devices show it too, retry
  shortly after the failure instead of waiting for a resume.
- Notifications, not built yet on a device: `firebase_messaging` 17, the
  Android manifest's FCM default channel, icon and auto-init flag, and the
  iOS `FirebaseMessagingAutoInitEnabled` key. The `workout` channel
  is now created at start (an announcement on the emulator had landed on
  FCM's fallback channel before); check that one sent to a fresh install
  shows on `workout`. Check foreground display and taps on both
  platforms, and that the admin web build still loads (the plugin
  registers a web part). Since forge v0.7.0 reminders sync through
  `Notifications.sync`, whose signatures differ from the app's former
  ones, so every pending reminder is rescheduled once at the first start
  after the upgrade; check that they still fire and open their tab.
  `Notifications.openSettings` (the reminder tiles' "open settings") is
  not verified on either platform yet.
- Forge tasks; the app's own versions are accepted deviations, to be
  replaced once these exist:
  - The Live Activity bridge (`AppDelegate.swift`'s `WorkoutActivity`,
    `WorkoutActivityTaps` and a generic attributes type) could move to a package with a native iOS
    plugin once a second app needs one; the widget views stay in the app.
  - A messaging addition (to `forge_notifications` or a new package):
    following a topic per language with leaving the others, foreground
    display of pushed notifications, auto-init off until allowed (the
    app's `FcmAnnouncementRepository`).
- `forge_purchases` has no "unavailable" backend; the app swaps in its own
  repository for release builds without keys. Move it into the package when
  it is next changed.
- App Check (2026-11-20), monitoring first (owner's decision); enforcement
  is turned on before release. Live in code: `initFirebase` (forge_firebase)
  activates it before any Firestore, Storage or Functions call, with App
  Attest (DeviceCheck below iOS 14) on iOS, Play Integrity on Android and
  the debug provider in debug builds, the simulator included. Profile builds
  on the owner's iPhone use App Attest against dev. Runner.entitlements
  carries `com.apple.developer.devicecheck.appattest-environment` from the
  `APP_ATTEST_ENVIRONMENT` build setting (development for Debug and Profile,
  production for Release); the next `-allowProvisioningUpdates` build adds
  the capability to the App ID. The admin web build does not activate it
  (its own bootstrap, no reCAPTCHA key), so `sendAnnouncement` and the
  admin's Firestore writes must stay unenforced until the web gets a
  reCAPTCHA Enterprise provider. Not done yet, per project (dev and prod):
  - Register the iOS app for App Attest and DeviceCheck (App Check › Apps,
    or the App Check API's `appAttestConfig` / `deviceCheckConfig` on
    `projects/<p>/apps/<iosAppId>`; DeviceCheck needs a DeviceCheck key
    (.p8) of team A8J42TV74R, stored with `tools/secret.sh`).
  - Register the Android app for Play Integrity (`playIntegrityConfig`)
    once the Play Console exists: link the Cloud project in Play Console ›
    App integrity and add the Play app signing SHA-256 to the Android app.
  - Debug tokens: run a debug build; the token is in the native log, on
    iOS as "App Check debug token: '…'" (Xcode console or `flutter run`),
    on Android `adb logcat | grep DebugAppCheckProvider`. Add it under App
    Check › Apps › Manage debug tokens on dev (or the API's
    `debugTokens`). A token lives per install, so a reinstall prints a new
    one.
  - Watch the App Check metrics per product, then enforce per product
    (Firestore, Storage, Authentication; API `services/<service>`
    `enforcementMode: ENFORCED`). Callable functions: add
    `enforceAppCheck: true` to `deleteAccount`'s `onCall` options
    (`functions/src/delete_account.ts`); not to `sendAnnouncement` while
    the admin web has no App Check. `revenueCatWebhook` is an HTTP
    endpoint and stays as it is.

## Feature notes

How each feature behaves, by area. Not needed to resume: read the area of
the feature you are about to touch, and keep it true when you change it.

### Subscription and paywall

- **Subscription wiring**: `forge_purchases`, entitlement `premium`. RevenueCat
  when this platform's public SDK key is passed with `--dart-define`
  (`REVENUECAT_IOS_KEY`, `REVENUECAT_ANDROID_KEY`; never committed), else the
  fake in debug and profile builds (a debug-only "Fake store" section on the
  Profile tab steers it), else, in release, an unavailable store: nobody is
  Premium and the paywall says purchases are not available yet.
  `PurchaserSession` identifies the signed-in uid (guests too; linking keeps
  it) or resets, at startup and on every auth change, retrying failures.
- **Premium gate**: `context.watchPremium()` gives unknown / free / premium for
  locks; `await context.requirePremium()` before entering a premium feature
  (`lib/features/subscription/presentation/premium.dart`). Unknown never shows
  a paywall or a lock. The client value is for UI only; paid data is
  enforced by `entitlements/{uid}` in the rules.
- **Client vs server Premium**: only `revenueCatWebhook` writes
  `entitlements/{uid}` (written, not deployed), so client Premium (fake or
  RevenueCat) and server access can disagree: the fake never reaches the
  server, and a real purchase reaches it seconds to minutes later. Features
  treat a server refusal of premium content as locked, whatever the client
  says. On dev, `tool/set_premium.sh` writes the entitlement for demos.
- **RevenueCat webhook** (`functions/src/revenuecat_webhook.ts`), built to
  the documented contract
  (https://www.revenuecat.com/docs/integrations/webhooks,
  https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields,
  https://www.revenuecat.com/docs/integrations/webhooks/sample-events; the
  tests use the sample events, with our uid and entitlement):
  - Auth: the `Authorization` header must equal the Functions secret
    `REVENUECAT_WEBHOOK_AUTHORIZATION` exactly (the docs do not say whether
    RevenueCat adds a scheme, so the secret holds the whole value set in the
    dashboard, e.g. `Bearer <random>`); SHA-256 digests compared in
    constant time; else 401. Neither header nor body is logged. Deployed
    with `invoker: "public"` (RevenueCat has no Google credentials) and
    `maxInstances: 10`.
  - Only 200 counts as delivered; RevenueCat retries anything else about 5
    times over 80 minutes. So handled and deliberately ignored events answer
    200, requests that are not RevenueCat's 401/405/415/400, and only an
    Auth or Firestore failure 500. The event type is read first, so TEST
    and any type not handled answer 200 whatever their shape. Every
    response body is `{reason}` (`applied`, `test-event`, `unhandled-type`,
    `not-premium`, `no-expiry`, `no-user`, `deleted-user`, `stale`,
    `duplicate`, `nothing-to-transfer`, `retry`, ...), visible in
    RevenueCat's delivery log.
  - Sandbox and production events are treated alike (`environment` is only
    logged): with a release build only TestFlight testers and App Review can
    buy in the sandbox, and App Review buys against prod, so its purchase
    must unlock server content too. An event reaching the other project's
    webhook names a uid that project's Auth does not have and is skipped.
  - Events (only those whose `entitlement_ids` include `premium`, except
    TEMPORARY_ENTITLEMENT_GRANT, which names none; the app has only
    Premium). Grants never shorten Premium already known:

    | Event | Writes |
    |---|---|
    | INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, SUBSCRIPTION_PAUSED, SUBSCRIPTION_EXTENDED, REFUND_REVERSED | premium until the later of `expiration_at_ms` and the known expiry; `productId` = `product_id` |
    | CANCELLATION, any `cancel_reason` but a refund (UNSUBSCRIBE, BILLING_ERROR, ...) | the same: premium runs to the end of the period |
    | CANCELLATION with `cancel_reason` CUSTOMER_SUPPORT (the docs' only refund reason) | premium false, `expiresAt` = the earlier of `expiration_at_ms` and the event time |
    | EXPIRATION | premium false, as a refund |
    | BILLING_ISSUE | premium until the later of `expiration_at_ms`, `grace_period_expiration_at_ms` and the known expiry |
    | PRODUCT_CHANGE | as a grant; `productId` = `new_product_id` when present |
    | NON_RENEWING_PURCHASE | as a grant; a null `expiration_at_ms` (the docs: non-subscription or lifetime products) is 9999-12-31 |
    | TEMPORARY_ENTITLEMENT_GRANT (only `app_user_id` and the time) | premium until event time + 24 h (the docs' maximum), product kept |
    | TRANSFER (no user, entitlement or expiry fields) | the `transferred_from` uids' known Premium moves to the `transferred_to` uids (a later expiry they have is kept); the old uids get premium false |
    | TEST, anything else | nothing |

    Any other type without an expiry is never lifetime: it keeps the known
    expiry, or writes nothing (`no-expiry`). A refund or EXPIRATION for a
    product other than the stored `productId`, while the stored Premium
    still runs (a plan switch, a temporary grant expiring next to a
    subscription), keeps Premium.
  - Users: `app_user_id`, else the single uid among `original_app_user_id`
    and `aliases`; `$RCAnonymousID:` ids are never written. A uid Auth does
    not have (a deleted account) is skipped and its `entitlements/{uid}`
    deleted (idempotent, so a retry after a 500 leaves nothing either);
    after writing, a uid deleted meanwhile has its document removed, and
    `deleteAccount` deletes the entitlement again after the auth user.
  - Order and redelivery (one transaction per event): the document keeps
    `lastEventMs` (the latest `event_timestamp_ms` applied) and
    `lastEventIds` (the ids applied at that time, at most 20). A newer event
    replaces the state. Events of the same millisecond keep the outcome
    with the later Premium expiry (then the greater `productId`), whatever
    order they arrive in. An older event only extends Premium still
    granted (so BILLING_ISSUE's grace survives arriving after the billing
    error's CANCELLATION) and otherwise changes nothing; an id in
    `lastEventIds` is a no-op. Grants extend by taking a maximum, so a
    redelivered older grant is harmless too.
  - Not done: RevenueCat recommends fetching `GET /subscribers` after each
    event instead of trusting the payload; that needs a secret REST key and
    would fix the payload's blind spots (a transfer from an anonymous id or
    a deleted account, e.g. a restore by the new guest after deleting the
    account, grants the server nothing until the next renewal; two
    concurrent subscriptions are tracked as one `productId`). Revisit if
    one of these shows up.
- **Paywall moments** (Monetization, 2026-11-19): besides a Premium
  feature (`requirePremium`) and Profile's card, the app offers the
  paywall by itself at two moments: once per user, `onboarding` when the
  program suggestion is left (whichever way: Start, See other programs,
  or nothing to suggest; the router passes it to `ProgramSuggestionPage`
  so programs never imports subscription); and every time, `workoutDone`
  when any workout's summary is left by Done, back or Open programs (not
  Edit, which goes on to fix the workout; owner's pick, 2026-11-20; it was
  `firstWorkout`, once, after the first workout ever). The paywall first,
  then the summary goes.
  `FinishWorkout` marks a summary `firstEver` when none of its exercises
  had stats and `hasWorkouts` (server, else cache) finds no stored
  workout; unreadable is not first. A moment shows only to a user known
  to be free whose settings have loaded (`paywallMomentDue`), and is
  a once-per-user moment is marked shown at once in `settings.seenTips`
  (`onboardingPaywall`; a stored `firstWorkoutPaywall` is ignored), so it
  follows the account across devices and
  reinstalls. Premium, or a status still unknown, skips it unmarked.
- **Hard paywall from the store setup**: the current RevenueCat
  offering's metadata, carried by Forge's `Offering.metadata`, decides
  whether the onboarding moment's paywall (and the app-open one below)
  can be closed: `dismissible`
  false (a JSON bool, or the string "false") hides the close button and
  blocks back and the iOS sheet drag (`PopScope`; `SheetPage` drags only
  a page that can pop) until a purchase or restore; absent or anything
  else is closable (`offeringDismissible`). While the plans load that
  paywall has no close; a failed load is closable, so nobody is trapped.
  Every other paywall is always closable, whatever the metadata. The
  route carries the moment (`/paywall?moment=onboarding`). Debug builds
  on the fake store switch it with "Offering dismissible" among
  the Fake store rows. Which installs get a hard paywall is RevenueCat's
  targeting, set up in its dashboard, not in the app.
- **Hard paywall for paid traffic** (Monetization, 2026-11-20): Apple
  Search Ads is asked once per install whether it came from a campaign:
  the AdServices token (iOS 14.3+, no consent or ATT needed) sent from the
  device to Apple's attribution API (404 means not ready: three attempts
  5 s apart). Apple's final answer (the campaign id, or not attributed; a
  device without a token counts as not attributed) is kept on the device
  (shared preferences, Forge's); with no final answer (offline, Apple
  down) it is asked again on later launches, but only while the signed-in
  user is not past onboarding (`ProfileModule.pastOnboarding`, waiting
  for the profile to load; owner's call, 2026-11-20). After
  `PurchaserSession` identifies a uid (once per uid and launch, so also
  after signing in to another account), Forge's `RecordAdAttribution`
  applies the kept answer to that RevenueCat user: if attributed, the
  custom attributes `ad_network` = `apple_search_ads` and
  `ad_campaign_id` = the campaign id are set and
  `syncAttributesAndOfferingsIfNeeded` reloads the offering, so the
  targeting rule serves offering `hard` (same `$rc_monthly`/`$rc_annual`
  packages and products as `default`, metadata `{"dismissible": false}`).
  An offering load (the onboarding paywall) waits up to 5 s for an
  attribution in progress; slower, failed, not attributed, Android and
  the fake leave the current offering, the soft one. Not attributed never
  clears the attributes. Why not RevenueCat's own Apple Search Ads data
  (`enableAdServicesAttributionTokenCollection`, also turned on, for its
  charts): RevenueCat asks Apple "within a 24 hour period", too late for
  the paywall at the end of onboarding, and its docs do not say which
  value it writes to `$mediaSource`. No Cloud Function: Apple's API takes
  the device's token without credentials, and a forged attribution only
  makes the forger's own paywall hard. Which campaigns get the hard
  paywall is the targeting rule's list of campaign ids, changed in the
  RevenueCat dashboard without an app update; a device in developer mode
  gets Apple's test record, campaign 1234567890, which a test rule can
  list. The hard paywall is the soft one's page with the same plans, so
  it shows and starts the 7-day trial exactly as the soft one ("Start
  7-day free trial", "Free for 7 days, then ..." and the renewal terms);
  only the close button and back are gone.
  - Done by API (2026-11-20): offering `hard` (ofrng478c2e07b1) with
    `$rc_annual` (pkge2616eb39e1) and `$rc_monthly` (pkge1e366b665a), each
    with the App Store and Test Store products of `default`; `default`
    unchanged and still current.
  - Left for the dashboard (RevenueCat, project GetWorkout): (1)
    Integrations › Apple AdServices › Add Apple Search Ads integration
    (Basic; Advanced only with an Apple Ads account, via Sign in with
    Apple), for RevenueCat's charts. (2) Once a build with this change has
    set the attributes for one customer (a developer-mode device sets
    campaign 1234567890), Targeting › New rule "Apple Search Ads → hard":
    Audience source Custom filters, `ad_network` is `apple_search_ads` AND
    `ad_campaign_id` is any of <the campaign ids to make hard>, Offering
    `hard`, all placements; save Live (the Default Offering stays
    `default`). Testing: add 1234567890 to a rule limited to a TestFlight
    app version, check the hard paywall on a developer-mode device, then
    remove it. Apple Ads ad groups must not use age or gender targeting
    (Apple returns no attribution for them since 2026-09).
  - App Store privacy (before release, with the labels in Open
    questions): the app sends the AdServices token to Apple and the
    campaign id to RevenueCat linked to the account, so App Privacy gets
    Usage Data › Advertising Data, linked to the user, purposes Analytics
    and App Functionality, not used for tracking; no ATT prompt and no
    `NSUserTrackingUsageDescription`. AdServices is not a required-reason
    API, so the privacy manifest is unchanged. The privacy policy should
    say that installs from Apple Search Ads are recognised to choose the
    subscription offer.
- **Hard paywall on every app open** (Monetization, 2026-11-20): the
  onboarding moment is marked shown before it opens, so killing the app
  on it used to get a hard-offering user in for free. `HardPaywallGate`
  (created by `App` with the router) opens the paywall at moment
  `appOpen` (`/paywall?moment=appOpen`, never marked in `seenTips`; like
  onboarding's it is full screen and the offering's metadata decides
  whether it closes: `PaywallMoment.offeringDecides`) when an open is
  due: each launch, each return from the background (`onShow`), each
  time the entitlement turns inactive (Premium lapsed, another user) and
  each time the gate's paywall is gone without Premium (a `go` from a
  notification tap, a redirect, a failed load that let it close). A due
  open is checked when every open page is past the start (`isPastStart`:
  not over onboarding, its end with the onboarding paywall, the
  verification page or the splash), Forge's app gate shows no update or
  maintenance page, no account deletion runs and no other paywall is
  open (`paywallOpen`, the same guard as `openPaywall`), and re-checked
  on every navigation and app gate change until then (after the frame).
  Premium ends it; an unknown entitlement waits; a free user's offering
  is loaded once (`GetOfferingHard`): soft or failed ends it until the
  next due open, hard opens the paywall. On it, a pending purchase shows
  its waiting card with no Got it and the paywall stays until approved;
  coming back while it is open opens no second one. A pending purchase
  is not remembered across a relaunch: the new paywall shows the plans
  again. The fake store's "Offering dismissible" row switches it in
  debug builds.
- **Prices and trial**: the store's (monthly 7.99 USD, yearly 39.99 USD
  with a 7-day trial on yearly only); the app shows what the store
  returns, and the fake store's plans use these numbers. The trial shows
  only with the yearly plan (its row's terms, card and button).
- **Paywall**: full-screen `/paywall`, yearly listed first (the app sorts
  yearly before monthly, whatever the store's order) and selected by
  default, prices as
  the store gives them, trial shown only when the plan carries one, restore
  and legal links always visible. Terms and privacy URLs live in
  `lib/app/legal_links.dart`; placeholders until the pages exist. Layout
  (UX pass, 2026-11-13, owner's pick): the intro and the three benefits
  scroll; the selected plan's purchase button and its terms, then Restore,
  Terms and Privacy, are fixed at the bottom while they take at most half
  the page's height; taller (large text), the whole page scrolls as one in
  that order. Three plan layouts are kept for
  an A/B/C test, the rest of the page shared: A lists the plans as rows (name,
  whole offer), B shows one card per plan side by side (name, the store's
  price, its period, then any trial or intro price), as many cards as the
  store offers (two today), C shows one plan (yearly) with its benefits and
  "See monthly plan" under it (PW-Q1, 2026-11-17, replacing "Or monthly,
  <price>"). The page is Forge's `SubscriptionPlans` fed from
  `PremiumPaywallCubit` (PW-F1): rows "Yearly" / "$39.99 / year" with
  "Best value" on yearly when there is a monthly plan, tiles "$39.99"
  over "7 days free" (else the intro offer, else "billed monthly"), the
  single plan "Yearly · 7 days free" / "$39.99 / year" / "That is $3.33 a
  month."; the button "Start 7-day free trial", "Start for <price>" or
  "Subscribe"; the full renewal terms under it (PW-Q2). Prices failed:
  the "Couldn't load plans" card and a disabled "Subscribe" without terms
  (PW-Q3); a store that cannot sell: the unavailable card; a pending
  purchase: the "Waiting for approval" card, whose "Got it" closes the
  paywall (Premium unlocks by itself once approved); a paywall that cannot
  be closed (the hard onboarding one) shows the card without "Got it" and
  stays open until the approval brings Premium and closes it (owner's
  call, 2026-11-19). Restore's result is
  "Premium restored." (the paywall closes) or "Nothing to restore.".
- **Win-back offer** (W2, owner's pick, 2026-11-20): a lapsed subscriber
  the App Store offers a win-back (iOS 18+, Apple decides eligibility) sees
  it on the paywall: every plan that carries one gets the record tag
  "Welcome back · 1 month free"; in A the price line is "1 month free,
  then $39.99 / year", in B the tile's line is "1 month free", in C the
  name is "Yearly · 1 month free"; the button is "Start free month" (a
  longer free period "Start N-month free trial", a paid one "Start for
  <price>"), the terms "Free for 1 month, then <price per period>" and
  the renewal. Buying the plan applies the offer. Everyone else, and
  Android, sees the paywall unchanged. Forge carries it as `Plan.winBack`
  (only when eligible, in place of any trial or intro). The fake store
  offers its plans' free month once the user's subscription has ended
  ("End subscription now (win-back)" among the Fake store rows).
- **Manage subscription** (W1, owner's pick, 2026-11-20): on iOS it
  presents RevenueCat's Customer Center (themed in the RevenueCat
  dashboard), whose cancel path first offers the "1 month free"
  promotional offer (Claim free month / No thanks, cancel); a claimed
  month or a change arrives through the entitlement stream. Where the
  Customer Center cannot show (the fake store, an error) and on Android
  (until Play is set up) the store's manage page opens instead; if that
  fails too, "Couldn't open your subscription settings.".
- **Paywall A/B/C test** (Firebase Remote Config + A/B Testing, owner's call,
  2026-11-13; `forge_remote_config`): the Remote Config string
  `paywall_layout` picks the layout, `a` (list), `b` (cards) or `c` (one
  plan); the app's
  default is `a`, and an empty or unknown value is A too
  (`GetPaywallLayout`). `bootstrap` registers it on Firebase in every
  build, against the build's project (fetched at most every 12 h in
  release, every minute otherwise); tests use the fake. Startup activates
  what an earlier launch fetched, alongside the telemetry restore, and
  fetches the next values in the background, so the layout is stable for a
  whole session, a new install sees A in its first session and its arm
  from the second, and a failure only leaves the defaults. The paywall
  reads the layout once, when it opens (`PremiumPaywallCubit.layout`).
  Debug builds on the fake store override it with the "Paywall layout" row
  among the Fake store rows (Remote Config, A, B or C; in memory until
  restart); release builds do not register the override. Events, through
  `Telemetry.logEvent` (`forge_core`): `paywall_view` {`layout`: `a`|`b`|`c`}
  once per paywall open, when the plans first show to a user without
  Premium (not on a failed load, nor for a subscriber, whose paywall
  closes at once):
  the experiment's activation event; `paywall_purchase` {`plan`: the
  plan's period, `monthly` or `yearly` (the same on both stores, whose
  product ids differ), `layout`} on each purchase or trial start that
  granted Premium on the paywall: the goal. A pending purchase approved
  later and a restore are not counted. Events follow the analytics consent
  below, so prod counts only release builds, for signed-in users (guests
  included) who did not turn "Share usage data" off, are counted. Remote Config
  itself is fetched for every user, whatever their answer to "Share usage
  data" (owner's call, 2026-11-13): a user who turned it off still gets a
  layout but is never measured; the privacy policy says so instead of the
  fetch being gated. The Remote Config parameter and the experiment are
  set up in the console, not by the app.

### Account and privacy

- **Account page**: a signed-in user's card has Email, "Signed in with"
  (`AuthUser.signInMethods`: Email, Google, Apple, comma-joined) and Data,
  "Backed up" or "Waiting to sync" (AC-Q1; no time is recorded):
  `FirestoreSyncRepository` asks Firestore's `waitForPendingWrites` when
  the page opens and whenever `snapshotsInSync` fires, and calls writes
  the server takes within 2 s backed up, so a normal write never flashes
  "Waiting". Then "Subscription" with the GetWorkout Premium row, "You are
  on Free" or the Profile card's state; it opens the paywall when free and
  Manage subscription for a subscription, nothing while checking or
  for lifetime Premium (AC-Q2). Then Sign out (a dialog; a failure is a
  snackbar "Couldn't sign out." whose Retry signs out without asking
  again) and Delete account. A guest gets the guest card (Create account,
  I already have an account), the subscription row and Delete my data.

- **Analytics consent** (`lib/features/account`):
  `settings.analyticsConsent` of each user, guests included (a guest has a
  uid and a user document; linking keeps it, signing in to an existing
  account takes that account's answer). Consent is per user, never per
  device. Opt-out (Feature notes › Analytics): false is off; true and null
  (never answered, so everyone not asked before) collect, through
  `initFirebase(collectUnanswered: true)`. Users who said no before keep
  no. Never asked: there is no consent page, in onboarding or over the
  tabs. Analytics and Crashlytics collect in prod release builds and, so
  events can be checked in DebugView, in debug and profile builds into the
  dev project (owner's pick, 2026-11-20; Forge v0.46.0), for the signed-in
  user, with their uid as the user id; never the advertising
  ID, Android ID or IDFV, and no ad personalisation signals (the `AD_ID`
  permission is removed). They still start off natively (Info.plist,
  AndroidManifest.xml): on a fresh install nothing is collected until the
  signed-in user's answer is known, so a user who said no on another
  device is never collected for a moment. At start, collection is what the
  last applied answer left (the SDKs keep it), or that native off on a
  fresh install; `initFirebase` does not change it, and
  `FirebaseTelemetry.restore` then applies the answer the user signed in
  at launch last gave on this device (one file per uid in app support, a
  saved null collecting). Whenever the signed-in user changes or is
  unknown, collection goes off until that user's stored answer is read,
  and stays off when the read fails. `ConsentCubit` (app-wide) applies
  each answer as it arrives, null included, but a missing answer only
  from the server: a cached copy without one may predate a no from
  another device. Changes run one at a time and the latest wins. Turning
  on first deletes the crash reports recorded before it and is saved
  last, so a failure never leaves it saved. While an account is being
  deleted (`DeletionUnderway`) its consent is not followed, so the deleted
  document (read as no answer) never turns collection back on for the
  deleted user; a deletion that failed follows it again. Changed with the
  "Share usage data" switch under Profile → Privacy: on for true and null,
  off for false; turning it saves an explicit true or false. The settings
  feature leaves the field alone: its writes merge, and `UserSettings` does
  not carry it.
- **Privacy policy link**: Profile → Privacy, in the browser.
  `LegalLinks.privacyUrl` (`lib/app/legal_links.dart`) is the one place the
  address is written; the Android build reads it from that line into
  `R.string.privacy_policy_url` for Health Connect's
  `PrivacyPolicyActivity`.
- **Deleting an account**: Account → "Delete account" ("Delete my data"
  for a guest), set apart in the error colour, opens a page saying what is
  deleted from the servers right away (profile and settings, programs,
  workouts, records, custom exercises, cardio, body entries and photos,
  the sign-in), what is cleared on this device at once and that the
  offline copy goes at the next start, and that a store subscription is
  not cancelled; then a confirmation dialog. Steps: the router holds
  everyone in place (`DeletionUnderway`), so the vanished profile cannot
  open onboarding and write the user's document again; the workout in
  progress stops keeping and syncing for the user; the device's pending
  writes are sent (10 s at most; offline fails with nothing asked or
  deleted); the callable `deleteAccount` deletes. For an account with a
  credential it wants a sign-in from the last 5 minutes, else the app asks
  for a renewed sign-in and tries again: the password field when the user
  has one, and a button per linked provider (`AuthUser.signInMethods`)
  that renews it with that provider (`forge_auth`'s
  `ReauthenticateWithProvider`); a cancelled provider sheet leaves the
  dialog open and asks nothing. A user with Apple linked always goes
  through Apple first: `forge_auth`'s `ReauthenticateWithAppleCode` signs
  in again with Apple natively and returns a fresh authorization code,
  which `deleteAccount` uses to revoke the app's Apple tokens at Apple
  before deleting anything (App Store 5.1.1(v)); the Apple button of the
  renewed sign-in dialog does the same. A closed sheet deletes nothing; a
  failed Apple sign-in or a refused revocation deletes nothing and shows
  the delete failure. Firebase's own revocation
  (`revokeTokenWithAuthorizationCode`) failed on the owner's iPhone with
  `invalid-credential` and hid Apple's answer, so the function does it
  with the `APPLE_SIGN_IN_KEY` secret (set per Firebase project before
  deploying `deleteAccount`) and logs Apple's answer on failure. A guest
  is deleted
  the same way, without that check. Once the server deleted the data,
  still signed in (so nothing of the next guest is touched), the app
  removes the user's kept workouts file (unreadable copies too), cancels
  every scheduled notification, records no consent for them and resets the
  analytics id and unsent crash reports, and marks Firestore's offline
  copy, which is cleared (`clearPersistence`) at the next start before
  Firestore is used; then it signs out and a new guest starts at
  onboarding. A local leftover is logged, not reported. If only the
  sign-in is left (the function's `details.reason` says so) the user stays
  held on the page, which offers only "Try again" (no back in its app
  bar). A function not deployed
  or not callable answers `not-found` / `permission-denied`, shown as
  "deleting accounts isn't available yet", never as done; anything else
  that failed before the data went gives the workout back.

- **Email verification** (blocking, owner's decision; `forge_auth`'s
  `EmailVerificationPage`, route `/verify-email`): only an email and
  password account must verify; Google or Apple next to it counts as
  verified (`AuthUser.needsEmailVerification`), and guests are unchanged.
  Creating or linking an email account mails the link at once
  (`SignUpWithEmail`; a failed send still signs up, Resend covers it).
  Until verified the router shows the page instead of the app, at start
  too (existing unverified users included) and after signing in to an
  unverified account; once verified it goes on like the splash gate
  (Today, or onboarding for a profile without it).
  - Page (owner's pick, canvas
    https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ row V1, board A'):
    mail icon, "Check your email", the line, a "Sent to" card with the
    address, the moving "Waiting for confirmation…" line, "Resend email"
    (secondary) and "Use another email" (text). No "I've verified"
    button: the page reloads the user every 4 s while the app is
    visible, stops while it is hidden, and reloads at once when it shows
    again. Resend counts down 60 s from the last link this session sent
    (so from the page's first frame right after sign-up or linking), or
    after a `too-many-requests` answer; a page opened in a later session
    can send at once.
  - "Use another email" (row V2, board A) opens the "Change email" sheet:
    "We will send a new link. Your workouts stay with this account.", a
    "New email" field, "Send link" (primary) and "Sign out instead"
    (text; signs out at once, a new guest starts on onboarding; nothing
    is deleted, the account and its data wait for its next sign-in).
    Send link calls Firebase's verify-before-update-email on the same
    account (same uid, same data); the sheet closes, "Sent to" shows the
    new address, Resend then resends to it, and the page keeps waiting.
    Opening the link makes it the account's verified email and the app
    goes on. Errors under the field: a malformed address (checked before
    sending), `invalid-email`, `email-already-in-use` (Firebase may not
    report this with email enumeration protection on; the link then
    fails when opened), and `requires-recent-login`, which the
    repository first answers by signing in again with the password this
    session used (sign-up, link, sign-in or re-authentication; kept in
    memory only, dropped on sign-out or deletion); without it the sheet
    says "Please sign in again to continue".
  - Confirming an email change revokes the session and Firebase signs the
    user out; with the password from this session, the guest start signs
    in to the new address instead of a new guest, so the user lands back
    in the app. Without it (the app was restarted since), the user lands
    as a new guest on onboarding and signs in with the new address; the
    data stays on the account. Not checked on a device yet.
  - Email templates are Firebase's defaults in both projects: sender
    `noreply@<project>.firebaseapp.com`, subject "Verify your email for
    %APP_NAME%", the link handled at
    `https://<project>.firebaseapp.com/__/auth/action` (no custom
    domain), locale en; the email-change template is the default too. To
    customise later in the console (Authentication > Templates): sender
    name, subject and text, the action URL (a custom domain on Hosting),
    and a custom sender domain.

### App shell, settings and onboarding

- **Navigation** (owner, 2026-11-13): five tabs, Today / Programs /
  Exercises / Progress / Profile, in a Material `NavigationBar` (icons
  `today_outlined`, `event_note_outlined`, `fitness_center`,
  `insights_outlined`, `person_outline`; five labels fit a 375 pt phone).
  Programs (`ProgramsPage`, `/programs/...`: the active program, the week,
  the missed-day prompt, Ready-made, Generate, New program, Start empty
  workout, the user's programs, and every page they open) and Exercises
  (`ExercisesPage`, the model under a search box, `/exercises/...`: the list,
  exercise pages, custom exercises; see Exercise list) are two branches of
  the shell, each with its own stack, kept alive like the others and built
  the first time it shows; there is no segmented control any more. "Add
  to program" pushes the builder in the tab its exercise is in (see
  Program page); a custom exercise's edit form opens in the Exercises tab
  from wherever its page is (also above the workout or the calendar). Starting a workout stays on Programs
  (and Today). Every location kept its path (the merged Train tab already
  used `/programs` and `/exercises`, and no notification payload or stored
  route ever held a Train path), so nothing needs a redirect. The active
  workout is full-screen and can be minimized to a bar above the tabs: it
  rises from the bottom over the tabs (`RisingPage`, both platforms; WO1
  B) with a grabber (Forge `ForgeGrabber`, the bottom sheet's) above its
  header, and goes back down to the bar on ⌄ at the top left, back, or a
  drag down on the grabber or the header (`DragToClose`: the page follows the finger and
  closes when let go past half way or flung down, else springs back).
  Pages opened above it (picker sheet, exercise detail) open and close as
  before.
  Tapping the open tab returns it to its first page the way back would. A
  `go` (a link, a notification tap) replaces its tab's stack (each tab is
  its first path segment); a page there with unsaved changes
  (program builder, custom exercise form, workout edit, measurement day)
  is never dropped silently. One router
  guard (`onEnter`, `lib/core/unsaved_changes.dart`) brings that page up
  (its tab, the workout or paywall above the tabs put away, the workout
  staying in its bar) and asks with the page's own discard prompt: keep
  editing stays there, discard makes the navigation again. Pages without
  changes (an edit left as it opened, a page that saved), other tabs'
  stacks, pushes and tab switches are left alone. Back and the guard share
  one prompt per page, so nothing asks twice.
- **Navigation gestures** (owner, 2026-11-18, after the developer Gesture
  lab): every pushed page is the platform's page route (`AppPage`,
  `lib/core/pages.dart`): on iOS the Cupertino slide with Flutter's left
  edge back swipe and default scroll physics. Tab roots and the start
  pages (splash, retry, onboarding, suggested program) have no
  transition. go_router's page for a `builder` route had none either, so
  no swipe: its MaterialApp check looks for `material_ui`'s class, not
  Flutter's; every pushed route has a `pageBuilder` now. Pages over the
  flow (the paywall, the exercise picker's Add and Leave out forms) are an
  iOS sheet (`SheetPage`) that a drag down closes, from its list's top
  too, and keep close; on Android a full-screen dialog. A page that
  refuses to pop (unsaved changes, `PopScope`) still follows the edge
  swipe; let go where it would leave, it springs back and the page's own
  prompt asks (Keep editing stays, Discard leaves), as back does.
- **Profile tab** (UX pass, 2026-11-13, owner's pick; studio board
  2026-11-15): one page, top to bottom: the account header, the Premium
  card, More (Your profile; the calculators are Today's since the Tabs
  picks), then the settings groups (Units,
  Workout, Reminders, Connected apps, Appearance), Privacy and, in debug
  builds, on the fake the Fake store rows. An Apple relay address
  (`@privaterelay.appleid.com`) is never shown: a named user shows the
  name alone, and a user with no name and no other address who signed in
  with Apple reads "Apple account" / "Signed in with Apple" with the
  guest's person icon (K15 A). A
  guest's header opens the guest account sheet (forge_auth
  `showLinkAccountSheet`: "Keep your workouts safe", Google, Use email
  instead, Not now); Use email instead opens Sign in on the email form
  in create mode, which links the guest (GA6, GA7). Every
  change saves at once; a failed save shows a snackbar. The Premium card
  (`PremiumCard`) is, for a free user, Forge's `PlanCard`: Premium's
  name, the store's trial as its tag, three benefits and "Get Premium"
  (the paywall); otherwise, as a FeaturedCard prompt, the user's state
  (checking, trial, renews, ends, lifetime, payment problem) is its title
  over that line, and a subscriber (trial, renewing, ending, payment
  problem) gets "Manage subscription" (see Manage subscription); lifetime
  or granted Premium (no expiry, nothing to manage) and an unknown status
  get no action. Workout group: effort, warm-ups, the rest timer and,
  while it is on, its default rest, rest notification and rest sound
  (`settings.restTimer.alert`: chime and vibrate (default), chime,
  vibrate or off; a rest reaching zero in the app plays the chime,
  `assets/sounds/rest_chime.wav` (two soft bell tones, generated for the
  app, no licence), through `audioplayers` mixed with other audio and
  silent in silent mode, and vibrates as chosen; the rest notification
  sounds the same: one Android channel per choice (`rest_chime_vibrate`,
  `rest_chime`, `rest_vibrate`, `rest_silent`, "Rest over · <choice>"),
  as Android fixes a channel's sound and vibration, the chime bundled as
  `res/raw/chime.wav` and iOS `chime.caf`; iOS cannot vibrate without a
  sound, so Vibrate is silent there), Bar and plates (a summary; its
  page edits the barbell, EZ bar and trap bar weights and the plates, and
  puts back the standard set) and Keep screen on (`settings.keepScreenOn`,
  default on: the screen stays awake while a workout is in progress,
  through `wakelock_plus`). Connected apps: the health store (Apple
  Health, or Health Connect) with what the app reads ("Steps and cardio in") and
  On / Off from step access, read again on resume; On opens the store's
  settings, Off the Steps page (which explains before asking); hidden
  without a health store. Restore
  reports its result in a snackbar and, on success, closes the paywall
  (owner's pick, 2026-11-15).
- **Start and sign in** (design pass, Kurulum, 2026-11-17): the splash
  is Forge SplashScreen, the GW mark and GetWorkout on featured (the
  native launch screen is the same featured colour, iOS and Android), its
  slow-start line after 2 s (SP4); a guest session that cannot start
  shows SplashScreen.failed, "Couldn't start. Check your connection and
  try again." with an outline Retry (SP3). Sign in is forge_auth's
  AuthPage on SignInPage (`AccountAuthPage`): the mark, "Plan it, log it,
  see it add up.", Continue with Google, Use email instead, the terms
  line linking Terms and the privacy policy; email errors that belong to
  a field show under it, the rest as "Sign-in didn't finish. Try again."
  with Retry (SI6); "Continue as guest" shows only with nobody signed in,
  so never for the app's guest (SI7). Pushed from Profile or Account
  (`/profile/account/auth`) it opens full screen over the tab bar.
- **Units**: stored metric. kg/lb and cm/in chosen by the user. A single
  lifted weight is shown through `WeightUnit.shown`: within two decimals
  (the precision weight fields show; 1e-8 hundredths of tolerance, the
  nearest other-unit weights being 4e-6 off: 538.92 lb, 244.45 kg) it was
  typed in this unit and shows as typed; otherwise it was typed in the other
  unit and shows rounded, to whole lb (80 kg → 176 lb) or half kg (45 lb →
  20.5 kg), or to two decimals when that would show a positive weight as 0.
  Display only: fields store what is typed, converted to kg; an untouched
  field stores nothing, and typing back the number a field showed keeps its
  stored kg (`RetypedWeights`, in the workout editor and the program
  builder). Set rows and drops, previous and suggested values, workout
  detail, heaviest-weight records and program targets use it. The estimated
  1RM is computed, so it always shows rounded the same way
  (`estimatedFromKg`: records, the strength chart and its labels); volume,
  body weight and the calculators (results of typed inputs) keep their own
  formatting. A weight typed with more than two decimals is taken for the
  other unit's and shows rounded.
- **Week start** (owner, 2026-11-13): the whole app uses one first day of
  the week: the calendar, the Today and Progress week strips, weekly
  volume, Cardio (summary, 12-week chart, week headers, Progress card), the
  Body chart's weekly bars and step averages, the Steps "This week" chart,
  the program week plan (and so the done days the workout reminders know),
  and the order of weekdays in the Training days sheet, the weekdays of the
  Programs tab's active program card and the program page, and
  the measurement reminder's day. Settings → Appearance → "Week starts on":
  Automatic (default, shown as "Automatic (Monday)" with the day it gives),
  Monday, Sunday or Saturday (`settings.weekStart`, written only when not
  automatic). Automatic is the phone's region, not the app's language
  (English only, so Sunday for everyone): the device locale
  (`PlatformDispatcher.locale`, followed on change). With a region, CLDR's
  weekData `firstDay` for it (CLDR 49, a const table in
  `regionFirstWeekday`; unlisted regions Monday): `en_TR`, `tr_TR`,
  `en_GB` Monday, `en_US` Sunday, `ar_EG` Saturday, `MV` Friday (only
  Automatic can give Friday). Without a region, the language in intl's
  bundled date symbols (`dateTimeSymbolMap()`, `FIRSTDAYOFWEEK`, 0 =
  Monday), else Monday. `WeekStart.firstWeekday`
  resolves the setting against it; widgets read it in `build` with
  `context.watchFirstWeekday()` and pass it to the cubits they create,
  which follow a change while alive through `FirstWeekdayListener`
  (`changeFirstWeekday`). The app-wide `ProgramListCubit` and
  `CardioListCubit` are created with the value of that moment
  (`currentFirstWeekday`) and told of changes by the app and by the
  pages showing them. A new week start moves the program week plan once
  the new week's done days arrive, keeping the known ones meanwhile, and
  not while the list shows a failure. Only views change: stored dates,
  program weekdays and schedules, `nextDate` and program lengths (counted
  from the start date) never depend on it.
- **Onboarding questions** (UX pass, 2026-11-13): a welcome page, then one
  question per page, all nine needing an answer: goal, level, days per
  week, equipment, sex, birth year, height, weight, target weight. There
  is no skipping and no closing summary; Next on the last question ends
  onboarding. Height and the two weights are picked on a ruler
  (`RulerPicker`, forge_ui) or typed by tapping the value; the birth year
  on a wheel. A ruler has to start somewhere (170 cm, 70 kg, age 30), so a
  number question counts as answered when it shows; the target weight
  follows the weight until the user picks one. "I already have an
  account" shows on the welcome page for a guest only. In "Your profile"
  every answer can be changed but not removed. Design pass (Kurulum,
  2026-11-17): the welcome is the mark on an accent tile, "Train with a
  plan that fits your week.", a muted line and three numbered lines
  (BenefitList), Get started and the guest's link at the bottom; every
  question's action is Continue; the goal question reads "What is your
  main goal?" with subtitles, Lose fat first (also in Your profile), and
  only in onboarding "We use it to pick your first program." under it.
  Only in onboarding, the target weight reads "Your goal" over "Now,
  where do you want your weight to be?" and "You weigh 70 kg now. Leave it
  there to hold your weight." (K10 A); the target's ruler marks the
  weight now, "Now 70 kg" (Forge `NumberPicker.ruler(marker:)`, also in
  Your profile). Every next question slides in from the right as the
  one before leaves to the left, and Back slides the other way, so a step
  that looks like the last still reads as a new page (K10).
  Equipment (L3 A): the sets (Full gym, Home gym, Dumbbells and a bench,
  Pull-up bar and dip bars, Resistance bands) as ChoiceGrid list rows
  like the goal question, the one matching the answer selected; a row tap
  picks its set; its info button ("Details of <set>") opens a sheet titled
  by the set, "Untick what you don't have, tick anything extra.", the
  seven common items and every item ticked as checkboxes, More equipment
  for the rest and Done, which picks the tuned set; the row it was opened
  from stays selected while the question shows. Coming back with
  equipment that matches no set (M3 A) selects no row; a muted line under
  the list reads "Custom equipment · 9 items" (the items owned, bodyweight
  aside) with an Edit opening the same checkbox sheet titled "Custom
  equipment"; Done there keeps the items, selecting a set's row if they
  now match one, and picking a set replaces the line. The generator's
  equipment question is the same.
  After the last question (`afterOnboarding`,
  `OnboardingPermissionsPage`), the progress bar full: "Remind you on
  training days?", only while the device does not let the app notify yet
  (allowed already, the step is left out and the reminder stays as it is)
  (Turn on reminders asks the system and, if allowed,
  turns the workout reminder on at its default time; refused or Not now
  moves on silently, ON6), then "Bring in steps and cardio?" naming
  Apple Health or Health Connect (ON5), shown wherever a health store
  exists and steps cannot be read yet: never asked, refused or (iOS)
  undetermined (SG4). Connect asks where the system still can (never
  asked; Android refused asks again) and otherwise opens the store's or
  the app's settings (iOS once asked; Android still refused after
  asking); Skip moves on. Then the suggestion: "Your plan is ready",
  the FeaturedCard outline ("Recommended for you · free", the name,
  "3 days · Intermediate · 8 weeks" with the session time, each day as a
  row with its suggested weekday tag), "Why this one" (the user's goal,
  days and equipment set that the program matches in one sentence, an
  unmatched answer left out, then the catalogue summary, ON10, CK1), and at the bottom Start this program (saves a copy among the
  user's programs without starting it and opens its page; the user's
  existing copy opens instead, SG1) and See other programs; no
  "Not now" (ON8); while it is chosen the card's loading form and a
  disabled Start. The page frame, the
  question layout and the radio answers are shared with the generator
  (`QuestionScaffold`, `QuestionLayout`, `ChoiceAnswer` in
  `lib/core/question_page.dart`; `EquipmentAnswer` in
  `profile_questions.dart`).
- **Days per week recommendation** (DW1 C, DW2 A, DW3 A; canvas under
  Design): "How many days a week can you train?" recommends the days most
  lifters at the user's level train (`Level.recommendedDaysPerWeek`:
  beginner 3, intermediate 4, advanced 5). Under the question "Most
  beginners train 3 days a week." ("Most intermediate lifters …", "Most
  advanced lifters …"), and that row carries a soft Recommended tag
  (`ForgeTagKind.record`, Forge `ChoiceOption.tag`). Nothing is
  preselected: the user still picks, and a saved answer stays the one
  selected. Onboarding uses the level just answered (changing it and
  coming back moves the recommendation); Your profile › Training days
  uses the saved level. With no level known neither shows.
- **Birth year**: a plausibility range (age 13-100), not an age gate. An
  implausible year is only not accepted as an answer; nothing is blocked.
- **First-use tips**: four inline banners (Material `MaterialBanner`,
  never modal), each with "Got it", none until the user's settings have
  arrived: effort, inside the effort question the first time, in the
  rest strip or the bar (under the steps, scrolling with them, so the
  countdown and every step stay in view), until it is dismissed or an
  effort is picked; set types, at the top of the add-set sheet, until a
  type is picked there; automatic warm-ups, at the top of the workout in
  progress once warm-ups were added to it automatically
  (`warmupsAdded`), until the setting is changed; the body model, under
  the Exercises tab's model once it has loaded, until it is dismissed or a
  muscle is opened from the model. Dismissing or using the
  thing marks it seen for good, in `settings.seenTips` (codes `effort`,
  `setTypes`, `autoWarmups`, `muscleModel`; the paywall moments use the
  same list, see Subscription and paywall; the app has no local flag store, and this
  follows the user across devices). Tips are only ever added to that list,
  field by field (`arrayUnion`), never written with the other settings, so
  two devices and codes from newer versions are kept. Which tip is due is
  pure logic (`workout_tips.dart`, `exercise_tips.dart`).
- **Explanations for beginners**: each set type has a one-line description
  under its name in the add-set sheet and the bubble's long-press menu
  (Normal "A regular working set.", Warm-up "A lighter set to get ready.
  Not counted in your stats.", Drop set "Finish the set, then lower the
  weight and keep going without rest."). The set bar shows the
  effort question or row (see Effort scale) and, for a warm-up or drop set,
  its description (one line,
  the rest in the help) under the title, which names the kind in words (`setToDo`: "Bench Press · Warm-up
  1 of 2", "· Warm-up" for the only one, "· Drop set 2 of 3"; the lock
  screen and rest notification follow). An "Explain" (?) button next to
  the effort question and row opens one scrolling help sheet:
  what effort is and what the app does with it, every step of the user's
  scale and what it means, Failed, warm-up sets (with the automatic ramp)
  and drop sets.

- **Update and maintenance gate** (owner's call, 2026-11-20; picks U1–U3
  on the canvas https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ;
  `forge_app_gate`): three rules from Firebase Remote Config, checked by
  `AppGateCubit` against the installed version (`package_info_plus`, the
  marketing version only: `1.2.0` of `1.2.0+7`; the build number is not
  compared, since a store release always raises the version).
  - Keys (all with in-app defaults that ask nothing, so an absent key
    never blocks; `AppGateModule.remoteConfigDefaults`, merged into
    `RemoteConfigModule`'s defaults in `bootstrap`):
    `min_version_ios`, `min_version_android`, `recommended_version_ios`,
    `recommended_version_android` (strings, default `''`: a version such
    as `1.2.0`; missing parts are 0, a value that is not a version asks
    nothing), `maintenance` (boolean, default `false`, one switch for
    both platforms; per platform only through a console condition) and
    `maintenance_message` (string, default `''`: the app's own text; a
    language is added later with a console condition on the device
    language). Created on getworkout-dev (2026-11-20, group "App gate",
    "use in-app default"); not on prod yet.
  - Order: maintenance first (an update does not help while it lasts),
    then the minimum, then the recommended version.
  - U1 Update required: below the minimum the app is replaced by a page,
    "Update required" / "This version of GetWorkout is no longer
    supported. Update to keep training; your workouts are safe." and one
    Update button opening the store (App Store
    `https://apps.apple.com/app/id6836913044`, Google Play
    `https://play.google.com/store/apps/details?id=com.getworkout.app`).
    Nothing else is reachable; Back does nothing.
  - U2 Recommended update: below the recommended version (and at or above
    the minimum) a bottom sheet over the app, at most once per launch:
    "A new version is available" / "Update GetWorkout for the latest
    fixes and features.", Update (the store; the sheet closes for this
    launch only) and Later. Later, a swipe down, a tap on the scrim or
    Back dismiss it for that `recommended_version_*` value for good
    (`app_gate.json` in the app support directory); a new value offers
    it again.
  - U3 Maintenance: while `maintenance` is true a page "We'll be right
    back" with `maintenance_message`, or "GetWorkout is down for
    maintenance. Try again in a little while.", and Try again, which
    fetches Remote Config at once (busy meanwhile) and opens the app if
    maintenance is off. Back does nothing.
  - When: `bootstrap` checks before `runApp` from what the last launch
    fetched (local only, so offline the app opens as before), then the
    rules are fetched in the background, on every resume and on Try
    again, ignoring the 12 h fetch interval; a failed fetch keeps the last
    rules. Only the gate's keys take a fetched value mid-session
    (`RemoteConfigRepository.refresh`); `paywall_layout` keeps one value
    per session.
  - The gate sits in `MaterialApp.builder` around the router: the app
    stays mounted and hidden under a page and comes back as it was. Its
    cubits start as usual underneath (auth, Firestore listeners).

### Exercises and content

- **Exercise sync**: clients read `exercises` of every status, so a
  retirement or a return to draft is noticed by the incremental sync on
  `updatedAt`, and filter to `live` on device. A cache whose document count
  differs from the server's `count()` is rebuilt with a full fetch.
- **Content ownership**: Firestore is the source of truth for content once
  it is seeded. `content/*.json` is the seed and the bulk-edit path;
  the admin panel edits Firestore directly and leaves `contentHash` alone, so
  the import skips (and fails on) documents edited there unless `--force`.
- **Exercise coverage** (`tool/coverage_report.dart`, logic in
  `tool/src/content_coverage.dart`): prints the live library by main and
  secondary muscle, equipment, equipment profile, level and pattern, the
  exercises without an alternative or variation, single-member families,
  near-duplicate names and text defects. Acceptance rule, from the
  generator since the SPEC gave no number: in every equipment profile,
  every muscle (any can be a focus) has at least `maxExercisesPerMuscle`
  (3, the most exercises a generated day gives one muscle, never repeating
  one) main-muscle exercises the generator may give a beginner, the
  smallest pool: level at most intermediate, not mobility or explosive,
  fitting through `equipment` or an alternative set. Exceptions, 2 each:
  bodyweight × mid delt (prone Y raise and the wall isometric; the presses
  are front-delt exercises) and bodyweight × forearm (dead hang, false grip
  hang). The script exits non-zero on a shortfall, and
  `test/tool/content_coverage_test.dart` runs the rule on the content files
  in CI. Seed after the audit: 416 exercises, 415 live (279 beginner, 104
  intermediate, 32 advanced); doable per profile: full gym 415, home gym
  240, dumbbells 180, bodyweight 123, bands 141. Hammer curls have main
  muscles biceps and forearm (brachioradialis is filed under forearm), and
  pike and handstand presses list mid delt as secondary like every other
  overhead press. The weekly-set warnings of the arm focus, glute focus,
  calisthenics and kettlebell programs stay: each is a focus or
  equipment-limited program whose summary says so.
- **3D model**: our own renderer, written in Dart, built first because it is
  the riskiest part. Source model has 37 meshes: 19 muscle groups (left/right
  split except abdominal and oblique) plus the body. A female model with the
  same mesh names is required before release; the user supplies it. The
  exercise page shows it twice, front and back side by side with the worked
  muscles coloured, both fixed (`interactive: false`, the back through a
  camera at yaw π) so the page scrolls over them; two CPU-rendered viewers
  share one parsed model and paint once. The Exercises tab's model stays
  interactive.
- **Equipment profiles**: one list, `EquipmentProfile` in
  `vocabulary.dart`, serves onboarding's quick picks and the catalogue's
  `equipmentProfile`. Full gym = everything; home gym = barbell, plates,
  dumbbells, bench, pull-up bar (a barbell at home implies a rack, which has
  no code); dumbbells = dumbbells and a bench; bodyweight = pull-up bar and
  dip bars; bands = resistance bands. Bodyweight is always available and is
  never stored. Profiles store only equipment codes, so changing a pick's
  equipment never touches stored data.
- **Custom exercises**: ordinary exercises everywhere the catalogue is
  listed (the catalogue cubit merges the signed-in user's in), marked
  "Custom". Ids are `custom_` plus a Firestore auto id, so they never
  collide with catalogue ids (`ex_...`) and an id alone tells which kind it
  is. They have no level, movement pattern or family: level and pattern
  filters never match them, and they have no alternatives or variations
  and are no one's. They sort first, by name, in popularity order. A name
  may repeat a catalogue name; the label tells them apart. Equipment left
  empty means unspecified and counts as doable with any. The form's
  check sheets take any ticks; bodyweight with other equipment is reported
  on the Equipment row when Save is tried. Deleting one also
  removes it from favourites in the same write; programs then show it as
  unavailable, like a retired exercise, and workouts keep their copy. Added
  to a program, one rests 90 s by default, having no rest of its own. The
  500 limit is checked by the app on create, counting what Firestore's
  cache holds (kept current by the catalogue's listener); rules cannot
  count.
- **Exercise list**: the Exercises tab opens on the interactive model (rotate,
  zoom, Front/Back, tap a muscle, or press and slide across muscles with
  its name and a haptic tick) under a search box. The box is an entry, not
  a field (Forge SearchField's tap-only pill): it opens the one exercise list
  page (`LibraryPage`, `/exercises/list`, declared before `:id`, inside
  the Exercises tab's stack, an explicit `MaterialPage` because go_router's default
  page for `builder` routes has no transition here), pushed above the model
  so back returns to the model as it was. The list page holds search,
  filters, sort, the count, favourite stars and, in its app bar only, the
  + for a custom exercise; there is no model on it. Opened from the box,
  its search field takes focus once the page's route animation has
  completed (one keyboard request, after the transition). The box and the
  page's search field share a ForgeSearchField heroTag
  (`librarySearchHeroTag`): only the grey pill flies, its width easing
  between the two ends; the filter button moves with its page. One
  gesture on the model opens one page: a muscle opens nothing while a page
  already covers the model. A muscle opens the same page at
  `/exercises/list?muscle=<code>`, without the keyboard. State: the list
  page and the model's page share the app-wide `LibraryCubit`, so search text, the
  filters set in the filter sheet and the sort last while the app runs (a
  user change resets them). A muscle chosen on the model belongs to that
  visit, held only by the page's location (its `muscle` parameter; the
  cubit holds the filter, nothing else): arriving makes it the only muscle
  filter and clears the search, the other filters and the sort staying;
  leaving the page (back, re-selecting Exercises, a `go` elsewhere) or a link
  to another muscle over it takes that muscle filter away again, unless
  the user already removed or changed the muscle filter, which then stays
  as they left it. So the box always opens without a model-chosen muscle.
  While the page's muscle is the only muscle filtered, the list shows its
  chip and switches between "Main" and "Also works" (a segmented control
  with each count), each in the list's order, so search, filters and sort
  apply inside them; removing the chip or adding another muscle gives the
  plain list, and one muscle picked by hand in the filter sheet is a plain
  filtered list. Opened from the pill the search starts empty (the
  filters and the sort stay); its field claims focus for the first frames
  after the page is in, since the route's own focus and the Hero's flight
  land after the first request. Every exercise list in the app is this
  widget (`LibraryListView`): one scroll view under the pinned search,
  the filters, sections, count and sort scrolling with the rows and named
  by the search's summary chip once out of sight (Egzersizler · 8 Y1 A);
  the exercise picker (`ExercisePickerPage`,
  for programs, the generator, the workout and workout history) uses it
  with its own cubit and no sections. The picker's route (`…/pick`) takes
  `max`, `multiple` and a `form` (`add`, `leaveOut`, `swap`, `replace`,
  with `exercise` and, for swap, `logged`); Add and Leave out open there
  from the root navigator, over the tab bar, while Swap and Replace open
  at the sibling `…/swap` inside their tab; each place declares the most
  its list holds (40 a workout, 20 a program day or a leave-out pick).
  `pickSwap` and `pickReplacement` open the Swap and Replace forms and
  return the picked exercise. "Create custom exercise" opens the form
  above the picker (`…/pick/new?name=`), which pops with the new id; the
  picker chooses it once the catalogue holds it (5 s at most).
- **Exercise detail** (UX pass, 2026-11-13, owner's pick; Egzersiz · 7):
  the app bar holds the name and ⋯, whose menu offers "Add to workout"
  (the workout in progress, else asking to start one), "Add to program",
  the favourite and, for a custom exercise, Edit and Delete, the same in
  every place the page opens (EB1 G). The body: the model
  (front and back) with Main muscles and Also works; for a custom
  exercise the "Custom" tag and its logging type; a card of facts
  (equipment with its alternative sets; for a catalogue exercise also
  level, mechanic, pattern, sides, logged as, also called); Setup and How
  to do it as numbered steps; Common mistakes, Safety and Cues as
  bulleted lines, each its own card; the custom exercise's Note, or on a
  catalogue exercise the user's own note ("Your note", stored in
  `users/{uid}.exerciseNotes`, trimmed, blank removes it); then one
  "Similar exercises" card: its total, then Variations and Alternatives as
  two groups with their counts and their first three names; a tap opens
  a sheet with every one by group (rows without tags, as the group names
  the relation), a row closing it and opening that exercise in the same
  tab. An alternative of the same family is listed once, as a
  variation. Anything an exercise lacks is left out, so a custom exercise
  shows the model, its tag, equipment, Note and nothing below. Records and
  progress left the page; an exercise's strength page opens from Progress.

### Programs

- **Programs**: a name of 1-60 characters, 1-7 days, day names of at most
  40 characters, 1-20 exercises per day, an optional length of 1-52 weeks;
  lengths count UTF-16 code units in the fields and in validation. The
  Firestore rules validate the top-level fields only (`name`, `days` count,
  `origin`); the app validates days and items. Items whose exercise's
  logging type changed are fitted to the new type when the builder loads
  them, and the user is told. The Programs tab (UX pass,
  2026-11-13, variant A) shows the active program first as one card: "Active
  program" and its name (a lock when it is a locked premium copy; a tap
  anywhere on the band but its ⋯ and day rows opens the program's page,
  with no chevron, Kararlar · 5), "Week n of N · <weekdays>" ("Week n" without a length,
  "Finished" once it ran its length; weeks count from the start date, as
  the length does, `ProgramSchedule.week`) with a progress bar when it has
  a length, the locked notice, then this week's days by date, each Done,
  Missed, Next or planned; no Start and no missed-day choices (Tabs P3,
  P4: Today's workout card starts the day and answers a missed one;
  another day than the next starts from its card on the program page).
  Then one card with three rows, the same with or without programs:
  ready-made programs, the generator (locked without premium) and "New
  program" (the builder); an empty workout starts on Today (P7). Then the
  other programs ("Your programs" without an active one; the weekly sets
  card is only on the program page, Kararlar · 5) under a
  SectionLabel, with their days and length. Without an active program the
  "No active program" prompt and the rows come first; no floating
  button.
- **Program page** (UX pass, 2026-11-13, variant B; Edit moved into the
  menu by the owner on 2026-11-15): a menu with Edit, Duplicate and Delete
  in the app bar; a summary card with the state
  (Active, Not active or Finished), length and day count, the weekdays and
  a days mismatch warning while active, then Start program, or Change days
  and Stop, or the premium lock (Start locked, or the active copy locked
  with Stop still allowed); then one card per day with its exercise count
  and estimate, ▶ to start that day (the premium gate for a locked copy;
  see Design › Program detail for the page's look)
  and a toggle that shows its exercises. Which days are open is the page's
  view state, never stored: the next day while the program is active, the
  first day while it is not; again from there once its days change (an
  edit may move them), and the next day opens once it moves on, e.g. on
  Start. The mismatch warning is hidden once the program finished. Each
  program id gets its own page (keyed in the router), so a copy opened
  from Duplicate never acts on the original. "Add to program" on an exercise without programs opens
  the builder: inside the Programs or the Exercises tab it is pushed above
  the exercise in that tab, and saving or leaving returns there
  (`Routes.programNewReturning` in Programs, `Routes.exerciseProgramNew`
  with its own picker in Exercises; `returningProgramNew` picks), so the
  exercise can be added; from a workout or the history it opens in the
  Programs tab as before. In the builder, + Day
  selects the new day and opens its Rename dialog; opening the builder or
  switching days never takes the focus.
- **Schedule**: `activeProgram.nextDate` is a calendar date stored as a
  `YYYY-MM-DD` string, so it is the same date in every time zone, and
  `startedAt` is a device-clock timestamp because starting a program must
  work offline. Every training weekday does the fixed program day
  `activeProgram.schedule` gives it, every week (2026-11-19: a 2-day A/B
  program on Mon A, Tue B, Thu A, Fri B); a day may be on several
  weekdays or on none. The next day (`nextDayIndex` on `nextDate`) comes
  first; after it each training weekday does its own day
  (`ProgramSchedule.upcoming`), so finishing a day plans the first
  training weekday after it with that weekday's day, whichever day was
  done. A day moved to another date (Do it today, Move, the calendar's
  move) keeps its own day there, in place of that date's own day, which
  is left out that time; the weekdays after it do their own days again
  (owner's pick, 2026-11-19). Moved earlier in its week with the
  calendar's move, it takes its own date along (owner's pick, 2026-11-19):
  Thursday's A moved to Wednesday leaves Thursday a rest day this week,
  and the weekdays after Thursday do their own days
  (`activeProgram.movedFrom`, cleared once the next day is planned anew).
  Moved later, the training weekdays in between are left out.
  A missed next day stays the next day until the user does it today,
  moves it to the next training weekday or skips it (the first training
  weekday from today then does its own day); meanwhile it is planned on
  the first training weekday from today, and the week plan shows it
  once, on its date, as missed. Starting a program plans the first
  training weekday from today with its day; when that is today and the
  day was already done today (a workout of that program and day started
  today) it counts as done, as finishing it would have, and the next
  training weekday comes next (`StartProgram` reads today's done days).
  Changing the training days replans the next day as the new schedule
  gives it, from today (from tomorrow when it was planned after today,
  as today's day may be done). A schedule naming days the program no
  longer has keeps them inside it (index modulo the day count) and the
  program page asks to change the training days. A program with a length
  ends that many weeks after its start date.
- **Catalogue rules** (`lib/features/programs/domain/catalogue_rules.dart`):
  every catalogue program must pass the app's own `validateProgram`, and
  its session lengths are the app's `estimateDay`. On top: every exercise
  fits the program's equipment profile (through `equipment` or an
  alternative set) and is at most one level above the program (no advanced
  exercise in a beginner program); `equipment[]` is computed from the
  exercises' primary equipment; live programs are exactly 6 free and 19
  premium. Weekly sets per major muscle (pec, lat, mid delt, biceps,
  triceps, glute, quads, hamstrings) are warned about outside 6-12 for
  beginner, 10-18 for intermediate and 12-20 for advanced programs. These
  bands are narrower than the 10-20 reference band of the volume screen
  because they describe what a program of one level should prescribe,
  while the screen judges any week of any user. Focus programs and
  equipment-limited ones exceed or miss a band on purpose and say so in
  their summary.
- **Catalogue in the app**: clients read the whole `programs` collection,
  every status, and keep the live cards on device by `order` (no composite
  index; offline from Firestore's cache after the first load). A premium
  program's days are read only once the user is known to have premium; days
  the rules refuse to a user with premium show "unlocking" and are read
  again three times (after 2, 4 and 8 s), then on Retry, since the
  entitlement may not have reached the server yet; a refused free program
  is a failure. Days read under an earlier premium status are dropped.
  "Start this program" waits for the exercise library and the user's
  programs, and is blocked with a message when a day uses an exercise no
  longer in the library (copying without it would change the program).
  After the copy offer, the replace confirmation and the Training days sheet it
  copies the program into `users/{uid}/programs` (`origin: catalog`,
  `sourceId`, `premium` for a premium one) through the builder's
  validation, starts the copy and opens it; when a copy from the same
  `sourceId` exists, it is offered first. Duplicate copies it the same way
  and opens the builder on the copy. The card's `dayList` (each day's
  name and exercise count, computed from the days like `minutes`) lets a
  locked premium program list its days. An
  exercise opened from a ready-made program opens its alternatives and
  variations inside the Programs tab. Recommended for you: never a program
  above the user's level (beginner while unanswered) or needing equipment
  they lack (a program fits when the user owns all its primary `equipment`
  or all of its equipment profile; an unknown code or a missing list is
  not owned); while their equipment is unknown nothing is claimed to match
  it and "Fits my equipment" filters nothing. The rest score 3 for the
  goal, 2 for the level, 2 for the days per week (1 for a day more or
  less); the top 3 show, ties in catalogue order, free programs first
  unless the user is known to have premium. After onboarding the best
  free recommendation is offered (save it, or browse); with none, or
  the catalogue offline, onboarding lands on Today, and so does signing in
  from onboarding to an account already onboarded.
  `ProgramsModule` takes the premium status and the premium action as
  parameters, so programs never import the subscription feature; bootstrap
  passes `SubscriptionModule.premiumStatus` (the app-level
  `EntitlementCubit` as unknown / free / premium) and
  `SubscriptionModule.showPaywall`. The program cubits follow that status,
  so a page updates by itself once the paywall grants premium; pages get
  the premium action from their page widget, never from `sl`.
- **Ready-made programs page** (UX pass, 2026-11-13, variant B; the
  screen step, 2026-11-15): a search by name, then the filters as chips
  scrolling sideways: "Only my equipment" (toggles in place; while the
  equipment is unknown it opens the sheet, which says why), then for
  Level, Days per week, Goal and Equipment each chosen value as a
  removable chip (removing it turns that value off) or, with none chosen,
  the filter's name with ▾; a chip opens the filters sheet (no filter
  action in the app bar). While filtering, "n filters on" (each chosen
  value counts one, `CatalogueFilter.activeCount`) and Clear. Otherwise
  the best recommendation as one row and the count, then every program
  as ProgramCard's row form: name with Fits you (`TrainingProfile.suits`:
  the user's goal, level and days per week) or the Premium tag while
  locked, "days · level · length". The post-onboarding suggestion shows
  ProgramCard's card form.
- **Copies of premium programs** (decided by the user, 2026-11-11): a copy
  of a premium ready-made program is marked `premium: true` and keeps the
  mark through edits and duplicates. Without premium it stays visible and
  readable but cannot be started, rescheduled or trained; an active one
  shows as locked in the Programs tab and is not stopped, so it resumes
  when premium returns. While the premium status is unknown these actions
  wait. `programAccess` is the one check, also for starting a workout
  from such a program (Start <day> in the Programs tab, ▶ per day on the
  program page): locked opens the paywall and starts only if premium was
  bought; `ActiveWorkoutCubit` refuses it too. A workout in progress from
  it can always be finished; free workouts are never gated. The gate is client-side only: the copy lives in the user's
  own collection, and the rules only check that `premium` is a boolean.
- **Program generator** (`lib/features/generator`): pure Dart on the device,
  the same program for the same answers, library and seed; Regenerate takes
  the next seed. Questions: goal, level, 2-6 days (onboarding's range),
  session of 30/45/60/75/90 minutes (60 preselected), equipment (presets or
  items), up to 3 focus muscles, exercises to leave out (from the picker),
  one area to go easy on (shoulders, elbows, lower back, hips or knees, each
  a set of muscles) and the split; goal, level, days and equipment are
  prefilled from the profile. Splits: full body, upper/lower, push/pull/legs
  (3+ days; 4 adds an upper day, 5 upper and lower); "best for my days" is
  full body for 2-3 days, upper/lower for 4, push/pull/legs for 5-6
  (upper/lower for beginners). Weekly targets: 10/14/18 sets by level for
  the catalogue's major muscles (inside the 10-20 band and each level's
  catalogue band), half for calves and abs, +4 (at most 20) for a focus
  muscle, none for the area to go easy on (which wins over focus); other
  muscles are worked only through these exercises, and no trained muscle
  passes 20. Exercises: live catalogue ones only (a custom one has no
  level), fitting the equipment through `equipment` or an alternative set,
  at most one level above the user (the catalogue rule), never mobility or
  explosive patterns, never left-out ones, never with the area's muscles as
  main muscles and, where another fits, not as secondary ones either;
  compound first for quads, pecs, lats, hamstrings and glutes, isolation
  first for the rest. Each day's next exercise goes to the muscle furthest
  short of what it still needs that week (secondary work counts), so short
  sessions share the time fairly. Reps: strength 4-6 (isolation 8-12; exercises without
  a load get the muscle range), muscle 6-10 / 10-15, fat loss 10-15 / 12-15
  with rests capped at 60 s, general 8-12 / 10-15; timed exercises 30/40/45 s
  by level; rest is the exercise's default. 2-5 sets an exercise (4 at most
  for beginners), up to 10 exercises a day, each day within the session by
  `estimateDay`; weekly sets reach the targets as far as the days and
  sessions allow. Answers that give no program (days out of range, a split
  needing more days, a day no exercise fits) get a typed reason, not an
  empty program; a trained muscle no exercise of the week works directly
  (none fits, or none fitted the sessions) is named on the preview.
  Saved as the user's own (`origin: generated`, "<split>, <n> days", days
  "Upper A", ...), editable like any other and never marked `premium`:
  Premium gates the generator, not the programs it made. Its entry is on
  the Programs tab for everyone, locked when free, and opens through
  `requirePremium()`; it is a feature of its own, so the programs feature
  still never imports the subscription one (the tab only shows its entry).
  Layout (UX pass, 2026-11-13): the questions are laid out as onboarding's
  (one per page, Back and the progress segments with "n / 9" in the app
  bar, "Generate a program" above the question, the answer near the
  thumb, Continue or "Create my program" at the bottom; Back on the first
  question leaves), full screen above the tabs (`/generate`). The preview: split and summary, the uncovered muscles
  as a card, a Weekly sets card with each target muscle as a plain bar
  filled to its own target (full once met) and "x of target", then the days as the
  program page's day cards (`ProgramDayCard`, without ▶), the first open
  and again after Regenerate; Regenerate and Save fixed at the bottom.
  Design phase (2026-11-17): "Upper/lower · 4 days" over "Build muscle ·
  Intermediate · 60 min"; uncovered muscles as NoticeBanner's one-line form; Weekly sets
  as a SectionCard with "n total" and a VolumeBand "n sets" per target
  muscle (GP-Q4, replacing "x of target"); each exercise "3 × 6–8" in mono with
  ⋯: Swap for a similar one (the picker's Swap form, `/generate/pick`;
  sets, rest and the kept mark stay, an exercise already on the day is
  ignored) (GP-Q2), Keep when regenerating (history icon, ticked; the row
  shows an accent "Kept" after its reps) (GP-Q1), Change sets and reps (the builder's targets
  sheet, `ItemTargetsSheet`) (GP-Q3), Remove (not the day's last).
  Regenerate keeps the kept items on their day as they are: they count
  towards the targets and no pass trims them; one gone from the library
  is dropped. Edits recount the weekly sets and uncovered muscles. While
  building, a "Building your program" card and both buttons off; Save
  reads "Save program".
- **Admin program editor**: edits `programs/{id}` and its `detail/main` in
  one transaction, so both are written or neither; a save is refused when
  either changed since the editor loaded them, and keeps `contentHash` and
  unknown card fields, as the exercise editor does. Typed in: id, status,
  premium, order, level, goal, equipment profile, length, name and summary
  per language of `languages`, and the days. `daysPerWeek`, `equipment` and
  `minutes` are computed from the days on save and shown read-only, so they
  always match the rules. Every save, drafts included, must pass
  `programProblems` and have an unused id and a unique name and order, as
  the import rejects an invalid file whatever its status; the 6 free / 19
  premium split of live programs shows as catalogue health and never
  blocks, nor do the weekly-set warnings. The picker offers live exercises;
  a new item takes the builder's defaults and the exercise's rest. A save
  drops unknown fields inside days and items (the import rejects them too).
  Readers take a whole double as an integer. Panel strings are English
  literals like the rest of the panel (`lib/main_admin.dart`).
- **Program progress**: doing another day of the active program shows it as
  done but leaves the schedule. Done days are read from workouts by date
  only, so no composite index is needed.
- **Add to program**: an exercise's page appends it, with the default
  targets, to a day of one of the user's programs through the program's
  validation; a full day cannot be picked, and without programs it offers to
  create one.
- **Save as program** (offered on a program workout's summary too, owner's
  pick 2026-11-15): a workout becomes a one-day program of the
  user's own: its working sets, the rep range done or the longest duration,
  the heaviest weight (least assistance) as target, the exercise's default
  rest (90 s for a custom one). Exercises no longer in the library are left
  out; a program that would not be valid (over 20 exercises) is refused.

### Workout

- **Starting a workout**: the Programs tab and Today start the next
  day, a program's page any of its days, the Programs tab also an empty
  workout (Today only while there is no program day to do), and an
  exercise's page adds it to the workout in progress or, after
  asking, starts one with it. With no program day to do, Today's card
  points a user who has programs of their own at them: "Choose a program
  to start", "You have 2 saved programs. Start one to set your training
  days.", "See your programs" opening the Programs tab (K14 B); without
  any it still offers the ready-made ones. A program day waits until the user's custom
  exercises are loaded; exercises really gone are left out and the user is
  told how many. A workout left open ends itself (K1 B): the device keeps
  when its last set was ticked (`LocalWorkouts.lastSetAt`, never in
  Firestore); 4 hours (`workoutIdleLimit`) after it, or after the start
  with no set done, the workout is stored ending at that last set, or,
  with no set done, thrown away. A local notification (id 4, the
  `workout` channel, shown only where notifications are allowed) is
  scheduled for that moment and moved with every set: "Full Body A ended
  at 14:20" / "It was open 4 hours with no new sets, so we saved it at
  your last set: 52 min.", or "… was removed" / "It was open 4 hours with
  no sets logged, so nothing was saved." It ends while the app runs (a
  timer), when the app comes to the front, or when it next starts; a
  finish by hand or a discard cancels the notice. The summary of one that
  ended itself opens by itself above the open pages and has Edit as a
  text action at the AppBar's top right, which closes the summary and
  opens the workout in the editor (`/today/workouts/:id/edit`) (L1 B).
  Starting while a workout is in progress asks to resume it
  or discard it.
- **Empty workout**: a workout with no exercise (`Workout.isEmpty`; with
  none there is no set, ticked or not, and a note alone does not count) is
  open but not in progress (`ActiveWorkoutState.inProgress`): no bar in the
  shell, not kept in the local file (an empty one kept by an older version
  is dropped on load), no rest (`Rest.followEdit` ends it), never stored,
  and starting another simply replaces it. Leaving its page (back or
  minimize) ends it through `ActiveWorkoutCubit.leave`, and Discard or
  Finish end it, all without asking. A free workout starts empty and is in
  progress from its first exercise; a program day (or an exercise's page)
  starts with exercises, so it is in progress at once; removing the last
  exercise makes any workout empty again.
- **Workouts on the device**: per user one JSON file
  (`workouts_<uid>.json` in the app's private support directory, versioned)
  holds the workout in progress, finished workouts the server has not
  confirmed yet, and the exercises whose stats need rebuilding. It is
  rewritten after every change (only the latest of a burst, replaced
  atomically, so moving a workout from in progress to finished is one
  write) and read on launch, the workout in progress behind the minimized
  bar. A user never gets another's. A file that cannot be read, or of an
  unknown version, is renamed `.unreadable-<time>`, never overwritten, and
  the user is told. A file outlives Firestore cache eviction and costs no
  write per keystroke. The workout id is made at the start, so storing a
  workout twice stores it once.
- **Logging a set**: empty fields show a suggestion, which ticking takes;
  each value comes from the first that has it: this workout's previous done
  set of the same type and exercise, the same working set last time, the
  program target (weight, bottom of the rep range, duration). A warm-up only
  follows the warm-up before it. A done set edited into an invalid one is
  unticked. A weighted or assisted bodyweight set without a weight has none
  added. Effort is a whole number: RIR 0-5 (5 means 5+) or RPE 10 down to "6 or less", see
  Effort scale. Sets
  take a note of up to 200 characters. Durations are typed in seconds; a
  minutes and seconds input is left to the design phase.
- **Workout screen**: shared by the workout in progress and editing a
  stored or past workout. One card per exercise, or per superset/circuit;
  only the card of the selected set is open (name, goal, last time, note,
  the menu, whose "Exercise details" opens the exercise's detail page), the
  others show "Squat · 1/3" (working sets only, as "of N" counts them)
  with the menu still there, and tapping one
  opens it on its first undone set, else its last. Holding an exercise's
  header (not its menu) as long as a long press collapses every card to its
  one-line exercises, the held line scrolled back under the finger; only
  once that is laid out does the drag start (the header's recognizer waits
  for the cards to open its gate), so the dragged card and its gap are one
  line, and the card (a superset or circuit as one, never split or dropped
  inside another) follows the finger; once dropped (`moveBlock`,
  `grouping.moveItem`) the cards open again with the same set selected.
  Moving first scrolls instead; every pointer end (lift, cancel, the app
  leaving) ends it, and the cards expand when the drop is applied or at the
  latest 500 ms after the finger lifts. Headers cannot be held while cards
  are collapsed (a drop still landing) or while edits are refused (saving,
  finishing). Collapsing is local state of the cards; the drag uses
  `SliverReorderableList`, its proxy a freshly built one-line card with the
  page's providers re-provided. Screen readers get "Move up" / "Move down"
  actions on the headers. The workout note and "Add exercise" stay below,
  not draggable. The selection is presentation state in
  the editor cubit (`SetSelection`, `set_selection.dart`): until something
  is picked it is the next set to do (`nextSet`, which knows supersets),
  else the first exercise; ticking moves it to the next set to do (the
  exercise's last set opens the next exercise with undone sets, a finished
  round of a group goes to the next round's first exercise), unticking or
  an invalid tick keeps it; an added set is selected; removing or moving
  sets and exercises keeps it on its set or exercise (removing the selected
  set selects the one that took its place, else the one before; removing its
  exercise falls back to the next set to do); skipping the rest leaves it.
  The pick (the set or exercise the user last picked or opened, or where a
  tick moved it) is kept with the workout in progress in the local file
  (optional `picked` field, still version 2; one that no longer points
  into the workout is dropped), so each time the workout page opens (from
  the minimized bar, Today's "Resume workout", a lock-screen or
  notification tap, or a relaunch) it goes on where the user left it
  (owner, 2026-11-19; it used to reopen on the next set to do). Opening
  the page (`pageOpened`) drops an effort question left in the bar (its
  tick started no rest) and an invalid tick's message; one in the rest
  strip stays while its rest runs, as the minimized bar shows that rest.
  The edit page is unaffected.
  The open card shows its sets as **bubbles** (the owner's pick; the
  "selected set only" view was tried and deleted): a wrapping row of round
  bubbles, a warm-up dashed with "W", a drop set "2D", done ones filled without a tick (owner's pick), the
  selected one in the theme's selected colours, a "+" bubble; a group
  stacks one row per exercise, labelled A1, A2, warm-ups first, then one
  column per round with the round's bubbles joined. Tapping a bubble
  selects its set; long-pressing it opens a menu at the bubble listing
  Warm-up, Working and Drop set (the ones it can be) with the current one
  ticked, then "Remove set" (owner's pick, Çelişkiler, 2026-11-15; also custom
  screen-reader actions), the same as the bar's "more" sheet. Adding a set
  asks Normal / Warm-up / Drop set (a drop set only for rep-based
  exercises); a warm-up goes after the existing warm-ups, other sets at the
  end, all empty with the usual suggestions as hints. Changing a set's type
  keeps warm-ups first: a set made a warm-up moves to after the other
  warm-ups, a warm-up made a working set becomes the first working set,
  normal and drop sets stay in place (`retypedSetPosition`); the selection
  follows the moved set, and a running rest forgets the set it followed as
  for any move. The **set bar** sits at the bottom of the page above the rest
  strip and the safe area; typing a value, the keyboard carries Forge
  StepperField's Next / Done bar: Next types the following value (weight,
  then reps, then a drop's values in order; greyed on the last), Done
  closes the keyboard, and one tap on another value moves the typing there
  keeping what was typed (K2 A+B); while the keyboard is up the rest strip steps
  aside (still mounted) so the bar sits right on the keyboard, the list
  above shrinks and stays scrollable, and the selected bubble is
  scrolled into view. It shows the selected set ("Squat · set 2 of 3", last
  time, the set note), its fields by logging type with
  the suggestion as hint, a drop set's drops (edit, remove, add) right
  under them, the effort steps, the tick (which needs no keyboard and starts
  the rest as before) and a "more" sheet (following the selection, so a type change that moves the set keeps it on that set) for the set type, note and
  removal; an invalid tick's message shows in it. Sets are named
  everywhere by `setLabel` and `setToDo` (W, 1, 2D; "of N" counts working
  sets), the same as the lock screen and the rest notification. The exercise detail page
  opens above the workout (`/workout/exercises/:id`, and
  `/progress/calendar/exercises/:id` above the edit page), so back returns
  to the workout as it was.
- **Effort scale**: optional per set, picked in the set bar (picking the
  chosen step again clears it). Settings → "Effort question" ("Asked
  after each set you log."): Off first, then "By feel (default)" ("Easy,
  moderate, hard or max"), "RIR · reps in reserve" ("0, 1, 2, 3 or 4+
  reps left") and "RPE · rated effort" ("From 6 or less up to 10") (E1 B)
  (`settings.effortScale` codes `feel`, `rir`, `rpe`, the older `off`
  reading as by feel; Off is `settings.askEffort` false, which only stops
  the question: efforts are still shown and picked in the kept scale, and
  picking a scale turns the question on again) (L4 A). A choice setting
  marks its default option "(default)": the effort and the rest sound
  ("Chime · vibrate (default)"); units (from the device's region), the
  default rest and the week start are not marked, as the board draws
  them. Every scale is
  stored the same way, as RIR (`rpe = 10 - rir`): by feel Easy ("4+ reps
  left") stores 4, Moderate ("2–3 left") 2, Hard ("1 left") 1, Max ("0
  left") 0, and a stored RIR shows as Easy from 4, Moderate at 2-3, Hard at
  1, Max at 0. RIR offers 5+ down to 0; RPE offers "RPE 6 or less"
  (stores RIR 4, and a stored RIR of 5 shows as it), then 7 to 10, so RPE 5
  is no longer a choice (UX pass, 2026-11-13). Every scale ends with "Failed" (the last rep was attempted
  and not completed), stored as `toFailure` with RIR 0; there is no separate
  failure switch, and any set with `toFailure` shows Failed whatever its
  RIR. Effort shows in the chosen scale everywhere (bar, workout detail).
  Effort is only stored and shown (bar, workout detail); nothing else uses
  it yet, and the help says just that. Effort is only asked about a DONE
  working set; warm-ups are never rated. Right after a working set is
  ticked in the workout in progress it is asked in one of two places
  (owner's design pick, superseding both places below: it is asked in the
  set panel as rows with their one-line meaning while the rest runs as a
  thin line above (time, +15 s and Skip rest); the question has no Skip
  (owner, 2026-11-18); once answered the panel becomes the large
  countdown with +15 s and Skip rest, and the next set's entry returns when
  it ends; the rest strip is not on the workout screen):
  - **Its tick started a rest** (`restStartedBy`, `askingWithRest`): in
    the rest strip, under the countdown with +15 s and Skip, one line
    naming the set with its values and the scale's short question ("Set 1
    · 80 kg × 8 — how hard?", "… — reps left?", "… — RPE?", the exercise
    first when the selection is on another one), the "?" help and the
    steps with Failed. The set bar meanwhile shows the
    next set as usual, so its weight can be set during the rest. It lasts
    as long as that rest (`restQuestionSet`: the rest still that set's and
    running, so "+15 s" extends it): gone when the rest runs out or is
    skipped, when a step is picked (stored on that set; the countdown
    stays), another set is ticked (its own question replaces it), any set
    is unticked, any edit moves sets (adding a warm-up before, removing or
    reordering sets or exercises), or the workout finishes. A rest kept
    over a relaunch brings no question. The strip takes at most 40 % of
    the bottom area (`SetBarLayout.maxBelowShare`, the bar keeps the rest):
    its countdown always shows, the question and the first-use tip scroll
    under it. Picking
    another set or opening an exercise leaves it. Opening the help changes
    nothing; a rest ending meanwhile leaves the sheet open and the
    question gone. The strip, and so the question, steps aside while the
    keyboard is up.
  - **It started none** (rest timer off, a set mid-round in a superset):
    the set bar becomes the question (`questionSet`): "Set 1 done · 80 kg
    × 8" ("Drop set 2 done · …", the exercise first when the selection
    moved on: "Squat · Set 3 done · 100 kg × 5"), the scale's question
    ("How hard was it?", "How many more reps could you have done?", "How
    hard was it, from 1 to 10?") with the "?" help and the steps with
    Failed; no fields and no tick, the keyboard already closed by the
    tick. The bar returns to the next set when a step is picked, any set
    is picked or an exercise opened, an edit moves sets,
    with or without a rest; it has no timeout (K18 B). Leaving the page
    drops a question whose tick started no rest.
  Neither shows while edits are refused (finishing), and an answer refused
  then leaves it open. Editing a past workout never asks on a tick. A
  selected done set shows its effort row under its values, named: "Set 1 ·
  how hard was it?" (`effortRowSet`); an undone set never has one. The
  bar then takes its own height instead of its 60 % of the page
  (`SetBarLayout.fullHeight`), so the steps show without scrolling; it
  scrolls only when taller than the page (large text).
- **Automatic warm-up sets**: Settings → "Automatic warm-up sets" (its
  row shows e.g. "Standard · Every exercise") opens a page
  (`/profile/warmups`) with:
  - **Scheme**: Off, Light (60 % × 6), Standard (50 % × 8 · 75 % × 4,
    the default, also for users who never chose), Full (40 % × 8 · 60 % ×
    5 · 80 % × 2) or Custom; each preset shows its sets. Custom lists its
    sets, each a percentage (10-95) and reps (1-20) checked as typed with
    the app's usual "Enter a value from … to …"; an invalid field is not
    kept until fixed. A set can be removed (not the last) and "Add warm-up
    set" appends one (up to 5) midway from the last to 90 % (on 5 %) with
    half its reps (`nextWarmupStep`). Custom starts, the first time, from
    the scheme chosen then (Standard's sets from Off) and keeps its sets
    while another scheme is chosen. Sets stay in the order entered (they
    are a sequence the user builds; nothing re-sorts rows under the
    finger), and warm-ups follow them by position.
  - **Which exercises**: every exercise, or the first exercise for each
    muscle group: an exercise gets warm-ups only when no exercise before
    it in the workout that is itself done with a weight and reps
    (`weight_reps`) has the same main muscle (the first of its
    `mainMuscles`, the 19 muscle groups of the vocabulary; one without any
    is a group of its own); push-ups before bench press or a plank before
    loaded core work do not count, a loaded one counts even if its
    warm-ups were deleted (`warmupsAllowed`). Decided as it enters the workout (a program
    day in day order, superset members one after the other; one added or
    swapped in against the exercises before it); reordering later adds or
    removes nothing (`warmedUp`, `warmedUpAll`).
  - Rounding stays the fixed 2.5 kg / 5 lb step.
  Stored as `settings.warmups` (`scheme` code `off`/`light`/`standard`/
  `full`/`custom`, `custom` [{`percent`, `reps`}], `scope` `every`/
  `firstPerMuscle`); without it the old `settings.autoWarmups` reads false
  as Off, true or missing as Standard. `autoWarmups` is still written
  (false only for Off) so app versions before the schemes keep a matching
  switch; they ignore `warmups` (unknown keys are not read), and a switch
  flipped in such a version wins: this app writes both in agreement, so
  when they disagree an older version wrote last (`autoWarmups` false
  reads as Off whatever the scheme, true with Off as Standard). Malformed custom sets
  are dropped or clamped; Custom without sets reads as Standard.
  Exercises logged with a weight and reps (`weight_reps` only: weighted
  and assisted bodyweight, reps-only and timed exercises get none) start
  with one empty warm-up per set of the scheme before their working sets
  when they enter a workout in progress: a program day started, an
  exercise added (also to an empty workout, and "start with this
  exercise"), or swapped in while none of its sets is done (the selection
  then opens its first warm-up). A swapped-in exercise is judged against
  the exercises before it: its untouched warm-ups (nothing entered, not
  done) go when it may have none there (a type that takes none, or the
  muscle-group rule refusing them; `withoutUnusedWarmups`), and come when
  the rule grants them. The scheme and the unit are the user's own
  settings: a program day waits for them (up to the catalogue wait); while
  they have not arrived, or cannot be read, nothing gets warm-ups and
  warm-ups suggest no ramp (never a ramp in a unit not known yet). Never
  on a past workout (edited or added by hand), never to exercises already
  in the workout when the setting changes, and none when the exercise
  already has a warm-up or they would pass the set limit. There is no
  "repeat a workout" yet; a workout saved as a program starts as a
  program day. The warm-ups' values are suggestions, like any set's:
  warm-up n follows the scheme's set n (past the last, the last; with Off,
  hand-added warm-ups follow Standard's), its percentage of W for its reps
  (`rampedWarmup`), W being the first working set's weight as typed, else
  as suggested; rounded to 2.5 kg or 5 lb in the user's unit, never below
  one step nor above W. They follow W until typed over or ticked; while W
  is unknown (or 0) they fall back to the usual warm-up rule (the warm-up
  before it), normally empty. In the workout in progress this applies to
  every warm-up of a `weight_reps` exercise, added automatically or not;
  editing a past workout keeps the plain rule. Warm-ups keep their meaning
  everywhere (no stats, volume, records or "of N", no rest).
- **1RM**: Epley, `weight * (1 + reps / 30)`; sets above 12 reps are ignored.
- **Swapping an exercise**: the same logging type keeps the sets, another
  gets as many empty ones; up to eight alternatives are offered before the
  whole library. With some sets done, only the sets not done move to the
  new exercise, placed after the old one, which keeps its done sets
  (`swapKeepingLogged`).
- **Workout limits**: name 1-100 characters, note 1000, exercise note 500,
  set note 200, 40 exercises, 30 sets each, 5 drops per set. The rules
  validate the top-level fields of `workouts` and `exerciseStats` (allowed
  keys, types, sizes); the app checks sets before storing.
- **Rest timer**: ticking a set starts a rest of the rest chosen for the
  exercise in this workout (exercise ⋯ › Rest time; `WorkoutExercise.restS`,
  kept on a group's last exercise and, like the goal, only in the local
  file, never with the finished workout), else its program item's
  `restS`, else the exercise's `defaultRestS`, else the user's default
  (`settings.restTimer`: `enabled`, default on; `defaultS`, 90 s, 15-600;
  `notify`; `alert`), which the workout cubit follows itself. A rest of 0 is none.
  In a superset or circuit rounds count working sets (warm-ups belong to
  no round, so a warm-up on one exercise shifts nothing), and only the
  group's last exercise with a working set in that round starts the rest,
  for the rest of the group's last exercise (as the program estimate
  counts it); the next set follows the same rounds, the group's warm-ups
  first. The workout's last set to do starts none and ends a running
  one, as nothing is left to rest for (rests between exercises stay).
  Warm-ups start none and leave a running one alone; a drop set
  rests like any set. Rest start and end are decided in one place, from
  the workout before and after each edit: a new tick replaces the running
  rest; the set that started it no longer done (unticked, or edited
  invalid) ends it; an edit that moves sets (remove or move an exercise,
  remove a set) keeps it running unlinked. Finishing, discarding and a
  user change end it. The rest is its end time on the device clock, kept
  with the workout in progress in the local file (optional `rest` field,
  still version 2), so it survives minimizing, backgrounding and
  restarts. A rest ending more than 30 min ahead (600 s plus "+15 s"
  room; "+15 s" never goes past it) is not believed: dropped on load, and
  not run when the clock was set back. A damaged `rest` in the file is
  dropped, a set position not in the workout forgotten; the workout is
  never set aside for it. One that ended while the app was away ends
  quietly; one that reaches zero in front of the user buzzes and shows
  "Rest over" for 3 s. +15 s moves the end. −15 s (the Live Activity's
  button only) moves it earlier and ends the rest when 15 s or less is
  left; a rest moved either way keeps its start, so its bar and the
  panel's progress do not jump.
- **Rest notification**: local, scheduled only when the app hides and
  cancelled when it shows or the rest ends, since the notifications
  package cannot hide one over the app in front. A rest moved while the
  app is hidden (a Live Activity button) reschedules it in place, never
  cancelling it first, so a suspension in between cannot leave none; the
  calls run one after another, each for the state when it runs, so a
  late one cannot undo a newer change. A rest left running when the
  app is killed in front gets none. The wish is the user's
  (`settings.restTimer.notify`, written only by their answer or the
  settings switch); the permission is the device's and is never written
  to Firestore. On a device not asked yet, tapping Start on a workout
  (any start: program day, empty, from an exercise) asks in the app
  first, "Get alerts when rest ends?" (a Forge `PermissionPrompt.dialog`,
  S7; closing it is a Not now), before the workout opens (K3 B),
  only while the rest timer is on, unless they said no or said yes and the
  device already allows it; the system is asked only after "Allow", never
  on its own. "Not now" is remembered on that device only (a marker file
  in app support), so other devices still ask; a device refusal leaves
  the wish, so devices that allow it still notify. "Allow" then asks, on
  Android, for exact alarms (without them the notification falls back to
  an inexact alarm, possibly late). The rest notification has id 1 on one
  Android channel, `workout` ("Workout", high importance).
- **Workout on the lock screen**: the workout in progress is on the lock
  screen, drawn by the system so its times run without the app
  (`RestTimerCubit` through `ShowWorkoutOnLockScreen` /
  `ClearWorkoutFromLockScreen`; `WorkoutLockScreen` with an iOS and an
  Android adapter). It follows `ActiveWorkoutState.inProgress`: shown from
  the first exercise (an empty workout shows nothing) until the workout is
  finished or discarded, or the user changes or signs out; kept while
  finishing. Nothing is shown or removed until the workout is loaded at
  start, then one left from an earlier run is updated to the workout in
  progress or removed. A running rest is shown instead of the workout while
  `settings.restTimer` is enabled (the workout itself shows whatever that
  setting says). Rest: title "Rest" and the next set as in the rest
  notification (none when nothing is left); workout: its name, the elapsed
  time since `startedAt`, and the set to do now ("Bench Press · set 2 of
  3", "Bench Press · Warm-up 1 of 2", "Bench Press · Drop set 2 of 3", as
  `setToDo` names it; none when every set is done). The rest notification
  and the lock screen's line after the rest name the next set the same
  way ("Next: Bench Press · set 2 of 3"; `restNextText`). The set column
  names sets by `setLabel` (W, 1, 2D). The set
  to do now is the next one (`nextSet`) after the set ticked last in this
  run of the app, whatever became of its rest (skipped, or none with the
  rest timer off), forgotten when that set is unticked or no longer done
  after an edit; after a restart, after the kept rest's set. The rest is
  replaced on +15 s or a new rest and turns back into the workout when it
  is over, skipped or unticked. It is silent whatever `notify` says: the
  end is announced by the rest notification (id 1) alone, so nothing
  alerts twice. A show or removal that fails (also iOS with Live
  Activities off, or before the app may start one) is logged once and the
  same content is not tried again until the app shows again; content that
  changes is tried at once.
  Android: ongoing, silent notifications on their own channel `rest`
  ("Workout in progress"; the id is from when it showed rests only;
  default importance, no sound or vibration; lower importances count as
  silent and may be hidden on the lock screen), whose system chronometers
  run without the app, one at a time: the workout, id 3 (title its name,
  text the set to do now, counting up from `startedAt`;
  `Notifications.showStopwatch`), or during a rest the rest, id 2 (title
  "Rest", the next set, counting down, with a timeout at the end so the
  system removes it even with the app killed; `showCountdown`). When a
  rest starts the workout is taken off and scheduled back for the rest's
  end (`scheduleStopwatch`, exact when the device allows exact alarms,
  else possibly late, with nothing shown meanwhile but never a stale
  countdown), so it returns while the app is suspended or killed; under
  its own id because a notification replaced as the countdown times out
  could be removed with it, so the two never race. +15 s replaces both;
  a rest cut short (skip, untick, rest timer off) drops the scheduled one
  and shows the workout at once; once the rest is over in front the app
  does the same. Both are replaced in place, never updated per second
  (posted again only when what they show changes), and ask for promotion
  to a Live Update (Android 16 status bar chip,
  `POST_PROMOTED_NOTIFICATIONS`). A tap opens the app with payload
  `active-workout`, handled like the iOS Live Activity's tap (below). A
  separate id from the end alert (1) because that one is scheduled only
  while the app hides and cancelled when it shows, and these stay across
  both. They need the notification permission and never ask for it:
  without it nothing shows, and they show at once when the user allows
  notifications mid-rest. They are ongoing, so they cannot be dismissed on
  the lock screen; no foreground service (nothing has to run: the
  chronometers, timeout and alarm are the system's, and a service would
  need a declared type and Play review), so from Android 14 the user can
  swipe them away while unlocked, until the next change.
  iOS (16.2+, below that nothing shows): one Live Activity for the whole
  workout from the `RestTimer` widget extension (target and bundle id kept
  from when it showed rests only; `WorkoutActivityAttributes`,
  `WorkoutLiveActivity`), started by the app in front through
  `AppDelegate.swift` (`getworkout/workout_activity`), updated and ended
  while the app runs; its texts come from the app. Owner's picks
  2026-11-19 (LA1 A, LA2 A, LA3 B, LA4 B). Lock screen, on a dark card in
  every appearance: while a set is due, a top row with the app's mark (a
  dumbbell on the muted green), the exercise's place ("Exercise 3 of 6")
  and the small elapsed time, then the exercise's name large, the set and
  its values ("Set 2 of 3 · 80 kg × 8": "Drop set 2 of 3", "Warm-up 1 of
  2" or "Warm-up" as the set to do now counts them; the values entered,
  else the suggested ones, in the user's unit; none while both are empty)
  and, right-aligned at the end of that line (cut before them, so the
  name has the whole width), one dot per set of the exercise, filled
  where done (narrower above five sets); never the workout's name. Once every set is done but the
  workout is not finished (LA5 A): the same top row (the last exercise's
  place), "All sets done" large and "Finish in the app" under it, no dots;
  the expanded island shows the same two lines. During a rest: "Rest" and the next set beside
  the countdown, a bar emptying from the rest's start to its end
  (`ProgressView(timerInterval:)`), and −15 s, +15 s and Skip (iOS 17+,
  hidden below). Dynamic Island compact: the dumbbell and the elapsed
  time, during a rest a ring emptying over it and the countdown (minimal
  shows the same symbol); expanded: the exercise with the elapsed time and
  the set line with its dots, during a rest "Rest" with the large
  countdown, the emptying bar and the next set, no buttons. A next-set
  line ends a long exercise name with "…" and never cuts its part from
  the last " · " on ("· set 2 of 4") (K7 A). The buttons are
  `LiveActivityIntent` App Intents (`WorkoutActivityIntents.swift`, in
  both targets, not shown in Shortcuts), so they run in the app's process
  without opening it: the Runner moves the rest shown at once (the app's
  rule: 15 s more up to 30 min ahead, 15 s less ending it when less is
  left, Skip ending it) and hands the press to Dart on
  `getworkout/workout_activity_rest`, which answers only once the press
  is applied and the rest notification moved (`LockScreenRestPress`, at
  most 5 s), so iOS keeps the app awake until then; Dart applies it to
  the workout's rest (`RestTimerCubit` through `WatchLockScreenRestActions`, waiting
  until the workout is loaded), which keeps it, moves the rest
  notification and shows the activity again. A press while Flutter does
  not run (the app launched in the background for it) or before Dart
  listens is kept in the Runner's user defaults and taken when Dart starts
  listening. Android's notification has no buttons. No push
  updates (no APNs yet), so the app cannot change it while suspended: the
  content state carries the rest with its end, the activity's stale date
  is that end, and the widget draws the rest only while it is not stale
  and its end is ahead, so at the end the system redraws it as the workout
  by itself; the app replaces it with the workout once it runs again.
  Outside a rest it has no stale date. iOS ends an activity after 8 h
  (kept on the lock screen up to 4 h more); the next update the app makes
  in front then starts a new one, as it does after the user swiped it
  away. Users can turn Live Activities off per app; then nothing shows.
  Logging a set and Finish stay in the app. Elsewhere (not on a
  button), a tap on it (lock
  screen and every Dynamic Island presentation, in both
  modes) opens the app with `getworkout://workout` (its widgetURL; the
  `getworkout` scheme next to Google sign-in's in `CFBundleURLTypes`).
  The Runner takes that URL itself as a scene delegate
  (`WorkoutActivityTaps`) and keeps it until Dart takes it, so a tap that
  launched the app is not lost; Flutter's own deep linking is off
  (`FlutterDeepLinkingEnabled` false; the app has no other deep links).
  The tap joins the notification taps' path in `App`: kept until the app
  is past its start and the workout is loaded, then the workout page is
  pushed through the router as from the minimized workout bar (so the
  unsaved-changes guard sees it), unless it is open already or no workout
  is in progress (an activity left behind), where the tap only opens the
  app. No App Group: the app's own ActivityKit bridge passes the content,
  so the `live_activities` plugin (App Group, iOS 16.1 minimum for the
  whole app) is not used, and the app keeps iOS 15 (ActivityKit
  weak-linked).
- **Finishing**: the workout, its exercises' stats and, when it did the
  active program's next day, the program moved on
  (`users/{uid}.activeProgram`) are one batch, so the server takes all or
  none; it works offline. Whether the program moves on is decided from the programs the
  device knows at that moment; if they are not loaded the program is left
  and the summary says so. The finished workout stays on the device until
  the server confirms it (its batch is acknowledged; see Unconfirmed
  workouts); one the server refused comes back as the workout in
  progress, once none is open, and the user is told, so a workout is never
  lost. Its program advance went back with the batch.
- **Workout times**: `startedAt` and `finishedAt` are device-clock
  timestamps, so a workout done offline keeps its real times; `finishedAt`
  is never before `startedAt`. A program day counts as done on the local
  date its workout started.
- **Records**: heaviest weight (every type with a weight except assisted),
  best e1RM and best set volume (`weight_reps`, `weighted_bodyweight` on the
  added weight), most reps (rep types), longest duration (duration types).
  Warm-ups never count: a session of only warm-ups adds no history point and
  leaves "last time", which holds working sets only. A drop set's volume
  includes its drops, its other records use its first part. A record must be
  beaten, not equalled; an exercise's first workout sets its records but
  celebrates none, in its summary or as tags on its page (`heldRecordSets`
  skips the exercise's first history point).
- **Workout summary**: duration ("< 1 min" under a minute), volume (weight ×
  reps of the working sets of `weight_reps` and `weighted_bodyweight`;
  assistance is no load), working sets and records, laid out as SPEC ›
  Design says. The comparison reads the program's finished workouts by
  `programId` (no composite index), from the server within 2 s, else the
  cache, before the batch is written. The day's changes are judged on the
  workout as it was before finishing (every set) against the day's items
  (`changedProgramDay`) and stored with `SaveProgram`.
- **Stats update**: stats are computed from what the device knows at
  finishing, the server's when it answers for all of them within 2 s, else
  the cache's
  (transactions do not work offline). Stats from the cache, and those that
  cannot be read at all (offline, never loaded here; left alone rather than
  overwritten), are listed on the device and, once the finished workouts
  are confirmed, rebuilt from that exercise's workouts read from the server
  (`rebuildStats`, at most 500 workouts; beyond that they are left). This
  also repairs two devices finishing at once. History keeps the latest 1000
  points, each with its `workoutId`. A rebuild first waits for the
  device's pending writes, so it never reads past an edit the server has
  not seen; offline it waits until the device is online. A rebuild that an
  edit or a finish of the same user crossed is done again, so the last
  stats write always comes from a read after every change.

### History and editing

- **History**: the calendar's list (see Calendar) holds the finished
  workouts of the month shown, read with the month (no paging). Rows carry
  no records mark. The workout page names exercises from the catalogue
  (custom ones included), else by the name stored with the workout
  (retired and deleted ones); a program that no longer exists shows as
  deleted. The workout page (see Design › Workout detail): ⋯ with Edit and
  Delete workout; the band with the start, the name, the program and the
  week of the active copy's run (`ProgramSchedule.runWeek`, none for a
  workout before the run started) and the four totals; the waiting to sync
  notice; the note as its own card; then a card per exercise (group
  letter, name, exercise note, set count), opening and closing, with a row
  per set: the bubble (as `setLabel`), its values and its effort (on the
  chosen scale), a "record" tag on a set holding a record the exercise
  still keeps (`GetHeldRecords`: one read of each exercise's stats; a
  record beaten later leaves the tag), then the set note; each drop is a
  row under its set.
- **Editing workouts**: editing, deleting and adding a past workout store
  the workout in one batch, never changing `activeProgram`; a past workout
  has no program (a program day only fills its exercises, `pastWorkout`),
  the edit page deletes too (it then closes with the workout's page), and
  moving a program workout's start only moves the day
  shown as done. Edits keep ticked sets only and pass the finishing checks
  (`isStorable`); the use case also refuses a start or end in the future
  and a duration over 24 h. The batch carries the stats of every exercise
  touched, before and after, rebuilt with `rebuildStats`, only when the
  server returned all their workouts within 2 s after the pending writes;
  stats are never rebuilt from the cache, which may lack workouts. Every
  exercise touched then joins the device's stale-stats list and is rebuilt
  from the server, as after finishing. An exercise with more than 500
  workouts keeps its stats, on both paths and in the rebuild, so after an
  edit they may stay stale.
- **Editing a workout that changes elsewhere**: the edit page keeps
  following the stored workout. Changed elsewhere, the save is blocked
  until the user reloads the latest version (dropping their edits) or
  discards; deleted elsewhere, only discarding is offered. A save replaces
  the latest stored version, never re-creates a deleted one.
- **Unconfirmed workouts**: a workout with a change the server has not
  confirmed (`hasPendingWrites`: just finished, finished offline or just
  edited) can be viewed but not edited or deleted; its page says it waits
  to sync. A confirmed workout the user deletes also leaves the device's
  list of finished workouts awaiting confirmation, so a confirmation in
  flight never brings it back. Confirming a finished workout asks its
  batch's own answer: acknowledged, it is dropped from the device even if
  it was deleted elsewhere since; refused, it comes back as the workout in
  progress. A save from before the app restarted has lost that answer, so
  only then does absence on the server count as refused. A refused edit or delete is undone by
  Firestore together with its stats (one batch) and reported on the
  calendar.

### Today and progress

- **Today tab** (`lib/features/today`; Tabs picks 2026-11-18): what to do
  now, three parts: the workout card, a "Start empty workout" row ("Pick
  exercises as you go", every day, through `startFreeWorkout`, which asks
  first while a workout is in progress) and the calculators card. The
  week strip, this week's sets and steps are Progress's. Next workout: while a workout is in progress (`ActiveWorkoutState.inProgress`,
  so not an empty one) the card is that workout, labelled "Workout in
  progress", with "Resume workout", which opens it like the workout bar
  and never starts another. A workout stores no day name, so its program
  day shows only while that day would still give it its name (not since
  renamed, moved or deleted). While the workout in progress is still
  looked for, the card shows only its title, never Start.
  Otherwise, with an active program the card's headline is that program,
  labelled "Active program" and opening its page, its next day below;
  without one it is titled "Next workout". It uses the Programs tab's own
  `ProgramListCubit` (one instance), so
  both show the same plan; the next day with its exercise count and
  estimate, the date it is planned for (`ProgramListState.nextDate`, the
  first of `ProgramSchedule.upcoming`) and Start through
  `startProgramDay`. A next day planned after today (none missed) makes
  today a rest day (the rest-day card, its "Start <day> early" through
  `startProgramDay`), or, when a workout was finished today (the latest of
  the week strip's workouts on today's date), the "Done today" block over
  the next day's row; until today's workouts are known the card shows only
  its title. A locked copy's missed day stays its locked block. A missed
  day shows in a header band with the three choices (`resolveMissedDay`,
  shared with `MissedDayPrompt`) instead of Start: Start comes back once
  the missed day is answered (Do it today, Move or Skip; owner's pick,
  Açık kararlar, 2026-11-15), only while the program is open, as there; a failed
  choice is reported by the prompt that made it, so the two tabs never
  both do, and a write the server refuses later by the one
  `ProgramWritesNotice` in the shell, whichever tab is open. While the
  premium status of a premium copy is unknown the card shows only its
  title, as the Programs tab waits, so a missed day never shows as a
  planned one with Start. A locked premium copy shows its day, locked,
  with Start opening the paywall. Without a program, or once it finished:
  one way, See your programs (saved programs, none finished) or See
  ready-made programs; the generator and the program list are on Programs
  (P6), the empty workout is Today's row (the app never calls it "free":
  users read that as "at no cost"). The today and done-today it needs come
  from the week's `TodayWeekCubit` (the one Progress's Calendar card
  shows). No quick actions besides the calculators card (a chip per
  calculator; the calculator pages are routes of the Today tab,
  `/today/calculators/...`, the Plates calculator's bar and plates page
  too) and, on a rest day, the rest-day card's suggestions (owner's
  picks): cardio is logged under Progress → Cardio, a past workout is
  added on the calendar. The rest-day card's walk reads `GetTodaySteps`
  against `settings.stepGoal` (read again when the goal changes and on
  resume) and only checks access, never asks the system. The workout card
  shows its title and shimmering grey bars while loading (owner's pick,
  Çelişkiler, 2026-11-15); no spinner on the home tab; cubits move to the
  new day when the app resumes.
- **Progress tab** (UX pass, 2026-11-13; screen step 2026-11-15): one
  card per area, each opening its page from anywhere on the card. Body:
  the latest weight, the change since the previous weigh-in, the newest
  body fat, the weights of the last 2 weeks as a line, Log weight and
  Measurement day; the measurement-day prompt under it when due.
  Calendar: this week's strip (the app's only one, Tabs P1), always, with
  the week's dates as its detail; no month count; the strip and every day
  open the calendar. Weekly volume (the app's only this-week sets, P2):
  `WatchWeeklyVolume` with one week, this week's sets against the active
  program's planned weekly sets (every day of a week once,
  `ProgramListState.plannedWeeklySets`) as "96 / 120 sets" and a bar, the
  four most trained muscles as VolumeBands, then how many trained muscles
  are in, below and above the band; without a running program "96 sets"
  and no bar. Strength (a StatTile, S8): the most recently trained
  exercise with an estimated 1RM as its detail ("Bench Press e1RM"), its
  latest workout's best e1RM as the figure with the unit apart, and the
  change since the first e1RM of the last 2 weeks as its change line
  ("+3 in 8 weeks", success when up, danger when down, ink-muted when
  none, M2 A; "First estimate" as the caption with one there); the card
  opens the strength list. Cardio (a StatTile, S8): this week's distance as the figure, "2
  sessions · 74 min" as the caption; with no distance this week the
  minutes are the figure and the sessions the caption. Steps (the app's
  only steps card, P5): today against the goal; not set up shows "See
  your steps"; no card without a health store. Each card reads
  through its own cubit and shows its own failure, so one area failing
  leaves the others. The Body and Strength cards' lines cover the free
  charts' 2 weeks (`StrengthRange.free`) for everyone, Premium too
  (owner's call, 2026-11-19); longer history is on the chart pages.
- **Calendar**: Progress → Calendar is one scrolling page (see Design ›
  Calendar): the month card and the month's list, both from one
  `CalendarCubit` that follows the month's dates plus six days on each side
  live: workouts and cardio by local start date, a range on one field, so
  no composite index. Weeks start on the app's first weekday (see Week
  start). Months before and after can be browsed; one ahead shows the
  program's planned days. The list holds workouts, cardio, program days
  planned (with Start) and missed (Do it today, through
  `ResolveMissedDay`). A date is marked for a workout done, cardio done, a
  program day planned and a program day missed. Planned days come from
  `ProgramSchedule.plan`, the week plan's logic over any range: a program
  day done (a workout of the active program and that day, on that local
  date) shows only as its workout, and a day done twice on one date shows
  once, in the Programs tab too. A next day done on its date without the
  program moving on (it was not loaded at finishing) is done, not planned
  or missed, here and in the Programs tab, whose missed-day prompt knows
  only this week's done days. The missed next day shows on its date as
  missed, and again where it is planned now. Only the next day moves
  (`MoveNextDay`: its `nextDate` set to a day from today to the last day of
  its week; the days after it follow). A planned day starts through
  `startProgramDay`, so a locked premium copy's days show but open the
  paywall. A workout opens its page under the calendar, a cardio session
  its page (which finds only the 500 newest sessions). If the programs
  cannot be read, what was done still shows. The calendar reports workout
  edits the server refused.
- **Volume**: each completed working set counts 1 for every main muscle and
  0.5 for every secondary muscle. Warm-up sets do not count. A drop set counts
  as one set. Reference band is 10-20 sets per muscle per week.
- **Weekly volume**: Progress → Weekly volume shows one week, the current
  one first; earlier weeks are free to browse, later than the current one
  never. A week starts on the app's first weekday (see Week start,
  `CalendarDate.startOfWeek`). A workout belongs to the
  week of the local date it started, like a program day, so a daylight
  saving change never moves it. Counting is the programs' own
  (`muscleSets` in `exercises/domain/muscle_volume.dart`) over done sets
  that are not warm-ups; an exercise's muscles are the library's current
  ones (custom exercises included), else, for a retired or deleted one,
  those stored with the workout. Each muscle is judged against 10-20 sets
  whatever the user's level: below, within (both ends inside) or above, in
  the band colours on the bars; the model is painted by weekly sets on the
  heat scale (heat-low to heat-high at 20, staying heat-high above it, no
  outline; Design › Renkler · 6); a muscle with no sets keeps the body's
  colour. Tapping a muscle
  lists the exercises and workouts that gave it sets. The 12-week trend
  (the week shown and the 11 before it) is Premium, a locked row opening
  the paywall otherwise. Only Premium reads those 12 weeks (again when
  Premium comes or goes); everyone else reads the week alone. They are the
  user's own workouts, so the gate is client-side only. Changing week
  keeps the week before on screen until the next arrives, so the model
  keeps its camera. `WatchWeeklyVolume` with one week is what the Today
  tab's card calls. Layout: see Design, "Weekly volume" (2026-11-16); the
  page's 12-week trend charts each week's total sets.
- **Strength**: Progress → Strength lists the exercises with stats (the
  whole `exerciseStats` collection, live), most recently trained first
  (`last.date`, else the latest history point), searched by catalogue name,
  custom exercises included; it stays loading until every exercise is
  named or known to be gone (one no longer in the library shows as
  removed, since stats keep no name). If that collection read grows too
  costly, the fix is a small last-trained index written in the same batch
  as the stats. An exercise's page opens from there only (the Progress card
  opens the list); the exercise detail page no longer links to it (UX pass,
  2026-11-13). It charts each workout's best e1RM in the user's unit
  (Forge Chart.line), lists the records (best e1RM, heaviest weight, most
  reps, best set volume, longest time) with the set that made them, and
  the sessions in the range, each opening its workout; an exercise that
  never had an e1RM (bodyweight, timed) shows no chart and every session.
  A workout's best set: the highest e1RM (then the heavier, then more
  reps) for a load, the least assistance (then more reps), the most reps,
  the longest time, or the heaviest timed set (then the longer); a
  record's set among equal values is the heavier one (for the heaviest
  weight the one with more reps).
  Ranges: 2 weeks free (12 until the Monetization pick of 2026-11-19); 6
  months, 1 year and all Premium; a range starts
  at local midnight of the same day that many months back, or that
  month's last day when it is shorter. Records are all-time and free (the
  workout summary shows them too); only the chart beyond 2 weeks is
  Premium, and a free user with older results (any workout before the
  last 2 weeks) is told so and offered the paywall. The gate is client-side: one stats document holds the whole
  history, so the rules cannot withhold old points without splitting it,
  and no server refusal can occur here.
- **Charts**: `lib/core/line_chart.dart` is a small `CustomPainter` line
  chart (points and formatters only; scaling and ticks are the pure
  functions of `lib/core/chart_geometry.dart`), since neither the app nor
  `forge_ui` has a chart and no chart package is added. Move both to
  `forge_ui` when that package next changes.
- **Charts**: `LineChart` (trends, e.g. e1RM) and `BarChart` (zero-based
  daily or weekly values with an optional target line, e.g. steps) live in
  `lib/core` and share `ChartText` and the pure geometry in
  `chart_geometry.dart`. When `forge_ui` next changes they move there
  together; `BarChart` then gains an optional band and per-bar colours,
  and the volume trend (`VolumeTrendChart` and its painter) is replaced
  by it and deleted. The volume band bars and the cardio chart stay
  feature widgets until then.
- **Cardio**: Progress → Cardio is one scrolling page (see Design ›
  Cardio): this week's distance (in the user's unit, only when a session
  has one), minutes and sessions on top, the 12-week minutes chart, then
  the sessions under a label per week, newest first; a session opens its
  page (type, start, distance, time, pace or speed, calories, heart rate,
  incline, note) with Edit (the form, at `…/edit`) and Delete. Log cardio is
  a full-width button fixed at the bottom once the list has loaded, the
  empty page included. Weeks start on the app's first weekday (see Week
  start), for the summary, the chart and the list alike, as on the Progress
  card. The list follows the 500 newest sessions, plus the workouts of the
  last 366 days in Apple Health or Health Connect (`GetHealthCardio` through
  `forge_health`, read on opening and on app resume, never stored; running,
  walking, hiking, cycling, elliptical, rowing, stairs, swimming, jump
  rope, HIIT and other become the matching type, strength work is left
  out). They need the workouts permission (Android: READ_EXERCISE,
  READ_DISTANCE, READ_TOTAL_CALORIES_BURNED, READ_HEART_RATE); without it
  none are read; the Steps page's Allow access asks for steps and then
  workouts (HX01). They show on the Cardio page, the Calendar (read once
  per user, marked and counted as cardio) and the Progress card, and
  cannot be edited or deleted here. Their tag names the store on iOS; on
  Android the app that saved them when its package is known (Strava,
  Google Fit, Samsung Health, Garmin Connect, Fitbit and a few more), else
  "Health Connect". Pace is rounded to the nearest second.
  feature widgets until then. Done for Strength (Forge Chart.line) and
  the volume trends (Forge Chart.line and Chart.bar with a band,
  2026-11-16); `LineChart` remains for Body.
- **Cardio**: Progress → Cardio is one scrolling page (UX pass,
  2026-11-13): this week's minutes, sessions and distance (in the user's
  unit, only when a session has one) on top, the 12-week minutes chart,
  then the sessions under a header per week (with its minutes), newest
  first; a session opens its detail (type, date, duration, distance, pace,
  calories, note) with Edit and Delete (owner's pick, Çelişkiler,
  2026-11-15). Log cardio is a full-width button
  fixed at the bottom once the list has loaded, the empty page included,
  which then shows only its message. Weeks start on the app's first
  weekday (see Week start), for the summary, the chart and the list alike,
  as on the Progress card.
  The list follows the 500 newest sessions.

### Body, steps and calculators

- **Weight log and measurement days** (`lib/features/body`): Progress →
  Body. A quick log is an entry with only `weightKg`
  (date picker; today keeps the current time, another day is noon); a
  measurement day is a step flow, weight → each tracked measurement → front,
  right, left, back photos, every step skippable, the last one saves;
  nothing entered saves nothing. Edit re-runs the same form or flow,
  prefilled; skipping a step keeps the stored value (a value typed there
  is dropped), and only an emptied field with Next clears one; an entry's
  own measurements stay steps even if no longer tracked; a value left as
  shown keeps its stored metric value exactly. Leaving the flow asks first
  when a value differs from how it opened or a picture was taken. The flow loads the
  previous photos itself, so it works when opened first (e.g. from a
  reminder).
  `settings.trackedMeasurements` is a list of codes (`neck`, `shoulders`,
  `chest`, `waist`, `abdomen`, `hips`, `leftUpperArm`, `rightUpperArm`,
  `leftForearm`, `rightForearm`, `leftThigh`, `rightThigh`, `leftCalf`,
  `rightCalf`, also the `measurements` keys), stored only once the user
  chooses (deleted otherwise, every stored list counts as chosen, also
  one an earlier settings save wrote); until then the default is chest,
  waist, hips, both upper arms and thighs, plus the body-fat measurements
  of the profile's sex once it is known. Edited from the flow's app bar.
  Both sides of a pair (upper arm, forearm, thigh, calf) that are steps
  share one step with a Left and a Right field, skipped or cleared field
  by field as above; entry and compare show them on one row (L / R).
- **Body page** (UX pass, 2026-11-13; screen step 2026-11-16): two views
  behind one segmented control. Overview: three boxes, one chart (range
  control only with entries older than 2 weeks; 2 weeks free), Log
  weight, Measurement day and the history; the looks are in SPEC › Design.
  The boxes (`bodyOverview`): the latest weigh-in's weight, the newest
  body fat and the lean mass of the two, each changed against the
  measurement day before the newest one, counted only for values dated
  after it. The chart shows up to three series picked in "Add to chart": weight,
  body fat, fat mass, lean mass and every measurement as lines, weekly
  sets and daily steps (a week's average, today's partial day left out) as
  bars, plus the target weight line while weight shows. Weight carries
  its rolling 7-day average (`rollingAverage`: the mean of the weigh-ins
  in the 7 days ending on each, within the range). Each series keeps
  its own scale; tapping a day shows the values of that date (a pair of
  measurements as the mean of its sides). Weekly
  sets and daily steps are Premium (owner, 2026-11-13): locked in the
  sheet, never read for a free user, and a stored choice of them is hidden,
  not deleted. Hidden series do not count toward the three; when Premium
  returns, the first three in stored order show. While Premium is not yet
  known they are neither locked nor read. The choice is kept on the device only (owner, 2026-11-13),
  one JSON file per user in the app support directory, so there is no
  data model field and a new device starts from the default (weight, and
  body fat once an entry has one). An unreadable choice file counts as not
  chosen. Under "All", daily steps go back to the oldest body entry or one
  year, whichever is older. Compare: the measurement summary's
  comparison (below). The chart is Forge's `MultiSeriesChart`.
- **Body fat** (derived, never stored): US Navy, through the calculators'
  `estimateBodyFat`, from an entry's measurements and the profile's sex
  and height (`entryBodyFat` in `lib/features/body/domain`). Sites: the
  waist is measured at its narrowest and the abdomen at the navel, so men
  need `neck` + `abdomen`, women `neck` + `waist` + `hips`. An entry
  without them, or with values the formula rejects, simply shows none.
  Shown on the Body page as a series of its chart
  (see Body page; only once some entry has one), in each history row, on the entry and as a change in
  compare, with one decimal. "Measurements to track" has a "Body fat"
  box: ticked exactly while all its measurements are tracked (nothing
  stored); ticking it ticks them (marked "Part of body fat"), unticking it
  unticks those not in the standard set (men: neck and abdomen; women:
  neck), keeping the rest; if none would change it stays ticked and says
  to untick one of them. Without the sex or height it links to the
  profile details instead. Which measurement is the formula's waist
  (`navyWaist`: abdomen for men, waist for women) is one mapping, used by
  `entryBodyFat` and by the calculators' prefill (`knownBodyValues`; no
  waist is prefilled while the sex is unknown). Each measurement step
  shows a one-line hint of where to put the tape (ARB `bodyHint*`).
- **Camera orientation**: `GhostCamera` holds the screen in portrait while
  it shows and locks the capture to portrait. The iPhone 17 family's
  Center Stage front camera is mounted differently; `camera_avfoundation`
  0.11.1 sets a fixed portrait rotation (90°) on the video and photo
  connections, which is off by 90° for that camera (sideways, stretched
  preview; flutter/flutter#196204, no fix released). The app overrides it
  with a patched copy in `third_party/camera_avfoundation` (pristine 0.11.1
  minus `example/`; every change marked `PATCH` in `DefaultCamera.swift`):
  on iOS 17+ the fixed angles are applied relative to the video
  connection's starting `videoRotationAngle`, which Apple sets so the
  front camera still delivers buffers like earlier iPhones and which is 0
  on the other cameras, for both the video and the photo connection.
  Chosen over `RotationCoordinator`, which follows the phone's physical
  orientation and so cannot honour the portrait lock. Limits:
  weight as the profile (30-300 kg), measurements 10-250 cm; values are
  typed to one decimal in the user's unit, so half a shown lb or inch
  step of slack lets the limits as shown pass (66.1 and 661.4 lb, 3.9 in).
  The Body chart has the strength ranges: 2 weeks free, longer Premium
  (confirmed by the user); the profile's target weight shows as its line.
  Comparing is the measurement summary (below). Saving or deleting an entry sets `profile.weightKg` to
  the weight of the most recent dated entry that has one, through the
  profile's `UpdateProfile` (calculators and the target distance use it);
  with no such entry the profile weight is left. Firestore rules validate
  `bodyEntries` (date timestamp, numeric `weightKg`, `measurements` and
  `photos` maps whose known keys hold numbers and strings).
- **Measurement summary** (`lib/features/body`, planned with the owner;
  screen step 2026-11-16): one screen, `MeasurementSummaryPage`, titled
  "Measurement summary" at `/progress/body/summary/:id` (opened in place
  of the flow right after a new measurement day is saved; never after an
  edit). The same comparison is the Body page's Compare view, which a
  measurement day's page opens for that day at
  `/progress/body?compare=<id>` (gone: not found). Without a link Compare
  shows the newest measurement day that has an earlier one, the only
  measurement day alone, or that there is none; the later day can be
  picked from the measurement days after the earlier one. No sharing or
  export. A measurement day is an entry with measurements or
  photos (quick weight logs are not, as for the reminders). The baseline
  is one of the measurement days dated before the entry: the previous
  one by default, "First" (the oldest) or any of them from a list ("Other
  date"); the control shows only with two or more. A chosen day that is
  deleted or moves after the entry falls back to the previous day. Body
  fat, fat mass and lean mass come from each day's own weight (fat and
  lean mass need the later day's weight); otherwise a notice says what
  is missing (sex/height with a link to the profile, the measurements,
  values the formula rejects, the day's weight). Every value either day
  has (weight, measurements, a pair as one box per side) shows before →
  after with the difference; the target (hidden without a target weight
  or a weight that day): an estimated date at the rate between the two
  days, given only when the target is not reached (within 0.05 kg), the
  earlier day has a weight, the days are at least 7 days apart, the
  weight moved toward the target, and the date is between now and 2
  years from now; else the distance or "Reached.". Then the photos of
  every pose either day has on Forge's `BeforeAfterSlider` (a fade);
  both days' photos are fetched from the backup when missing, once per
  screen. Without an earlier measurement day the screen shows the day
  alone: its date with "No earlier measurement day to compare with yet.",
  "Values" without changes, the target, and the photos without a slider.
  The domain model (`MeasurementSummary`, `measurement_summary.dart`)
  does every number; `FindBaseline` picks the baseline;
  `MeasurementSummaryCubit` follows the entries and the profile itself.
- **Photos**: private app storage plus Cloud Storage backup. Never the gallery
  and never the device's own backups: Android's backup rules
  (`res/xml/data_extraction_rules.xml`, `backup_rules.xml`) exclude
  `files/users/` and `files/body_photo_backup.json`, everything else is
  backed up as before; iOS sets `isExcludedFromBackup` on the photos'
  folder (`getworkout/backup_exclusion` channel in `AppDelegate.swift`).
  Taken with the `camera` plugin (`GhostCamera` from `forge_camera`, the previous
  photo of the pose at 35% over the live preview, mirrored with a mirrored
  front-camera preview; back camera first, a switch button), then stored
  shrunk (longest side 1600 px, JPEG 85, turned upright, metadata such as
  location stripped) in the app support directory at the storage path, the
  same string the entry's `photos` map holds. The camera's own file is
  removed once stored, on a retake or skip, and when the flow is left.
  A path carries a revision (`{pose}-{capture ms}.jpg`), so a retake is a
  new path and every device sees its copy is out of date.
  Saving is one change: all photos are stored, then the entry is written,
  and only then are uploads queued; a failure removes what that attempt
  stored, and a retry reuses the flow's entry id. The photos a retake
  replaced, or a deleted entry's photos, are removed (here and queued for
  the backup) only once the server confirms the write; a refused save
  removes its new photos instead, so an undone change leaves nothing.
  Backup (`BodyPhotoSync`) runs in the background: every photo's state
  (upload, delete, uploaded) is kept in `body_photo_backup.json`, written
  one save at a time; a file that cannot be read is renamed
  `.unreadable-<time>` and never overwritten. Work is done for whoever is
  signed in, the user checked before each task (a task failing because the
  user changed goes on with the new user's); failures stay queued and are
  retried at start, sign-in, app resume and the next queued change; a newer
  state for a path wins over a task still running. Each entries snapshot
  reconciles: photos on the device that an entry names and the queue does
  not know are queued for upload (a lost queue, or photos from before the
  backup). A photo missing on the device (a new phone, or a retake made on
  another one) is fetched when a page shows it (entry, compare, the
  measurement day's ghosts and kept photos). Account deletion
  (`DeleteUserAccount` through `LocalAccountData`) stops the user's backup
  and drops their queue before the `deleteAccount` callable runs, so no
  upload lands after the server deleted `users/{uid}/`, resumes it if the
  deletion did not happen, and `DeviceAccountData.clear` removes their
  photos with the rest of the device data (`ForgetBodyPhotos`). Guests
  are backed up like accounts: their uid is the one linking keeps. A
  guest who is left (signed out, or replaced by signing in to an existing
  account) can never come back, so their photos and queue on the device
  are removed at that moment. Orphans: on every sign-in, once the server
  has answered (a snapshot not from the cache; unlimited, so old entries
  count, and including writes not sent yet), the user's photos on the
  device that no entry names, the queue does not know and are older than
  ten minutes are removed: those of a save stored but never written, or
  refused while the app was closed. Nothing in the feature reports to
  analytics or crash reporting itself: `Log.e` goes to Crashlytics through
  `initFirebase`'s hook, which follows the consent; nothing is
  uploaded or fetched while signed out. A
  photo can be retaken, not removed alone. `storage.rules`: owner only,
  `image/jpeg`, under 5 MB, file names `(front|right|left|back)-<digits>.jpg`.
- **Steps**: read-only from Apple Health / Health Connect through
  `forge_health`; never stored, so `firestore.rules` is unchanged. The
  platform store in every build on iOS and Android; the fake only in debug
  and profile builds on other platforms. The Steps page (Progress tab)
  reads the last 30 days in one call and derives today and the week (from the
  app's first weekday, see Week start) from it; it reloads on app resume and on pull,
  never by polling. Access: unless already granted, a one-screen
  explanation comes first and the system is asked only after "Allow access";
  that the user was asked is remembered on the device (a marker file in
  app support), because HealthKit never says. Android refusal shows "Open
  Health Connect" and "Ask again"; a missing Health Connect offers its
  store page. On iOS a month of zeros shows a hint to allow access in
  Settings, never a denial. A failed request shows on the explanation or
  refusal screen; a failed refresh keeps the steps and says so. The page:
  a ring around the count ("of" the goal) with what is left or "Goal
  reached" under it, then the daily goal edited in place; the zero hint;
  then a This week / Last 30 days switch (kept only while the page is
  open, week first; see Design › Steps), a chart with the goal as a line, and under it the
  daily average and "Goal reached n of m days" over the chart's days
  before today (today's partial day and days to come left out, as on Body;
  hidden on a period's first day). The goal is `settings.stepGoal`, 10,000
  by default, 1,000-50,000; minus and plus move it by 100, and tapping the
  number types it in place as in every StepperField (owner's pick,
  Çelişkiler, 2026-11-15): a whole number within the limits, saved on the
  nearest 100, else the range shows under it. Each change saves at once through `SettingsCubit` (no Save); the
  row shows and steps from the last pick until its write comes back, so
  quick taps all count, and drops it when a save fails. `GetTodaySteps` (today vs goal) is registered
  for the Today card. The
  steps domain imports `forge_health` whole, platform code included; once
  the package exposes a domain-only library (next forge tag), import that
  instead.
- **Calculators start from what the app knows** (`GetKnownBodyValues`,
  one read of the profile and the body entries, through their own use
  cases): sex, age (current year minus birth year), height from the
  profile; weight from the newest dated entry that has one, else the
  profile; neck, waist and hips each from the newest entry that has it
  (they may be from different days: neck is rarely measured and changes
  little, waist drives the result); body fat (BMI/FFMI) by the
  calculators' own US Navy formula from those, when sex, height and the
  measurements allow it; activity from `daysPerWeek` (2 light, 3-5
  moderate, 6 active, by the levels' wording). Units, bar and plates come
  from settings as before. The EZ bar and the trap bar have their own
  weights next to the bar's, defaulting by the unit (EZ 10 kg / 25 lb, trap
  25 kg / 55 lb) until customised; the workout's plate breakdown uses the
  bar of the exercise's equipment (barbell first, then trap, then EZ). The
  Bar and plates settings page edits them; the Plates calculator shows a
  summary row leading there. 1RM and the macros' calories stay empty (no
  single source); the goal and target weight map onto no calculator
  input. Every input is a chevron row (name, bodyweight's "Weight"; the
  value in the user's unit, sans muted, or "—") opening a number sheet (the Log cardio sheet, now
  `core/widgets/number_sheet.dart`): titled with the name, the field
  labelled with it too (no unit) and the unit muted inside the box after
  the value, as in Log cardio's sheets (KC3), Clear while there is a value, Save rejecting a
  value outside the input's range in the field. A known value's row adds
  "Measured <date>" for a value from the body log (the entry's date; body
  fat takes the oldest of its circumferences'; the year only when not
  this one); profile values (height, age, a profile-only weight) have no
  date. Saving a value in the sheet makes it the user's (the cubit's
  `known` map drops it), so a late value never replaces it, even a
  cleared one. Both the waist and the abdomen are known; the body fat
  calculator shows the one for the selected sex (abdomen for men, waist
  for women), unless the user set it. Sex and activity are chevron rows
  opening choice sheets; body fat's sex is a segmented control. A missing
  input shows the result card's missing form, "Add your <inputs> to see
  the result." (1RM and macros keep their drawn lines). Reps take 1-100
  in the sheet, so a set above 12 reaches its own row message. Calories:
  "Daily energy need" is maintenance, with Lose / Keep weight / Gain rows
  at 7,700 kcal per kg: 0.5 kg and 0.25 kg a week, or 1 lb and 0.5 lb for
  a pound user (named unrounded); a target raised to the daily minimum, or no loss below
  it, says so in a muted row note. Activity labels "Sedentary · no
  exercise", "Light · 1–3 days", "Moderate · 3–5 days", "Hard · 6–7
  days", "Very hard · physical job". Known values are
  starting values only: nothing is written back. They load once when a
  calculator opens; a value arriving late fills only inputs the user has
  not changed (even one they cleared stays empty). A source that cannot
  be read adds nothing.

### Help, feedback and the review prompt

- **Help & feedback** (`lib/features/feedback`; canvas
  https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ, rows S1, S2): Profile ›
  More › "Help & feedback" (under Your profile, detail "Report a problem
  or share an idea") opens the page (`Routes.profileFeedback`, source
  `profile`); "Write to us" in the review prompt opens it above the
  workout summary (`Routes.workoutFeedback`, source `rating`). A
  multi-line Message (hint "Tell us what happened or what you would
  like…", at most 2000 characters), "Email for our reply" (the account's
  email when it has one, an Apple relay address included; empty for a
  guest, and optional), the note "We add your app version, device and
  account ID so we can help faster." and Send. No topic. Send with an
  empty message or an email that does not look like one (one "@", text on
  both sides, a dot after it) only marks the field ("Write a message
  first", "Enter a valid email, or leave it empty") and keeps marking as
  the user types. Sending writes `users/{uid}/feedback/{id}` (see Data
  model) without waiting for the server, like every write: offline it goes
  out later. Then a snackbar "Thanks! Your message is on its way." and
  back. Device details that cannot be read are sent empty rather than
  stopping the message; a write the rules refuse after that is only
  logged (the form checks what the rules check). No email or push
  notification of new messages (owner's choice).
- **Admin panel › Feedback** (`lib/admin/feedback`, `/feedback`, in the
  nav after Announcements): Open or Closed (Open first), the latest 100 of
  that status, newest first, live; each card shows the message (selectable),
  sent time, reply email (with Copy email) or "none", source, user id,
  app version, platform, OS version, device model and locale, and Close or
  Reopen, which moves it to the other list. Stream errors retry like the
  other lists.
- **Review prompt** (forge_review; canvas rows R1, R2; first-ask rule
  changed by the owner 2026-11-20): two kinds of moment. Every workout
  summary counts once on the device (by workout id); every app open
  (Today shown at launch, and each resume) counts the local calendar day
  once. The first ask comes at the first moment that can ask once two
  workouts were counted or the app was opened on three different days,
  whichever comes first: the second workout's summary, or Today at an
  open on or after the third day. Later asks only at a summary with a
  new record (a highlight) at least 30 days after the last ask; never
  twice in one app version (`FeedbackModule.reviewRules`). The summary of
  the user's first workout ever counts but never asks. A free user's
  summary that asks still leaves through the workout paywall: the ask
  while the summary shows, the paywall on Done (owner's pick R1,
  2026-11-20, canvas https://claude.ai/artifact/CayPEwTYFTHCX55XSMU3Nx). Today asks only while it is in front with nothing over
  the tabs (no paywall, workout, dialog or sheet; onboarding
  and the start pages come before the tabs); a day counted while covered
  asks at the next open that is not. An ask is recorded when it is
  decided, so closing the app on it still counts, and one covered in the
  instant between deciding and showing is spent unseen. The history
  lives in shared preferences, so a reinstall starts it again.
  A dialog over the summary or Today (ForgeDialog.choice): "Enjoying GetWorkout?",
  "Your answer helps us improve.", "Not really" (secondary) beside "Yes!"
  (primary), and ✕. Yes! opens the platform's review prompt
  (`in_app_review`: SKStoreReviewController on iOS, Play in-app review on
  Android, nothing where neither exists); the platform decides whether it
  shows (iOS: at most 3 times a year; never in TestFlight). Not really
  turns the same dialog into "Thanks for telling us" / "Tell us what to
  improve and we will look into it." with Write to us (the form, source
  `rating`, above the page that asked)
  over Close.

### Notifications

- **Reminders** (`lib/features/notifications`): `settings.reminders` holds
  `workout` (`enabled`, off by default; `minute` after local midnight,
  08:00 by default) and `measurement` (`enabled`, off; `everyWeeks` 1, 2
  or 4, 4 by default; `from`, the series' first date as `YYYY-MM-DD`, which
  also gives its weekday, set to today when first turned on and to the
  next such weekday from today when the day is changed; `minute`, 09:00).
  Workout: one local notification at the time on every date
  `ProgramSchedule.upcoming` plans a day for, 28 days ahead (at most 28
  pending), none for a day done on that date, none once the program has
  run its length, none for a locked premium copy; while the programs load
  or fail, or the premium status of a premium copy is unknown, they are
  left as they are, except that a reminder turned off is always cleared. Only the next
  day is named ("Upper · Push Pull"); later ones name the program, as they
  are due only if the user keeps to the plan. Measurement: one for each
  of the next four occurrences of the series except dates that already
  have a measurement day (a body entry with measurements or photos; quick
  weight logs do not count), so a measured one leaves three and the ids
  stay distinct, as `Notifications.sync` requires; the dates are
  followed live through `WatchMeasuredDates`; while they load the
  measurement reminders are left as they are. Horizon: reminders are only
  planned while the app runs, so a user who does not open the app for
  four weeks gets no more workout reminders, and the measurement reminder
  stops after its four planned occurrences. Settings changes apply to
  the settings current when the choice arrives; picking the series' own
  weekday or cadence changes nothing, another weekday restarts the series
  on that day's next date (`reminder_settings_changes.dart`). Both are pure planners (`reminder_plan.dart`);
  `NotificationsCubit` plans again on every program list, settings or
  measurement-day change, on every user change and on resume, and
  `forge_notifications`' `Notifications.sync` diffs each kind's id range
  against what is pending (by a signature of time, text and alarm mode),
  so equal ones stay. While the user's settings or programs load nothing is
  touched, so a start never drops reminders; a change of user or signing
  out drops them at once. Ids: rest 1, and on the lock screen (Android)
  rest countdown 2 and workout in progress 3, workout 100-127 (by date), measurement 200-203 (by
  occurrence), announcement in front 300. Reminders do not ask
  for exact alarms on Android (they may fire up to an hour late). Taps:
  a workout reminder opens Today, a measurement reminder a new measurement
  day (`Routes.bodyMeasureNew`, unless one is already open), an
  announcement Today; a
  workout reminder tapped while the workout in progress is in front stays
  there. A tap at launch waits until the app is past splash and
  onboarding; navigation runs after the next frame.
  Permission: turning a reminder, or the rest notification in the
  settings, on asks in the app first ("Allow notifications?" with one
  line on why; unless the device already allows), then the system; a
  refusal shows "Notifications are off" with "Open settings" (the app's
  notification settings), and the wish is stored on anyway; "Not now"
  changes nothing. While the device refuses (also before it was ever
  asked, which reads the same), the Reminders group starts with a
  "Notifications are off" notice: "Allow notifications" (asks) on a
  device never asked, else "Open settings". The platforms read a device
  never asked as refused, so the app keeps a marker file
  (`notifications_asked`, app support) written by every request, the
  reminders' and the rest notification's. All notifications share the Android channel `workout`,
  except the rest countdown (`rest`). Both channels are created when
  notifications initialise at app start (no permission needed), so a
  pushed announcement finds `workout` before any local notification.
- **Announcements**: FCM topics `announcements_<locale>` (`announcements_en`
  in v1), followed once the device allows notifications, for the device's
  language, leaving the other languages' topics. Notification messages:
  the system shows them in the background (Android: channel `workout`,
  icon `ic_notification`); in front the app shows them as a local
  notification. A tap opens Today; no deep links in v1. Without a push
  token (iOS without APNs) nothing is followed and nothing fails visibly;
  a failed subscription is tried again on resume. FCM auto-init is off in
  the native config (`firebase_messaging_auto_init_enabled`,
  `FirebaseMessagingAutoInitEnabled`) and turned on only when following,
  so a device that never allows notifications gets no push token.
  Allowing notifications never waits for the subscription. Topic push needs no
  stored tokens, so `users/{uid}/pushTokens` stays unwritten until a
  feature needs per-user push.
- **Sending announcements**: the admin panel's Announcements page
  (`lib/admin/announcements`) calls `sendAnnouncement` after a confirmation
  that it reaches every user who allowed notifications and cannot be
  recalled. Title at most 65 and body at most 240 characters after
  trimming (UTF-16 units on both sides; longer is cut off on most lock
  screens), languages of `languages` only. A send carries a random request
  id; the page remembers the last attempt (id and trimmed text) and sends
  the same trimmed text and language under the same id, a new id only for
  other text or after a send went through. The function sends a request
  id once, so a retry after an unclear failure (offline, timeout) never
  sends twice. Every request is recorded in `announcements/{requestId}`,
  which the page lists as the history (latest 50); a request still
  `sending` 5 minutes after `requestedAt` shows as "Unknown — check a
  device before sending again", and nothing recovers it automatically.
  Messages carry the Android channel `workout`, APNs `sound: default`, and
  a time to live of 3 days (Android `ttl`, `apns-expiration`), so a dated
  announcement is dropped rather than arriving weeks late.

### Analytics

Owner's picks (2026-11-20): Firebase Analytics with the BigQuery export
(no second analytics tool), collection on by default with an opt-out, the
full event plan below, and reports in the admin panel (a Dashboard page),
not in a separate dashboard tool.

- **Collection**: Analytics and Crashlytics collect for every user in prod
  release builds unless that user turned "Share usage data" off (Profile →
  Privacy). `settings.analyticsConsent` keeps its meaning per user: false
  is off, true or null (never answered, including everyone who has not
  been asked) is on. Users who said no before keep no. No consent page is
  shown, in onboarding or over the tabs. Still never the advertising ID,
  Android ID or IDFV, and no ad personalisation signals. Legal basis in the
  privacy policy: legitimate interest with an opt-out; the owner accepts
  the KVKK/GDPR risk of not asking first.
- **User id**: the Firebase uid is set as the Analytics user id, so events
  can be joined with Firestore and RevenueCat in BigQuery; it is cleared
  on sign-out and reset on account deletion (`Telemetry.forget`).
- **Screen views**: `screen_view` from a router observer on every page,
  sheet and dialog route, named by the route (`today`, `program_detail`,
  `workout`, `paywall`, …), not by widget class.
- **User properties** (set when they change): `level`, `goal`,
  `days_per_week`, `premium` (`free`|`trial`|`premium`), `acquisition`
  (`apple_search_ads`|`organic`), `account` (`guest`|`email`|`google`|
  `apple`), `has_program` (`true`|`false`).
- **Events** (snake_case; parameters only as listed; ids are content ids,
  never free text):
  - Onboarding: `onboarding_start`; `onboarding_step` {`step`: `welcome`,
    `goal`, `level`, `days`, `equipment`, `sex`, `birth_year`, `height`,
    `weight`, `target_weight`, `program`, `permissions`; `index`} when a
    step shows; `onboarding_complete` {`program_id` or none}.
  - Account: `sign_up` {`method`} when a guest links, `login` {`method`}
    on signing in to an existing account, `sign_out`, `account_delete`.
  - Programs: `program_start` {`source`: `onboarding`|`catalog`|
    `generator`|`custom`, `program_id` for ready-made ones, `premium`};
    `program_generate` {`goal`, `days`}; `program_create`; `program_edit`.
  - Workout: `workout_start` {`source`: `program`|`free`|`past`};
    `workout_complete` {`source`, `duration_min`, `exercises`, `sets`,
    `records`, `workout_count` (the user's total after this one)};
    `first_workout_complete` alongside the first; `workout_discard`;
    `personal_record` {`exercise_id`, `kind`}; `rest_skip`.
  - Library and model: `muscle_select` {`muscle`}; `exercise_view`
    {`exercise_id`, `from`}; `exercise_search`; `custom_exercise_create`.
  - Body and progress: `weight_log`; `measurement_day_save` {`photos`};
    `cardio_log` {`kind`}; `calculator_use` {`calculator`};
    `steps_connect` {`granted`}.
  - Monetization: `paywall_view` {`layout`, `moment`, `offering`} (the A/B
    test's activation event, name and `layout` unchanged);
    `paywall_close` {`moment`}; `paywall_purchase` {`plan`, `layout`,
    `moment`} (the goal, unchanged); `restore` {`premium`};
    `premium_lock_tap` {`feature`}; `manage_subscription`.
  - Engagement: `notification_open` {`kind`}; `review_prompt`;
    `feedback_send`.
- **In code** (`lib/features/analytics`): `Analytics` holds every name
  and parameter; cubits get it injected, a widget without a cubit reads it
  from the app's provider. `AnalyticsSession` sets the user properties
  (`acquisition` comes from the purchaser session's ad attribution) and
  tells `sign_up` from `login` on the auth stream. Screen names sit on the
  routes in `router.dart`; the app logs one whenever another page comes in
  front, a tab switch included. A dialog or sheet the app opens without a
  route logs none. Parameter values are codes; flags are `"true"` /
  `"false"` strings, as Analytics takes no booleans. Fires when:
  - `onboarding_start`: onboarding opens for a user. `onboarding_step`:
    each time a step shows, Back included; `index` is the step's place in
    the flow as it runs (welcome 0, the nine questions 1–9, `permissions`
    10, `program` 11: the permission prompts come before the suggestion).
    `permissions` once, when the first permission prompt shows; `program`
    when the suggestion shows. `onboarding_complete`: when the suggestion
    is left, with `program_id` (the ready-made program) when it was saved.
  - `sign_up` / `login`: `method` is the account's way in; an account with
    several names one (Apple, then Google, then email). `sign_out`: the
    confirmed sign-out, logged before it so it is still the user's.
    `account_delete`: once the server deleted the data, before collection
    for the user stops.
  - `program_start`: a start that went through, from the program page or a
    ready-made program's Start; `onboarding` when the program page was
    opened from the suggestion. `program_generate`: every program the
    generator makes, Regenerate included. `program_create` /
    `program_edit`: the builder's save of a new / an existing program.
  - `workout_start`: `free` and `program` when the workout starts (an empty
    one left again is no discard); `past` when a new past workout is saved.
    `workout_complete` is for live workouts only (a past one has no
    records); `workout_count` is the server's count before it plus one,
    left out when the server does not answer, and then `first_workout_complete`
    follows the summary's first-ever. `personal_record`: one per record
    kind beaten. `workout_discard`: the user throwing a non-empty workout
    away. `rest_skip`: Skip, also on the lock screen.
  - `muscle_select`: the exercise list opening on a muscle from the model.
    `exercise_view`: an exercise page opening; `from` is `library`,
    `catalogue`, `workout` or `history` (a stored workout being edited).
    `exercise_search`: a search typed into an empty field, in the library
    or the picker. `custom_exercise_create`: a new custom exercise saved.
  - `weight_log`, `measurement_day_save` and `cardio_log`: a new entry
    saved (edits are not logged); `photos` counts the day's photos.
    `calculator_use`: a calculator opened from Today or the Calculators
    page. `steps_connect`: the answer to the system prompt; `granted` is
    whether steps can be read (iOS never tells a refusal).
  - `paywall_view` / `paywall_purchase` / `paywall_close`: `moment` is
    `onboarding`, `workout_done`, `app_open`, or `user` for one the user
    opened. `offering` (view only) is RevenueCat's offering id, left out
    when the store gives none (the fake).
    `paywall_close`: the user closing it without Premium.
    `restore`: a restore that answered. `premium_lock_tap`: a free user's
    tap on a lock; `feature` is `generator`, `premium_program`,
    `body_history`, `body_series`, `body_range` or `strength_range`.
    `manage_subscription`: Manage subscription tapped.
  - `notification_open`: `kind` is `workout`, `measurement`,
    `announcement`, or `active_workout` (the workout's lock-screen activity
    or notification). `review_prompt`: the app's review question shows.
    `feedback_send`: feedback sent.
- **BigQuery** (owner's picks, 2026-11-20): Firebase is linked to BigQuery
  on prod and dev (2026-11-20). Google Analytics exports daily only (no
  streaming: the Dashboard shows up to yesterday), all three apps, no
  advertising identifiers, into `analytics_<property>` in the `europe`
  multi-region. Crashlytics exports too (`europe`), for crash-free rates on
  the Dashboard. The datasets appear with the first export; once they do,
  set their default table expiration to 14 months, which the privacy
  policy states. Google Analytics' own retention is 14 months for event
  and user data on both properties (prod 565341735, dev 565325900, account
  "Default Account for Firebase" 146870395).
- **Reports** (owner's picks, 2026-11-21, canvas
  https://claude.ai/artifact/DNxPob6inYxQPTGwLVC6mJ): the admin panel's
  Dashboard reads BigQuery and RevenueCat's metrics through admin-only
  functions, never from the browser directly.
  - Each project has its own panel: the prod panel shows prod data, the
    dev panel dev data. The panel opens on Dashboard, first in the menu.
  - One page: ten tiles on top (daily and monthly active users, new
    users, onboarding completed, first workout, workouts completed, trial
    starts, paid conversion, MRR, crash-free users), then Growth, Funnel,
    Retention, Revenue, Usage and Quality sections.
  - Period: 7, 30 or 90 days, or a custom date range; every tile shows
    its change against the period just before.
  - Funnel (install → onboarding → first workout → paywall → trial →
    paid) switches between bars and a table; Retention (day 1/7/30 by
    weekly install cohort) between the cohort table and curves.
  - Data: a nightly function queries BigQuery for the preset periods and
    stores the results in Firestore, which the page reads at once; a
    custom range is queried live by a callable. Revenue comes from
    RevenueCat's API v2 overview metrics.
  - Datasets: the 14-month expiry is set as the default partition
    expiration of `firebase_crashlytics` and `firebase_sessions` on dev
    and prod (2026-11-21); `analytics_<property>` (daily `events_` tables)
    gets a 14-month default table expiration once its first export lands.
- **Dashboard functions** (`functions/src/dashboard`, not deployed yet):
  `revenueCatWebhook` also keeps every event it reads in
  `revenueEvents/{event id}` (type, period type, `isTrialConversion` on
  renewals, the uid, product, store, environment, time, USD price).
  `dashboardNightly` (09:00 Europe/Istanbul) and the admin-only
  `dashboardRefresh` store `dashboard/p7`, `p30`, `p90` (ranges ending at
  the latest `events_` day), `dashboard/retention` (8 complete weekly
  install cohorts, day 1/7/30), `dashboard/revenue` with a daily copy in
  `dashboardRevenue/{day}` (RevenueCat's overview metrics; the one
  RevenueCat project serves both panels) and `dashboard/status` (`ok`,
  `no-data` before the first export, or `error` naming the parts that
  failed; the others are still written). The admin-only `dashboardRange`
  answers a custom range of at most 366 days. Admins read `dashboard`;
  `revenueEvents` and `dashboardRevenue` stay server-only. Trials and
  paid purchases count production events on prod and sandbox ones too on
  dev; they join Analytics through the user id (the uid, which is also
  RevenueCat's app user id). Users in crash-free and top issues are
  Crashlytics installations against Analytics' active app instances.
  Deploying needs the `REVENUECAT_API_KEY` Functions secret (a v2 key
  with `charts_metrics:overview:read`) on both projects.
- **Dashboard page** (`lib/admin/dashboard`, `/dashboard`, the panel's
  landing page): reads every `dashboard` document once on open and again
  after Refresh now (`dashboardRefresh`, client timeout 540 s); Custom…
  picks a range in the 14 months up to the last day and asks
  `dashboardRange` (timeout 300 s; longer than 366 days is refused before
  asking). Before the first export (no reports, status missing or
  `no-data`) it shows "No data yet" and the revenue snapshot only. Tile
  changes: counts in whole percent (nothing when the previous period is
  unknown or zero), shares in points to one decimal; a change that rounds
  to zero is muted. Growth and Retention curves are one Forge line chart
  per series (Forge has no multi-line chart). The most started program
  shows its id. The Funnel and Retention toggles live as long as the page.
- **Held until the answer is known** (Forge v0.49.0): a new install
  collects only once the user's stored answer is read, and Analytics drops
  what comes before, so `FirebaseTelemetry` holds events and screens (at
  most 100) while the followed user's answer is unknown, sends them in
  order on collect and drops them on no or a user change. The user id
  and the user properties are set after collection starts and replayed
  then (v0.48.0), for the same reason.
- **Checked on the simulator** (2026-11-20, dev, DebugView): screen views
  and the user properties, the onboarding steps and `onboarding_complete`,
  `calculator_use`, `muscle_select`, `exercise_view`, `exercise_search`,
  `weight_log`, `premium_lock_tap`, `paywall_view` (`layout`, `moment`,
  `offering`), `paywall_close`, `restore`, `program_start`,
  `workout_start`, `rest_skip`, `workout_complete` (with `workout_count`),
  `first_workout_complete`, `review_prompt`. Second pass (2026-11-21,
  dev, the Analytics log of the simulator): `sign_up`, `login`,
  `sign_out`, `account_delete` (collection pauses and resumes for each
  new user, the user id and properties follow), `steps_connect`,
  `paywall_purchase`, `program_generate`, `program_create`,
  `program_edit`, `workout_discard`, `personal_record`,
  `measurement_day_save`, `cardio_log`, `feedback_send`,
  `manage_subscription`. It found and #188 fixed: `login` sent under the
  discarded guest's id; `onboarding_start` logged for an onboarded user
  signing in from onboarding; a first workout logged `workout_count: 2`
  and no `first_workout_complete` (the count raced the save);
  `custom_exercise_create` missing when created from a search; and
  `notification_open`, a name Analytics reserves, never recorded (now
  `notification_tap`). Not seen yet: `notification_tap` and
  `custom_exercise_create` after the fix (next build), Android. Known
  and left as is: `sign_up` fires when an email account is linked,
  before its address is verified; deleting an account resets Analytics,
  so the next guest is a new `first_open`; Save as program after a
  workout logs no `program_create` (only the builder's save does).
  Every `app_exception` seen came from the Programs tab crash fixed in
  #183 (Crashlytics', a reserved name). Symbol upload works:
  the Runner's `flutterfire upload-crashlytics-symbols` phase reads
  `firebase.json` (Debug/Profile → dev app, Release → prod app) and a
  release build validated and uploaded its dSYMs to getworkout-prod.
  Debug builds make no dSYM, so the dev console lists those as missing;
  that only affects simulator crash reports.

