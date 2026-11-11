# GetWorkout

Single source of truth for this app. Any agent, in any tool, resumes from here.

## Product

A workout app for everyone who trains, beginner to advanced. The core loop:
pick or build a program, log today's workout set by set, see progress. Its
signature is an interactive 3D body model used to browse exercises by muscle
and to show weekly training volume. Written from scratch; nothing is taken
from the earlier FitLab app.

## Decisions

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
- **Monetization**: freemium via RevenueCat. Monthly and yearly plans, 7-day
  trial on yearly. Premium = program generator, 19 of 25 ready-made programs,
  advanced statistics (charts beyond 12 weeks, volume trend). Everything else
  is free. Until store accounts exist, purchases run against a fake gateway.
- **Backend**: Blaze plan. Cloud Functions are used only where a client cannot
  be trusted or cannot do the job: RevenueCat webhook, account deletion,
  sending push announcements. The program generator runs on device.
- **Exercise sync**: clients read `exercises` of every status, so a
  retirement or a return to draft is noticed by the incremental sync on
  `updatedAt`, and filter to `live` on device. A cache whose document count
  differs from the server's `count()` is rebuilt with a full fetch.
- **Content ownership**: Firestore is the source of truth for content once
  it is seeded. `content/*.json` is the seed and the bulk-edit path;
  the admin panel edits Firestore directly and leaves `contentHash` alone, so
  the import skips (and fails on) documents edited there unless `--force`.
- **Offline**: Firestore's persistent cache is the local database. The workout
  in progress is also kept in a local file so a crash never loses sets.
  Derived numbers are computed from workouts on read wherever the query is
  small; the only stored summary is `exerciseStats`.
- **3D model**: our own renderer, written in Dart, built first because it is
  the riskiest part. Source model has 37 meshes: 19 muscle groups (left/right
  split except abdominal and oblique) plus the body. A female model with the
  same mesh names is required before release; the user supplies it.
- **Units**: stored metric. kg/lb and cm/in chosen by the user.
- **Effort scale**: optional per set, off by default. RIR by default, worded
  plainly ("How many more reps could you do?"); RPE selectable. Stored as RIR
  (`rpe = 10 - rir`).
- **1RM**: Epley, `weight * (1 + reps / 30)`; sets above 12 reps are ignored.
- **Volume**: each completed working set counts 1 for every main muscle and
  0.5 for every secondary muscle. Warm-up sets do not count. A drop set counts
  as one set. Reference band is 10-20 sets per muscle per week.
- **Steps**: read-only from Apple Health / Health Connect; not stored.
- **Photos**: private app storage plus Cloud Storage backup. Never the gallery.
- **Privacy**: minimal set. In-app account deletion, privacy policy link,
  consent for analytics and crash reports. No age gate, health notice or data
  export (the user accepted the EU risk).
- **Notifications**: local for rest end, workout reminders and measurement
  reminders; FCM topic push for announcements.
- **Navigation**: five tabs, Today / Programs / Exercises (center, the model)
  / Progress / Profile. The active workout is full-screen and can be minimized
  to a bar above the tabs.
- **Blocked on accounts the user will open when needed**: Apple Developer
  (Apple sign-in, HealthKit, iOS push, Live Activity on a real device), Google
  Play Console, RevenueCat. Development continues without them.

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
| `incrementKg` | double? | Step for "add weight"; stored as a double even when the file says `1` |
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
`daysPerWeek`, `lengthWeeks?`, `equipment[]`, `l10n.<lang>.{name, summary}`,
`updatedAt`.

**`programs/{id}/detail/main`**: `days[]` (shape below). Readable when the
program is not premium or the reader has an active entitlement.

### Per user (read/write: owner only)

**`users/{uid}`**: `profile` (goal, level, daysPerWeek, equipment[], sex,
birthYear, heightCm, weightKg, targetWeightKg), `settings` (units,
effortScale, restTimer, bar and plates, stepGoal, reminder times,
trackedMeasurements[], analyticsConsent), `favoriteExerciseIds[]`,
`activeProgram` (`programId`, `weekdays[]`, `nextDayIndex`, `nextDate`,
`startedAt`).

**`users/{uid}/customExercises/{id}`**: `name`, `loggingType`,
`mainMuscles[]`, `secondaryMuscles[]`, `equipment[]`, `note`. Max 500.

**`users/{uid}/programs/{id}`**: `name`, `origin` (`own` \| `catalog` \|
`generated`), `sourceId?`, `lengthWeeks?`, `days[]`, `updatedAt`. Starting a
catalog program copies it here, so later catalog edits do not change it.

- `days[]`: `name`, `items[]`
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

**`users/{uid}/exerciseStats/{exerciseId}`**: `records` (heaviest weight, best
e1RM, best set volume, most reps or longest duration; each with value, date,
workoutId), `last` (date and sets of the latest workout, shown as "last
time"), `history[]` (date, best e1RM, total volume; one point per workout).
Rebuilt from that exercise's workouts whenever one is edited or deleted.

**`users/{uid}/cardio/{id}`**: `type`, `date`, `durationS`, `distanceKm?`,
`calories?`, `avgHeartRate?`, `incline?`, `note?`.

**`users/{uid}/bodyEntries/{id}`**: `date`, `weightKg?`, `measurements` (map
of cm values: neck, shoulders, chest, waist, abdomen, hips, and left/right
upper arm, forearm, thigh, calf), `photos` (map of `front` \| `right` \|
`left` \| `back` → storage path). A quick weight log is an entry with only
`weightKg`; a measurement day fills all three.

**`users/{uid}/pushTokens/{token}`**: `platform`, `updatedAt`.

### Server-written

**`entitlements/{uid}`**: `premium`, `expiresAt` (a Firestore timestamp; the
webhook converts), `productId`. Written only by the
RevenueCat webhook; readable by its owner.

### Storage

`users/{uid}/photos/{entryId}/{pose}.jpg`: owner only, JPEG, max 5 MB.

### Cloud Functions

- `revenueCatWebhook` → writes `entitlements/{uid}`
- `deleteAccount` (callable) → deletes the user's documents, photos and auth user
- `sendAnnouncement` (callable, admin) → FCM topic push

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
- [ ] Exercise domain and sync — incremental sync by `updatedAt` — library works offline after first sync
- [ ] Admin panel — sign-in, exercise list, exercise editor with validation, draft/live/retire — an edit appears in the app after sync
- [ ] Exercise content — 400+ exercises in English, loaded through the admin import — every muscle and equipment profile is covered
- [ ] Library — model tab with muscle sheet (main vs secondary), list, search, filters, sort — find any exercise in a few taps
- [ ] Exercise detail — text sections, model with worked muscles, alternatives, variations, favorite, add to workout or program
- [ ] Custom exercises — short form, edit, delete — shown with a "Custom" label everywhere

Group 4, programs
- [ ] Program builder — days, exercise picker, sets and rep range, rest, supersets and circuits, reorder
- [ ] My programs and schedule — start a program, pick weekdays, missed-day prompt (do today, move, skip)

Group 5, workout
- [ ] Active workout — single list, set rows with last time and goal, set types, drop sets, failure, RIR/RPE, notes, swap, add, reorder, minimize bar, crash recovery
- [ ] Free workout — start empty, save as program at the end
- [ ] Rest timer — auto start, +15 s, skip, notification
- [ ] Rest timer on the lock screen — iOS Live Activity, Android ongoing notification
- [ ] Finish and summary — records with a short celebration, `exerciseStats` update
- [ ] History — list, workout detail, edit, delete, add a past workout; stats rebuilt

Group 6, progress
- [ ] Calendar — month view of planned and done workouts and cardio
- [ ] Weekly volume — model coloring and bar list against the 10-20 band; 12-week trend (Premium)
- [ ] Strength — per-exercise records and e1RM chart (beyond 12 weeks Premium)
- [ ] Today tab — next workout and week strip, quick actions, volume card, steps card

Group 7, programs for everyone
- [ ] Catalog — 25 ready-made programs (6 free), filters, detail, premium lock, admin program editor
- [ ] Program generator (Premium) — questions (goal, level, days, session length, equipment, focus muscles, excluded exercises, area to go easy on, preferred split), preview, save as an editable program

Group 8, body and extras
- [ ] Weight log and measurement day — steps for weight, tracked measurements, four photos with ghost overlay, reminders, photo backup, compare
- [x] Cardio — log, list, detail, weekly chart
- [ ] Steps — health permission, today, week and 30-day chart, daily goal
- [x] Calculators — calories (Mifflin-St Jeor), body fat (US Navy), 1RM, plates, macros, BMI and FFMI

Group 9, launch readiness
- [ ] Onboarding — nine questions, suggested free program
- [ ] Notifications — workout and measurement reminders, FCM announcements
- [ ] Subscription — paywall, RevenueCat, entitlement checks, restore
- [ ] Account — delete account, privacy policy link, analytics consent

## Design

<!-- Filled in the design phase, after every feature is ticked. -->

## Open questions

- Google and Apple sign-in are implemented in `forge_auth` but not enabled: Google needs a support email for the OAuth consent screen, Apple needs the Developer account. Until then the app offers email only.
- A guest who signs in to an existing account leaves an orphaned anonymous user and its data behind; clean these up with a scheduled function when Cloud Functions arrive.
- The projects are not linked to a billing account yet; needed before photo backup and Cloud Functions.
- Female body model with the same mesh names: the user supplies it before release.
