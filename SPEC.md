# GetWorkout

Single source of truth for this app. Any agent, in any tool, resumes from here.
To resume, read Now and Open, then only the sections they point to.

## Now

Updated 2026-11-27. Keep this block and Open true with every change.

- **State**: feature groups 1-14 and the animation code of Group 15 are on
  main. iOS 1.0.0 (build 7) was submitted to App Review on 2026-11-24; its
  result is not known here. TestFlight builds 8-13 followed (2026-11-25 to
  2026-11-27). 300 of 419 live exercises have an approved animation.
- **Next**:
  1. Build the exercise page redesign of 2026-11-27 (Open).
  2. The next animation batch (Feature notes › Exercise animations: Where it
     stands, then A batch, step by step).
  3. The App Review result, then what waits on it (Open › Waits outside).
- **Waits on the owner**: each animation batch's approval; two playback
  details to draw and ask; checks on a real device (Open).
- **Waits outside**: App Review of 1.0.0; the Google Play Console is not
  opened, which holds all Android work (Open).

## Product

A workout app for everyone who trains, beginner to advanced. The core loop:
pick or build a program, log today's workout set by set, see progress. Its
signature is an interactive 3D body model used to browse exercises by muscle
and to show weekly training volume.

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
- **Language**: English and Turkish (2026-11-25). Every UI string goes
  through `gen_l10n` ARB files; exercise and program text is stored per
  language (`l10n.en`, `l10n.tr`). The app follows the phone's language
  (anything but Turkish gives English) and Profile › Appearance › Language
  overrides it. Turkish rules (2026-11-25): the user is addressed as "sen";
  exercise names stay English, their texts are Turkish; program and split
  names keep the English split term with Turkish around it ("Upper/Lower 4
  Gün"); day names stay as stored; muscles are Turkish in gym usage (biceps
  "Ön kol", lats "Sırt"; body measurements keep "Ön kol" for the forearm,
  where the tape goes); established training terms stay English (set,
  superset, drop set, circuit, RIR, RPE, 1RM; Squat, Hinge, Lunge as
  movement patterns), the rest is Turkish; the terms themselves are in the
  ARB files. Privacy policy and terms stay English (the KVKK text is
  Turkish). Announcements follow one topic per language, so the panel must
  send a Turkish version for Turkish users.
- **Accounts**: starts as an anonymous Firebase user. Linking email, Google or
  Apple keeps the uid and all data. Signing in to an *existing* account from a
  guest session discards the guest data after a warning; there is no merge.
  Google sign-in uses the platform's own picker (2026-11-24): Android
  Credential Manager's account sheet, iOS Google's sign-in sheet; the admin
  panel's web build keeps Firebase's popup. Closing that sheet returns to
  the page quietly, with no error. Sign in with Apple is offered first on
  iOS; Android offers Google alone (Apple there would need a Services ID).
- **Monetization** (2026-11-19): freemium via RevenueCat. Monthly 7.99 USD
  and yearly 39.99 USD (regional prices per store), a 7-day trial on yearly
  only. The soft paywall shows once at the end of onboarding (after the
  program suggestion), after the summary of a free user's 1st, 4th, 7th …
  workout (2026-11-24), whenever a Premium feature is touched, and from
  Profile; it can always be closed. Which paywall shows comes from
  RevenueCat offerings, not from app code, so it changes without an app
  update. Paid traffic (2026-11-20): installs attributed to Apple Search
  Ads campaigns get the hard (not dismissible) onboarding paywall, with the
  same plans and trial; everyone else, and anything uncertain, keeps the
  soft one. Apple Search Ads only for now: no tracking prompt (ATT), no
  MMP, no Play Install Referrer. A hard paywall locks the app (2026-11-20):
  past onboarding, a user whose current offering is hard and who has no
  Premium (a trial counts as Premium) gets the full-screen hard paywall on
  every app open, cold start or back from the background, until they start
  the trial or subscribe, and again if Premium lapses; Restore stays on it,
  and it stays open while a purchase awaits approval. Anything not known
  (the entitlement or the offering: loading, offline, an error) lets the
  user in until it is known or the next open.
  Premium = the program generator, 23 of 29 ready-made programs, and later
  progressive overload suggestions. There is no limit on programs. Free
  forever: logging, history and calendar, exercises and custom exercises,
  the 3D model, the summary's comparison, every chart with its whole
  history and the weekly volume trend (2026-11-24; the Progress cards'
  lines show 2 weeks, longer history is on the chart pages), body
  measurements and progress photos with compare, cardio and steps,
  calculators, the Live Activity, and later the Watch app, home screen
  widgets and exercise videos. A build without a RevenueCat key
  (`--dart-define=REVENUECAT_IOS_KEY=…`, `REVENUECAT_ANDROID_KEY`) uses the
  fake store in debug and profile and has no purchases in release.
- **Backend**: Blaze plan. Cloud Functions do what a client cannot be
  trusted with or cannot do; the list is under Data model › Cloud
  Functions. The program generator runs on the server (2026-11-22): a
  rule-based engine in a Cloud Function, no LLM, so its rules change from
  the admin panel without an app update; generating needs a connection.
- **Offline**: Firestore's persistent cache is the local database. The workout
  in progress is also kept in a local file so a crash never loses sets.
  Derived numbers are computed from workouts on read wherever the query is
  small; the only stored summary is `exerciseStats`.
- **Privacy**: minimal set. In-app account deletion, privacy policy link,
  analytics and crash reports on by default with an opt-out switch
  (2026-11-20; Feature notes › Analytics). No age gate, health notice or
  data export (the user accepted the EU risk). Remote Config (the paywall
  A/B test, the update and maintenance gate) sends the Firebase
  installation ID for every user, consent or not.
- **Cloud Functions** (`functions/`): TypeScript, 2nd gen, all in
  `europe-west1` (`src/config.ts`; the app's one Dart constant
  `functionsRegion` in `lib/app/functions_region.dart`, used by the app and
  the admin panel, must match). One file per function, exported from
  `src/index.ts`; logic takes its Admin SDK access as a parameter so
  `npm test` (lint, build, `node --test`) runs without an emulator; CI runs
  it. Deploying is the Architect's step, never an agent's (the command is
  under Operations).
- **Dependencies** (2026-11-22): everything current, upgraded from an
  analysis; versions are in `pubspec.yaml` and `functions/package.json`.
  Held back: TypeScript at 6.0 (typescript-eslint does not support 7 yet);
  `equatable` at 2 in the app, only through the `cel` test dependency; the
  `camera_avfoundation` override (`third_party/camera_avfoundation`,
  patched 0.11.1; Feature notes › Body, Camera orientation) until
  flutter/flutter#196204 is fixed. Until then do not bump `camera` past
  what 0.11.1 satisfies without re-copying the new release and re-applying
  the `PATCH` lines; once a release fixes it, check the iPhone 17 front
  camera with it and drop the copy and its `dependency_overrides` entry.
- **Notifications**: local for rest end, workout reminders and measurement
  reminders; FCM topic push for announcements.
- **Accounts not opened yet**: Google Play Console; it blocks Play billing,
  Play Integrity, the prod signing SHA and the Health apps declaration
  (Open › Waits outside). The Apple Developer account exists (2026-11-17,
  team A8J42TV74R); RevenueCat is set up for iOS.
- **Exercise animations** (2026-11-25): every exercise is shown as a
  skeletal animation on the app's own body model, not as video; Claude
  writes them all. The rules live only in this SPEC (Feature notes ›
  Exercise animations). Each exercise is one recipe file,
  `content/animations/<id>.json`, which also carries its status. The owner
  approves batch by batch after watching the drafts in the released app;
  drafts may be on `main`, and only approved recipes reach other users. The recipe (poses, timing, gear) is stored in
  Firestore next to the catalogue and solved on the phone; body models and
  the solver ship in the app. Batches follow the equipment families. An
  exercise gets its correct form and, in the same batch, its mistakes.
  Gear is designed once: a piece of equipment is one kit, approved once,
  and every exercise that uses it names that kit; no exercise draws its own.

## Features

Ordered. Tick when merged to main. A finished group is one line; its
behaviour is under Feature notes and its build history in git. An open
item reads: name — screens — acceptance. Everything else still open is
under Open.

- [x] Group 1, foundation — scaffold, Firebase, guest start and linking, app shell
- [x] Group 2, the model — 3D renderer, per-muscle colouring
- [x] Group 3, exercises — sync, admin panel and editor, English content, library, detail, custom exercises
- [x] Group 4, programs — builder with supersets and circuits, My programs, weekday schedule, missed-day prompt
- [x] Group 5, workout — active and free workout, rest timer, lock screen (rest and workout), summary, history
- [x] Group 6, progress — calendar, weekly volume, strength, Today tab
- [x] Group 7, programs for everyone — catalog of 29 ready-made programs (6 free), admin program editor, generator (Premium)
- [x] Group 8, body and extras — weight log, measurement day with photos and backup, cardio, steps, calculators, measurement summary
- [x] Group 9, launch readiness — onboarding, notifications, subscription, account deletion and privacy
- [x] Group 10, UX pass — every screen's structure and flow reworked from the owner's picks; five tabs (Today / Programs / Exercises / Progress / Profile); three paywall layouts for an A/B test (Remote Config `paywall_layout`)
- [x] Group 11, design in code — Slate theme in forge_ui, Forge and app components, every screen by studio group, flow widget tests (#105–#139)
- [x] Group 12, analytics (2026-11-20) — opt-out collection, typed event API, BigQuery export (daily, prod and dev; prod dataset `analytics_565341735`, 425-day default table expiration), admin Dashboard
- [x] Group 13, admin panel rework (2026-11-21) — panel look, Users, Support inbox, App settings
- [x] Group 14, program generator rebuild (2026-11-22) — engine and rules on the server, callables, the generator in the app, admin exercise fields, rules editor and simulator; live on dev and prod (#221–#230)

Group 15, exercise animations (2026-11-25; Feature notes › Exercise
animations, whose "Where it stands" entry is kept current)
- [x] Animated viewer — `forge_model_viewer` reads skins, joins models and plays looped clips
- [x] Recipe files and tools — one `content/animations/<id>.json` per exercise with poses, timing, gear and status; a validator and the preview tool (`tool/animation/`)
- [x] Solver on the phone — the pose solver and the gear builder in Dart, in a Forge package (`forge_motion`)
- [x] Recipes in Firestore — the import writes approved recipes to `exercises/{id}/animation/main`, rules, the app reads and caches them
- [x] Animations in the app — Exercise detail's first card with the movement and muscles tabs and the mistake chips, the workout's play button and its sheet, both body models — plays on the simulator
- [ ] All exercises — batches by equipment family, each exercise with its correct form and its mistakes, each batch approved by the owner — every live exercise has an approved recipe (2026-11-27: 300 of 419 live exercises approved)

After release (owner's list, 2026-11-19; not before the first release):
- Health improvements.
- Apple Watch improvements.
- Home screen widgets.
- Streaks, weekly goals, achievements and the like.
- Progressive overload suggestions.
- Quick routines and templates outside programs.
- Exercise images and videos (beyond the animations of Group 15).
- Other languages.
- Timers for time-based sets and exercises, and rest set per series.

## Open

Everything still open, each item once; an item goes when it is done. Settled
behaviour and traps are under Feature notes.

### An agent can do now

- **Next animation batch** (Features, Group 15): 118 live exercises have no
  recipe and `ex_lat_pulldown` is a draft without its mistakes. Nearly
  every exercise left needs a kit not built yet (bands, machines, rings,
  suspension, rack, plates, sled, ab wheel; a wall is the `block`
  kit sized as one); the landmine
  press and the Meadows row need the landmine kit to follow one hand.
  Read Feature notes › Exercise animations: Where it stands, then A batch,
  step by step (it starts with `python3 tool/animation/batch.py`); the
  owner approves each batch. Sample every clip frame by frame for body
  parts inside gear: the owner caught feet passing through a box.
- **Exercise page redesign** (Design, 2026-11-27): draw the picks in the
  studio's ExerciseDetail board, then build them on one branch and PR. Left
  to the build, as the boards show: the Mistakes tab keeps the numbered rows,
  whose play button moves the form cards to that mistake; Details holds the
  info table, then Similar exercises; the muscle legend sits under the form
  cards. The owner may turn down the built result and ask for it back, so
  the PR changes only the exercise page and reverts as one.
- **Exercise page parts** (2026-11-26, after the redesign): studio component cards and Widgetbook
  use cases are owed for the animation stage with its tabs, the motion view,
  the mistake chips, the playback buttons, the workout card's play button, the
  numbered mistakes and the similar-exercise rows; `widgetbook/lib/use_cases`
  and the studio page have none of them.
- **Studio, not confirmed as drawn afterwards**: the states built from
  standard forms on the Programs tab and the workout screen (2026-11-15), and
  the admin pages (no admin component is tagged in the studio page).
- **Screens with fuller data** (`tool/seed_demo.dart` fills a dev account):
  Body with several weigh-ins, measurement days and photos; the past-workout
  band's four figures with a large volume ("12,400 kg" may be cut); the Cardio
  session's distance tile ("18.4 km" may wrap); large text beyond Today and
  Progress (both wrap without overflow at the largest accessibility size on
  the simulator, 2026-11-25).
- **Flow tests** do not cover dragging the weight ruler and taking a
  measurement photo.
- **Animations, gear that leaves the hands** inside a clip is not drawn: a
  slam or a throw stops at the release (Feature notes › Exercise animations).
- **Animations, rig**: a comparison with Tripo's rig, only if Blender's
  weights prove too weak.
- **Legal pages, not verified**: the Cloud Storage bucket's region, which the
  policy states as europe-west1; whether App Privacy's 16 types include
  Advertising Data for the Apple Search Ads attribution is not recorded
  (Feature notes › Subscription and paywall).
- **App Check**, per project (dev and prod): add each debug build's token on
  dev; watch the metrics per product, then enforce per product and add
  `enforceAppCheck: true` to the app's callables. What is enforced when is
  under Feature notes › Account and privacy › App Check.

- **GetWorkout Studio's published copy is behind** `design/studio.html`
  (2026-11-27: one wrapper tagged `Layout`, two derived lists rebuilt; no
  look changed). Republish the file to the studio link from a Claude
  session (Design, studio links).

### Waits on the owner

- **Review marks on the owner's prod account** (2026-11-27): the account
  has the admin claim, which shows animations under review, and the 271
  animated exercises were set as its favourites to tell them apart. The
  owner says when the favourites, or the claim, should go.
- **Playback details, to be drawn and asked** (an agent draws the rows first):
  whether pause and half speed survive a chip change (built: they do) and
  whether a speed change restarts the loop (built: it does; the screen review
  of 2026-11-26 noted the opposite without a board). Feature notes › Exercise
  animations › In the app.
- **Animations on the owner's phone**: speed and feel (60 fps).
- **Draft animations in the rules**: `firestore.rules` lets any signed-in user
  read the draft documents (the app shows them to admins only); narrowing that
  to the admin claim is a rules deploy the owner has not asked for yet.
- **Generator rules**, for the owner to tune in the panel: the seed rules'
  known gaps are under Feature notes › Programs › Program generator.
- **Generator offline** in the app is not tried on a device (the simulator
  cannot go offline on its own).
- **Health on a real device**: health cardio sessions; users who allowed steps
  before #118 are asked for workouts only through Allow access again; the real
  Apple Health / Health Connect prompts.
- **Google sign-in**: a completed native sign-in, guest link and re-sign-in on
  both platforms.
- **Body photos, not confirmed on a device**: the camera permission's denial
  text, the ghost's alignment (front-camera previews are mirrored, saved
  photos are not), retake, restore from the bucket, the iOS backup exclusion;
  the patched `third_party/camera_avfoundation` (Decisions › Dependencies) on
  an iPhone 17. A measurement day's four photos did upload from the owner's
  iPhone (2026-11-18).
- **Subscription trial** is not checked: the owner's Apple ID already
  subscribed in the group, and the dev sandbox tester's sign-in looped after
  the verification code (2026-11-24).
- **RevenueCat dashboard**: enable Customer Center (Pro plan, free below 2.5k
  USD monthly revenue), set its accent to the app's, and map both products to
  their promotional offer on the Cancel path.
- **Workout on the lock screen (iOS)**, checked on the simulator (2026-11-25).
  Not checked yet: a tap with the workout page under the picker or paywall,
  below iOS 17, a real device.
- **Notifications, not verified**: a tap on a push on iOS;
  `Notifications.openSettings` (the reminder tiles' "open settings") on either
  platform; where the iOS steps hint's "Open Settings" (`app-settings:`) lands
  on a device.
- **Legal pages** are not reviewed by a lawyer.
- **App Check, DeviceCheck** for iOS below 14, per project:
  `deviceCheckConfig` needs a DeviceCheck key (.p8) of team A8J42TV74R, stored
  with `tools/secret.sh`.

### Waits outside

- **App Review of 1.0.0 (build 7)**: submitted 2026-11-24 with both
  subscriptions, manual release; WAITING_FOR_REVIEW on 2026-11-25, not looked
  at since. Check the review result and record it here and in Now.
- **Turkish App Store listing**, once the review ends: the text approved on
  2026-11-25 is in `store/app_store_tr.txt`; enter it with Turkey added and
  Turkish screenshots.
- **Win-back offers**, once the subscriptions are approved: one per plan
  (Feature notes › Subscription and paywall › Win-back offer).
- **Play Console, not opened** (Decisions › Accounts not opened yet). Once it
  exists: the Health apps declaration (steps, exercise, distance, total
  calories burned, heart rate); Data safety (App activity, and App info and
  performance › Crash logs, collected and linked to the user).
- **Play billing**: Android / Play is not set up: products, the service
  account in RevenueCat, license testers, the merged manifest's BILLING
  permission.
- **Google sign-in on Android, prod**: the release (Play app signing) SHA on
  the prod Firebase Android app once the Play Console exists (Feature notes ›
  Account and privacy › Google sign-in set-up).
- **App Check, Play Integrity** (`playIntegrityConfig`), per project, once the
  Play Console exists: link the Cloud project in Play Console › App integrity
  and add the Play app signing SHA-256 to the Android app.
- **Android has never been built or run** with the changes since the rest
  timer; it waits for the Android release to be prepared. What is unbuilt and
  unchecked until then is under Feature notes › App shell, settings and
  onboarding › Android.
- **Android, first topic subscription**: on a fresh emulator install it failed
  twice with "FCM Registration failed" and succeeded at the next resume. If
  real devices show it too, retry shortly after the failure.

Reference: read only what the work at hand needs.

## Operations

Paths are from the app root; `tools/` is the forge's, run from the forge root.

- **Run**: `flutter run`; debug and profile builds use `getworkout-dev`,
  release builds `getworkout-prod`. Admin panel: `flutter run -d chrome -t
  lib/main_admin.dart` against dev, with an account that has the admin claim
  (`tool/set_admin.sh`).
- **Checks before a commit**: `dart format lib tool test && flutter analyze &&
  flutter test`; in `functions/`, `npm test`. CI repeats both.
- **Deploy**: functions with `firebase deploy --only functions --project <id>`
  (the Architect's step; their secrets are set on the project first); the
  legal pages with `firebase deploy --only hosting:legal --project
  getworkout-prod`; the admin panel with `tool/deploy_admin.sh <dev|prod>`;
  content with `dart run tool/import_content.dart --project <id>`, which
  validates and writes only what changed. `firestore.rules`,
  `firestore.indexes.json` and `storage.rules` are wired in `firebase.json`.
- **TestFlight**: bump the build number in `pubspec.yaml`, then from the forge
  root `tools/ios_upload.sh <app dir> <prod GoogleService-Info.plist>
  --dart-define=REVENUECAT_IOS_KEY=...` (the plist is
  `ios/Firebase/prod/GoogleService-Info.plist`).
- **Secrets**, by name. macOS Keychain through `tools/secret.sh`:
  `ASC_API_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_IAP_KEY_P8`,
  `REVENUECAT_IOS_KEY`, `REVENUECAT_SECRET_KEY`, `RC_WEBHOOK_AUTH_dev`,
  `RC_WEBHOOK_AUTH_prod`, and a copy of `SUPPORT_GMAIL_APP_PASSWORD`. Firebase Functions secrets, per
  project: `REVENUECAT_WEBHOOK_AUTHORIZATION`, `APPLE_SIGN_IN_KEY`,
  `SUPPORT_GMAIL_APP_PASSWORD`, `REVENUECAT_API_KEY` (Data model › Cloud
  Functions).
- **Google access token**: the `tool/` scripts that reach a Firebase project
  read one from `GOOGLE_ACCESS_TOKEN`. How to get one, the account ids and the
  owner's device are in the forge's `workflow/release.md` and its local notes
  file.
- **Local prerequisites**: Flutter 3.50.1 (`.github/workflows/ci.yml`); for
  the animation tools Blender 5.2 at `/Applications` and python3 with numpy
  and Pillow.

## Vocabulary

Stored as string codes. The lists are the enums of
`lib/features/exercises/domain/vocabulary.dart` (exercise fields) and
`functions/src/generator/vocabulary.ts` (the generator's: goal,
generatorTier, sensitiveArea, focusArea, equipmentStyle, slotRole). What
the lists do not say:

- **muscle**: 18 codes, equal to the body model's groups. Muscles the model
  lacks are filed under the nearest group (rhomboids → `trap`, serratus →
  `pec`, neck → `trap`, tibialis → `calf`, rotator cuff → `rear_delt`,
  brachioradialis → `forearm`). Hip flexors have no group (2026-11-20);
  a hip flexor stretch is filed under `quads` (rectus femoris). Readers
  skip codes they do not know, so old documents load without them.
- **equipment**: `box` is any plyo box, step or raised surface;
  `back_extension_bench` covers back extension and GHD benches.
  `bodyweight` means no equipment at all, so it is only ever listed alone.
- **laterality**: a `unilateral` set is logged once and means "per side".
- **position**: `supported` is on the arms (dips, L-sit, ring support),
  `inverted` is head down (handstands).
- **generatorTier**: how good an exercise is for a generated program,
  judged among exercises of its own equipment: `staple`, `standard`,
  `fallback` (only when nothing better fits), `never`.

## Data model

Firestore. Timestamps are server timestamps; ids are generated on the client.
Field limits and who may write are in `firestore.rules`.

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
| `generatorTier` | code | Read only by the program generator; a document without it counts as `standard` |
| `stressAreas` | code[]? | 1-5 sensitiveArea codes: the generator never gives this exercise to a user who marked one of them. Absent is none |
| `l10n.<lang>` | map | `name`, `aliases[]`, `setup[]`, `execution[]`, `mistakes[]`, `safety?`, `cues[]` |
| `updatedAt` | timestamp | Clients sync incrementally on this |
| `contentHash` | string | SHA-256 of the stored content, written by the import; a mismatch marks a document edited elsewhere |

Alternatives are computed on device: same main muscle and movement pattern,
the user's equipment first (an exercise fits when `equipment` or any of its
`equipmentAlternatives` sets fits), then popularity; pinned first, excluded
removed.
Variations are the other exercises of the same `family`, ordered by rank.

**`exercises/{id}/animation/main`** (2026-11-25): `recipe` (string), the
exercise's animation recipe as compact JSON text, because Firestore has no
arrays of arrays and a recipe is full of them; `updatedAt`, `contentHash`.
The recipe's format is documented in the header of
`tool/animation/recipe.py`. Written by the import from
`content/animations/<id>.json` only while its status is `approved` (deleted
when it no longer is), without the file's `status` and `note` and without
mistakes not approved themselves. Muscles are the exercise's own.

**`animationKits/main`**: `kits` (string), the approved gear kits of
`content/animations/_kits.json` as compact JSON text, stored once for
every recipe; `updatedAt`, `contentHash`.

**`programs/{id}`** (catalog card): `status`, `premium`, `level`, `goal`,
`daysPerWeek`, `lengthWeeks?`, `equipment[]`, `minutes` (`{min, max}`),
`dayList[]` (`{name, exercises}` per day, so a locked premium program can
list its days), `equipmentProfile` (`full_gym` \| `home_gym` \|
`dumbbells` \| `bodyweight` \| `bands`, for filtering; every exercise fits
it through `equipment` or an alternative set), `order` (unique int, the
catalogue's default sort), `l10n.<lang>.{name, summary}`, `updatedAt`,
`contentHash`. `equipment`, `minutes` and `dayList` are computed and
checked by the content validator; a card without a readable `minutes` or
`dayList` shows without it. Seeded from `content/programs/<id>.json`,
which holds the card and `days` together.

**`programs/{id}/detail/main`**: `days[]` (shape below, without `targetKg`),
`updatedAt`, `contentHash`. Readable when the program is not premium or the
reader has an active entitlement.

### Per user (read/write: owner only)

**`users/{uid}`**: `profile` (goal, level, daysPerWeek, equipment[], sex,
birthYear, heightCm, weightKg, targetWeightKg), `settings` (units,
effortScale, askEffort (absent is true), weekStart and language (absent or
unknown is automatic), restTimer, warmups, seenTips[], keepScreenOn, bar
and plates (each only while customised), stepGoal, reminder times,
trackedMeasurements[], analyticsConsent), `favoriteExerciseIds[]`,
`activeProgram` (`programId`, `schedule` (ISO weekday `"1"`-`"7"` → the
program day index done on it; 1-7 entries, a day may be on several
weekdays or on none), `nextDayIndex`, `nextDate` `YYYY-MM-DD`,
`movedFrom?` `YYYY-MM-DD` (the date the next day was planned for before it
was moved earlier; training weekdays up to it rest), `startedAt`
device-clock timestamp). Legacy: an `activeProgram` written before
2026-11-19 has `weekdays[]` instead of `schedule`; it reads as those
weekdays doing the days in turn, and the next write replaces it. Old
documents may still hold `exerciseNotes`, which nothing reads
(2026-11-26).

**`users/{uid}/customExercises/{id}`**: `name`, `loggingType`,
`mainMuscles[]`, `secondaryMuscles[]`, `equipment[]`, `note`. Max 500.

**`users/{uid}/programs/{id}`**: `name` (1-60 characters), `origin` (`own`
\| `catalog` \| `generated`), `sourceId?`, `lengthWeeks?` (1-52), `days[]`
(1-7), `premium?` (true on a copy of a premium ready-made program and on
its duplicates; Feature notes › Programs), `updatedAt`. Starting a catalog
program copies it here, so later catalog edits do not change it.

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
is the set that made the record, or the workout's best working set.
Rebuilt from that exercise's workouts whenever one is edited or deleted;
stats stored before `set` and `workoutName` were kept are rebuilt when
their Strength page opens.

**`users/{uid}/cardio/{id}`**: `type`, `date`, `durationS`, `distanceKm?`,
`calories?`, `avgHeartRate?`, `incline?`, `note?`.

**`users/{uid}/bodyEntries/{id}`**: `date`, `weightKg?`, `measurements` (map
of cm values: neck, shoulders, chest, waist, abdomen, hips, and left/right
upper arm, forearm, thigh, calf; body fat is derived from them and the
profile, never stored), `photos` (map of `front` \| `right` \|
`left` \| `back` → storage path, which holds the photo's revision; see
Storage). A quick weight log is an entry with only `weightKg`; a
measurement day fills all three.

**`users/{uid}/devices/{installId}`** (the admin panel's Devices and its
test announcements; written by the app, read by admins and the functions,
never read back by the app): `model`, `platform` (`ios` \| `android`),
`osVersion`, `appVersion`, `pushToken?` (the install's FCM registration
token, absent while it has none; kept here since 2026-11-24) and `lastSeenAt` (server time, the token's update time too).
`installId` is random, made on the install's first run and kept in the
app's support directory: it survives updates, a reinstall gets a new one.
When the app writes it is under Feature notes › Admin panel.

**`users/{uid}/feedback/{id}`** (Help & feedback): `uid`, `email?` (where
to reply), `message`, `source` (`profile` \| `rating`), the app version
and device details, `status` (`open` \| `replied` \| `closed`; the admin
panel shows `open` as New), `createdAt`, and once replied to
`lastReplyAt` (written by `sendSupportReply`). The owner, guests included,
may only create them; only admins read them, as the collection group
`feedback` (index in `firestore.indexes.json`), and change only `status`.

**`users/{uid}/feedback/{id}/replies/{requestId}`** (support replies):
`message`, `to`, `subject`, `status` (`sending`, `sent`, `failed`),
`sentBy`, `sentByEmail`, `requestedAt`, and once sent `sentAt` and
`messageId` (the SMTP Message-ID). Written only by `sendSupportReply`;
readable by admins.

Account deletion and the guest cleanup remove everything under
`users/{uid}`, subcollections added later included.

### Server-written

**`entitlements/{uid}`**: `premium`, `expiresAt` (a Firestore timestamp; the
webhook converts), `productId` (absent when no event named a product),
and the webhook's `lastEventMs` and `lastEventIds` (ordering and
redelivery). Written only by the RevenueCat webhook (and
`tool/set_premium.sh` on dev); readable by its owner. The rules read only
`premium` and `expiresAt`.

**`announcements/{requestId}`**: `locale`, `title`, `body`, `audience`
(`everyone` \| `free` \| `premium`; absent on older rows: everyone),
`status` (`scheduled`, `sending`, `sent`, `failed`, `cancelled`),
`sentBy` (uid), `senderEmail?` (older rows have none and the history shows
the uid), `requestedAt`, `scheduledFor?`, once sent `sentAt` and
`messageId` (FCM's), once cancelled `cancelledBy` and `cancelledAt`.
Written only by `sendAnnouncement`, `sendScheduledAnnouncement` and
`cancelAnnouncement`; readable by admins. Tests are not recorded.

**`generator/rules`** (the program generator's rules; Admin SDK only, no
client reads or writes it): `version` (int, from 1), `publishedAt`,
`publishedBy` (uid, or `import` for the seed), `publishedByEmail`,
`note?`, `restores?` (the version a restore brought back), `rules`. Every
publish also stores the same document as `generator/rules/versions/{n}`,
never changed afterwards. Seeded from `content/generator/rules.json`; the
shape of `rules` is the validator in `functions/src/generator/rules.ts`,
and what each part does is under Feature notes › Programs.

**`generator/options`** (read: any signed-in user; written with every
publish): what the app needs to ask the generator's questions: the rules
`version`, the splits with the answers each fits, the session lengths, how
many focus and skip areas may be picked, and each area's muscles (so the
pickers paint and take taps for exactly the muscles the rules act on).

### Storage

`users/{uid}/photos/{entryId}/{pose}-{revision}.jpg`, revision the capture
time in ms (a retake is a new file; the replaced one is deleted): owner
only, JPEG, max 5 MB.

### Cloud Functions

All exported from `functions/src/index.ts`. Inputs, outputs and refusal
codes (a machine-readable `details.reason`, which the app and the panel
map on) are in each function's file; below is what the code cannot say.
Every admin function needs the `admin` custom claim, set by
`tool/set_admin.sh` (Operations › Google access token).

- `guestCleanupNightly` (scheduled, `guest_cleanup.ts`; 2026-11-24):
  deletes every guest (no linked provider) the app has not used for 90
  days and that has no `entitlements/{uid}`, exactly as `deleteAccount`
  does. This also removes the guests left behind by signing in to an
  existing account.
- `revenueCatWebhook` (HTTPS, `revenuecat_webhook.ts`, secret
  `REVENUECAT_WEBHOOK_AUTHORIZATION`): writes `entitlements/{uid}`;
  Feature notes › Subscription and paywall.
- `deleteAccount` (callable, `delete_account.ts`): for the signed-in
  caller deletes `users/{uid}` recursively, `entitlements/{uid}`, Storage
  `users/{uid}/`, then the auth user last, so a partial failure can be
  retried; every step succeeds when nothing is left. A non-guest must
  have signed in within the last 5 minutes. With a fresh Apple
  authorization code it first revokes the user's Apple tokens, with a
  client secret signed with the `APPLE_SIGN_IN_KEY` secret (the .p8 of key
  W3KP8AP8K2; team, key and client id are constants in `apple.ts`); if
  Apple refuses, nothing is deleted. Once the auth user is gone it deletes
  `entitlements/{uid}` once more, so a webhook event racing the deletion
  leaves nothing; later events skip the uid. RevenueCat keeps its customer
  and its events keep coming until the store subscription, the user's to
  cancel, ends.
- `sendAnnouncement`, `cancelAnnouncement` (admin callables) and
  `sendScheduledAnnouncement` (Cloud Tasks queue function): a push to the
  audience's FCM topic (`announcements_<locale>`, with `_free` or
  `_premium` for those audiences; 2026-11-24), recorded in
  `announcements/{requestId}`. Idempotent per request id: one already sent
  is not sent again. Only an FCM error that certainly means it was not
  accepted records it `failed`, which a retry of the same id may send
  again; any other error leaves it `sending` and it is never sent again;
  different text gets a new id. A scheduled one (a minute to 30 days
  ahead, Cloud Tasks' limit) is a Cloud Task named after the request id;
  the task sends only a request still `scheduled`, so a cancelled one or a
  task delivered twice sends nothing, and a failed send is recorded, never
  retried. A test goes only to the caller's own devices' push tokens
  (`users/{uid}/devices`) and is not recorded.
- `sendSupportReply` (admin callable, `send_support_reply.ts`, secret
  `SUPPORT_GMAIL_APP_PASSWORD`, the Gmail app password of
  getworkout.support@gmail.com): emails the reply through Gmail SMTP from
  that address to the thread's `email`, keeps it under the thread's
  `replies` and sets the thread `replied` (or `closed`) with
  `lastReplyAt`. Idempotent per request id like `sendAnnouncement`: only a
  failure that certainly happened before the mail was handed over records
  it `failed`; timeouts and dropped connections leave it `sending`, never
  sent again.
- The panel's Users pages (admin callables in `functions/src/users/`,
  secret `REVENUECAT_API_KEY`, a v2 key; a 403 from RevenueCat is a key
  without the permission): `adminListUsers`, `adminFindUser`,
  `adminGetUser`, `adminGrantPremium`, `adminRevokePremium`,
  `adminSetAdmin`, `adminDeleteUser`. The list reads and sorts every Auth
  user on each call (Auth lists in no useful order; fine to tens of
  thousands). A user's Premium tag follows RevenueCat, else the server's
  record. Granting gives RevenueCat's promotional `premium`; revoking ends
  only promotional grants; a store subscription is never touched. A
  changed admin claim reaches the user's token within an hour; an admin
  cannot demote or delete themself. `adminDeleteUser` runs
  `deleteAccount`'s steps but cannot revoke Apple's tokens (no fresh Apple
  code) or cancel a store subscription. The password reset email is
  Firebase Auth's own, not a callable.
- `generateProgram` (callable, `functions/src/generator`): a program from
  the user's answers, the published rules and the live exercises. Users
  with an active entitlement only; an admin always may, and may also send
  unpublished rules to try and ask why each exercise was picked. The
  published rules are cached in the instance's memory for 60 s, the live
  exercises for 5 minutes, so a change shows after that. Feature notes ›
  Programs.
- `generatorRulesGet`, `generatorRulesCheck`, `generatorRulesPublish`,
  `generatorRulesHistory` (admin callables, `functions/src/generator`). A
  publish is refused as stale when it was not based on the current
  version; it writes `generator/rules`, its write-once version copy and
  `generator/options` in one transaction.
- `appSettingsGet`, `appSettingsPublish`, `appSettingsHistory` (admin
  callables, `functions/src/app_settings`): the app's Remote Config
  template, only the keys of the app's defaults (`KEYS` in `settings.ts`).
  A publish writes only the changed keys' default values and keeps
  conditional values, other parameters, groups and conditions; it is
  refused as stale when the template changed since it was loaded, and as
  locked for a key whose default is an experiment, rollout or
  personalization. The version's description (`Admin panel · <email>[ ·
  restores version N]`) is how the history knows who published: the Admin
  SDK's own user is the service account.
- `dashboardNightly` (scheduled), `dashboardRange`, `dashboardRefresh`
  (admin callables, `functions/src/dashboard`): the admin Dashboard's
  numbers; Feature notes › Analytics.

## Design

How anything looks lives only in the two studios; a design change is made
there, never here. The studio rules (tags, build check, components chosen
before drawing) are in the forge's `workflow/design.md`. This section keeps only
what was decided and when; what is still owed is under Open.
- GetWorkout Studio https://claude.ai/artifact/PuK5WUbeyhVHMxA6THNDC2 (in
  git as `design/studio.html`): the app's preset tokens, rules, components
  and every screen with its states. `lib/app/theme.dart` is written by hand
  to follow it; no tokens file is in the repo.
- MobileAppForge Studio https://claude.ai/artifact/6G4XXrCwoijEmEcFhNQDCU:
  the shared Forge components, drawn once; each card is that component's
  rule.
- The canvases linked below are the record of what was offered and picked
  from 2026-11-18 on; the older ones were local files and are gone.

Decisions, one row per batch. A pick that a later row replaced is left out
of the older row.

| Date | Topic | Picks | Canvas |
|---|---|---|---|
| 2026-11-13 to 17 | Colour and preset | Muted colours, the loud directions rejected; Slate is the one preset; users still choose Light, Dark or System | |
| 2026-11-13 to 15 | Screens and flows, first pass | Onboarding asks one question per page; Measurement day is three steps (weight, measurements, photos); the exercise picker is the exercise list in a choosing form, and Swap is its single-choice form with similar exercises first; the workout keeps one exercise card open, asks the effort after Log set and then shows the rest countdown in the set panel | |
| 2026-11-14 | Moving into Flutter | The app draws the studios' own icon set, no icon package; the preset's fonts are bundled | |
| 2026-11-14 to 15 | Components | The plate button only for barbell, EZ bar and trap bar exercises; a card's set count includes warm-ups; a superset or circuit keeps its items in step (one rounds count, one rest after the group); plates in muted competition colours; one calendar mark per day (workout, then cardio, then today, then missed or planned); Weekly volume has no Front / Back toggle | |
| 2026-11-15 | Open decisions and contradictions | The measurement camera is the app's PoseCamera over forge_camera; the splash is Forge's SplashScreen; the macros calculator uses Forge's Slider; Today's missed day hides Start until it is answered; photo poses are Front, Right side, Left side, Back; the paywall keeps three layouts; a cardio session opens its detail page; the step goal is typed in place; Restore's result is a snackbar and a success closes the paywall | |
| 2026-11-15 | Asked afterwards | Delete account opens its page, then a dialog; a custom exercise's page has no history card; while one sign-in runs the other options are off | |
| 2026-11-15 | Workout screen | Finish shows its loading state; "last time" is the best working set; the progression hint; per-workout Rest time and Warm-up sets in the exercise menu; a set picked during a rest can be entered; the panel offers Finish workout once every set is done; swapping with done sets keeps them; the workout note is a card opening a sheet; the plate breakdown covers a weight the plates cannot make, one below the bar and one at the bar; Log set is always on (2026-11-18) | |
| 2026-11-15 | Workout summary, Add past and Edit workout | The summary is its own page whose back does what Done does; its figures compare with the program day's previous workout; a free workout offers Save as program, a program day only saving its changes to the day; adding and editing a past workout are one page, opened from the calendar after a date, time and duration sheet; a past workout has no name field | |
| 2026-11-15 | Tab screen steps (Today, Programs, Profile, Exercises, Progress) | Today: the rest-day card offers starting the next day early; after training, a done block with the summary over the next day; a running workout shows its position and time. Programs: the band lists the week's days by state; a finished program offers Run it again and New program; a locked Premium copy keeps its band with a Premium-ended notice and no Change days. Profile: the header names the user or invites a guest to create an account; new settings Rest sound and vibration, Keep screen on, Bar and plates, Connected apps; a notifications-off notice leads Reminders. Exercises: the tab's search opens the list page; a search with no match offers a custom exercise with the name filled in. Progress: the Body band opens Body and carries Log weight and Measurement day; the measurement-day prompt | |
| 2026-11-15 | Exercise pages | List: a muscle picked on the model is a removable filter with a Main / Also works split; count and sort on one line; filters and sort are kept. Detail: a custom exercise shows only how it is logged and its equipment. Add to program: a full day cannot be picked; no programs asks to create one. Picker: a count with the limit of 40; a custom exercise created there comes back chosen; Swap and Replace list up to eight similar exercises first | |
| 2026-11-15 | Program pages (detail, ready-made, generator, builder) | Detail: Start program asks to replace the active one, then the training days; day cards open and close, the next day open; a locked copy's Start opens the paywall. Ready-made: search by name together with the filters; a locked program lists only its days' names and counts; starting offers the user's copy first and makes the copy only once the days are picked; Duplicate opens the builder on the copy. Generator (rebuilt 2026-11-22): full screen above the tabs on onboarding's question page with a page counter. Builder: optional length; adding a day opens Rename; the day menu hides what cannot apply; deleting a day with exercises asks; leaving with changes asks | |
| 2026-11-16 | Forms | Custom exercise and the filters pick muscles, equipment, pattern and level on check sheets; My equipment's picker stacks over the filters; Only my equipment opens the picker first; a warm-up row's error names the invalid field; Log weight starts at the last weigh-in; Measurement day's weight step cannot be skipped; Estimate body fat without sex or height leads to Your profile; with the camera off only skipping the photo is offered; Log cardio needs a duration and types its numbers in a sheet; height in ft in is typed as feet and inches; number questions keep their controls near the thumb | |
| 2026-11-16 | Calendar, Workout detail, Cardio, Steps | Calendar: the month always open and browsable ahead; the list follows the month shown, no older-workouts button; All / Workouts / Cardio filters list, marks and count; holding the program's next day moves it within the week; tapping a date scrolls to its rows. Workout detail: Edit and Delete off while waiting to sync; records are the ones the workout still holds. Cardio: the week band, a 12-week minutes chart, sessions by week; health-store sessions are tagged and cannot be changed. Steps: a goal in steps of 100; This week / Last 30 days; separate states for asking, refused, store missing and failed | |
| 2026-11-16 | Body, Weekly volume, Strength | Body: three figures with their change since the measurement day before; weight coloured by direction to the target, neutral without one; up to three chart series; daily weight under its 7-day average; older ranges are Premium; Compare with Previous, First or another date; the measurement summary opens after a new day is saved. Weekly volume: every muscle listed; a muscle's sheet shows where its sets came from and its 12 weeks; the 12-week trend is Premium. Strength: another exercise replaces the page; all five records with date and set; sessions open the workout | |
| 2026-11-17 | Setup, account and subscription | Splash: a failed start offers Retry, a slow start says so after 2 s. Onboarding: the health step also shows when access was refused or is undetermined and hides without a health store; a denied reminder goes on silently; the suggestion has no "Not now" and its Start saves the copy without starting it; "Why this one" names only the answers the program matches. Sign in: server email errors under the field; no guest option for a guest; full screen from Profile; the guest sheet is Forge's LinkAccountSheet. Account: Data says backed up or waiting, no time; Subscription opens the paywall when free, Manage when Premium. Paywall: layout C, Yearly first, the full renewal terms under the button; no prices or no store shows a disabled Subscribe; a pending purchase's Got it closes it. Generator preview: Swap opens the picker's Swap form, Change sets and reps the builder's targets sheet. Calculators: inputs are rows opening a number sheet, the unit inside the box; a missing input shows the missing result; lose 0.5 kg or gain 0.25 kg a week (lb users 1 lb and 0.5 lb); five activity levels | |
| 2026-11-18 | Delete account's sign-in check | A user without a password confirms with their provider in the same dialog and deletion goes on by itself; a user with a password also gets a button per linked provider; the divider is Forge's OrDivider; another account brings the dialog back; a user with Apple linked confirms with Apple, which revokes the app's Apple sign-in | https://claude.ai/artifact/NWzAVU8uZU6aUd9JdYx3w1 |
| 2026-11-18 | Screen review | A workout open 4 h ends itself at its last set with a notification; notification permission is asked at the first workout's Start; the dark featured card keeps its fill; the app is named "GetWorkout" everywhere; the Live Activity shortens names, never the set count or time; analytics and crash reports stay asked; the target-weight step has its own title and a marker of the current weight; Today with saved programs but none active points to them; an Apple user's header says so; a trend with one entry is hidden until the second; holding a chart bar shows its value; with no rest running the effort question stays until answered, and Settings can turn it off; onboarding skips the reminder step when notifications are already allowed | https://claude.ai/artifact/LTkRmeAmV7YSz6MdZJeS66 |
| 2026-11-18 | Screen review, follow-up | A self-ended workout's summary has Edit in the app bar; the analytics step follows the target-weight question and is drawn as a permission step; an equipment row selects on a tap and its info button opens the set's items; at large text the workout header grows and stacks; a card header's detail that does not fit moves under the title | https://claude.ai/artifact/3968osDfaNKbbUwkmvXVXL |
| 2026-11-18 | Standards | Effort choices are Off, By feel (default), RIR, RPE; Forge SectionLabel for every section heading; every single-choice list is ChoiceGrid's list form; EmptyView and ErrorView get a card form; a Forge IconButton; two in-page heading sizes; every set circle and group letter is a SetBubble; PermissionPrompt's dialog form for in-app asks; Progress's Strength and Cardio cards are StatTiles | https://claude.ai/artifact/144uTPX6c94VzNPSEDrtS6 |
| 2026-11-18 | Tabs | Each tab has one job: Today is now, Progress how it is going, Programs the plan. The week strip and this week's sets only on Progress; a program day starts from Today and from its row on the program page (2026-11-27: the owner dropped "only from Today"); a missed day is asked only on Today; steps only on Progress; with no active program the ways in live on Programs, Today offers one; Start empty workout only on Today, every day; calculators only on Today | https://claude.ai/artifact/NcABYovwub3DiYhWgVFgAa |
| 2026-11-18 | Decisions 5 | Strength's exercise sheet is radio rows, a removed exercise a normal row; a strength change is coloured by direction; equipment matching no set selects no row and gets its own line with Edit; the compact weekly sets card shows bars, no body models, and is gone from the Programs tab; a tap on the active program's band opens its page | https://claude.ai/artifact/SY61cw8E47RXMbs2vKFem9 |
| 2026-11-18 | Colours 6 | The muscle heat map is one green scale by weekly sets, full at 20, with no red or outline above it; volume bars everywhere use the below / in / over band colours; model, legend and bars share 10 and 20 sets; the Exercises tab's hint is a tip that goes for good | https://claude.ai/artifact/PZUvzt8A5QH2MKSRgeyCxx |
| 2026-11-18 | Exercise 7 | Models without a heat map use the green family, main and secondary; only the search pill flies between the tab and the list; similar exercises split into Variations and Alternatives; favourite stars are muted when off, accent when on; Compare without photos gets a "Later day" button | https://claude.ai/artifact/4aGCQch1LfGQFd78xFe3Fh |
| 2026-11-18 | Exercises 8 | On the list only the search and filter button stay pinned, a summary chip standing in for what scrolled away; the picker's Add form covers the tab bar, Swap and Replace stay in their tab; analytics consent and New exercise stay full pages | https://claude.ai/artifact/LACjPRwMzutXTieTMxgQZS |
| 2026-11-19 | Programs and Profile | A running program day's row says so and resumes; a free user's Premium card is light, with the trial, three benefits and Get Premium; a program, workout or day name stays on one line, shrinking before it is cut; the active program's page shows its days, next day, week and this week's count, no Start; Ready-made programs lists the active program first, opening the user's copy; which sheets take the focus on open | https://claude.ai/artifact/WmZQNYSPgohJ4y3wJSmR6w |
| 2026-11-19 | Live Activity and workout page | Lock screen while a set is due: position, exercise, set and a dot per set, no workout name; during a rest the countdown with −15 s, +15 s and Skip working without opening the app; the compact island shows an emptying ring during a rest, the expanded one the countdown without buttons; the workout opens full screen from the bottom and a drag down minimises it | https://claude.ai/artifact/P7BEPoJoM524GsYGfBnqn6 |
| 2026-11-19 | Programs, double entry | The "No active program" card has no button; Ready-made programs, Generate a program and New program are rows below it, each once | https://claude.ai/artifact/YaFwy2eH5tHzVFa1H1pNAn |
| 2026-11-19 | Exercise buttons | The exercise page has no bottom bar; Add to workout and Add to program, and a custom exercise's Edit and Delete, are in the app bar's menu | https://claude.ai/artifact/TDYNW9cLpTVgihVFauueeN |
| 2026-11-19 | Widget proposals | The Body card shows change and body fat beside the weight and labels its line's ends; Weekly volume shows done of planned sets and a key of its bands; the Strength card adds the 12-week e1RM line; the Cardio card adds Mon–Sun minute bars; the summary's top card shows each figure's difference from the same day's last session; the active program's bar has one segment per week | https://claude.ai/artifact/NrdtEdUxNYu39V78ArNteh |
| 2026-11-19 | Training days | Starting, running again, changing days and starting a ready-made program open one Training days sheet: a card per program day with weekday chips, a weekday holding one day | https://claude.ai/artifact/PbEWe754pHbYU5EJ2yrzsJ |
| 2026-11-20 | Training days, Simple and Custom | A Simple / Custom switch tops the sheet; Simple picks exactly as many weekdays as the program has days; Custom is the per-day sheet | https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ |
| 2026-11-20 | Release readiness | Update required is a one-button page; an update offer is a sheet once at start; maintenance is a page with Try again; verifying the email is detected by itself and a wrong address is changed on the same account; Help & feedback takes a message and an email; the review question is a dialog over the summary that also thanks and offers writing to us; RevenueCat's Customer Center with a one-month-free offer at cancel; a win-back tag on the plan cards; the dark body model sits halfway between surface and ink; explicit consent for body data dropped. Days per week: an info line and a Recommended tag, nothing preselected, 3 / 4 / 5 days by level | https://claude.ai/artifact/Amg5tFCLKJ8uWExrsVeMBZ |
| 2026-11-20 | Review prompt and the workout paywall | A free user's summary that asks for a review still leaves through the workout paywall: the ask while the summary shows, the paywall on Done. | https://claude.ai/artifact/CayPEwTYFTHCX55XSMU3Nx |
| 2026-11-21 | Program recommendations | Scoring as under Feature notes › Programs; the catalogue opens filtered to the user's equipment type, a custom set counting as the most similar preset; one "Recommended for you" section of up to three, not repeated below; chosen filters lead the chip line; the default filter counts as a filter; onboarding suggests the best match even when Premium, started through the paywall, and closing that paywall skips onboarding's own | https://claude.ai/artifact/GXnoUesKKgM9SRiYhLgc6Y |
| 2026-11-21 | Admin dashboard reports | Ten tiles over Growth, Funnel, Retention, Revenue, Usage and Quality, for 7, 30 or 90 days or a custom range, each with its change against the period before. | https://claude.ai/artifact/DNxPob6inYxQPTGwLVC6mJ |
| 2026-11-21 | Admin rework, batch 1 | A left menu in groups (People, Content, App), opening on Dashboard; the user page's actions; Support inbox and App settings pages. | https://claude.ai/artifact/7RmvEGrnT11YfeSrT9BTjm |
| 2026-11-21 | Admin rework, batch 2 | Exercises and Programs as tables with a filter column and a one-line health summary; editors with Save, Save as draft and Retire. | https://claude.ai/artifact/UJtdhzsgjvYbztAkNpArUb |
| 2026-11-22 | Test findings | With Health connected an empty cardio card offers Log cardio; a weight more than double the last set asks first; a program card's name wraps beside its tags; the number keyboard's Next / Done bar is removed | https://claude.ai/artifact/QuWYHPgfjm3cqTpV9eNai3 |
| 2026-11-23 | Workout summary redesign | Records as one highlighted card with the gains; front and back models over the four busiest muscles; each exercise's sets as a table, two shown and the rest behind a "more" row | https://claude.ai/artifact/EAeojwrrTVCeAdhA58w1Qe |
| 2026-11-23 | App icon and launch | The owner's logo, two PNGs in `design/logo/`: the dark one is the app icon, the light one the launch screen; the native launch screen and the splash show it identically, so the handover does not move it | https://claude.ai/artifact/QuWYHPgfjm3cqTpV9eNai3 |
| 2026-11-24 | Screen review | Today's calculators are one row; mono only for counters and table values; a program's weekly sets list the major muscles first in a fixed order; Change days and Stop move into the program menu, ordered Change days, Edit, Duplicate, then Stop program and Delete; a recommended row carries only its Premium tag, the match line once under the section title; Finish is a text button, Log set the one filled button; an empty Cardio card has no dash; Steps without Apple Health offers Connect; Profile groups: Your profile alone after the Premium card, help with the privacy rows last, Appearance without a row title, the rest timer's settings on their own page; the paywall gives each of its two benefits an icon and a line, and Yearly shows its monthly price and a computed saving; admin pages use one page header; the admin Exercises table shows the id under the name | https://claude.ai/artifact/TzXAmphdUeRWsqFSZ5Cym4 |
| 2026-11-24 | Admin fixes after the dev check | App settings' cards start under the page header, left-aligned, at one width | https://claude.ai/artifact/UizB3AJdRYCzcjfzQJ5pm2 |
| 2026-11-24 | Admin announcements and simulator | Compose opens with the audience (Everyone, Free, Premium) and a Now / Schedule choice in the admin's local time; the confirmation names the audience and time, a scheduled one can be cancelled until then; history lists Scheduled first with Cancel, then Sent; the generator simulator's weekly sets are two columns of bars with a mark at each muscle's target | https://claude.ai/artifact/6Jg7vHHUGovZYiCsuiShJq |
| 2026-11-25 | Language setting | Language sits under Week starts on in Appearance; the sheet lists each language in its own name | https://claude.ai/artifact/F51NiEKmssC2zSSXk8b3Ba |
| 2026-11-25 | Exercise gear | Gear stays in neutral tones, colour only on muscles; the barbell has thick sleeves and two plates a side; the flat bench is a pad on a beam; the pull-up bar has no posts; a light floor with the body's shadow under every model; smith machine, squat box and landmine approved as drawn | https://claude.ai/artifact/6oF4mJVecSe7n2gtZyZ5fW |
| 2026-11-25 | Exercise animations | Every exercise gets its correct form and each mistake a pose can show; the exercise page's first card has Movement and Muscles tabs; a chip for the correct form and one per mistake, the picked mistake playing in place with its region marked; the workout's open card gets a play button opening a sheet with the animation, cues and a link to the page | https://claude.ai/artifact/RGTHJ9yhTVxSxnX1LG3ZL2 |
| 2026-11-26 | Exercise page | The picked mistake chip fills in danger, the others tinted, the correct-form chip green; chips sit right under the animation with the text in a fixed two-line place below; pause / play and half speed buttons, in the workout's sheet too; a hint for turning and zooming, no view buttons; the workout card's play button is filled | https://claude.ai/artifact/Y8sMp2DB83WX6ga5MhbCvW |
| 2026-11-26 | Exercise screen review | The own note is removed; Setup and How to do it share one card; each common mistake carries its chip's number, and one with an animation plays it from its row; the Safety card takes the warning tone; half speed looks filled while on; Tips get a title icon; each similar exercise is its own row with See all; the favourite star sits in the app bar beside the menu. Without a board: a mistake without an animation leaves a gap in the chip numbers | https://claude.ai/artifact/Gp3cZ7kU1JMSZ5TG59rXGn |
| 2026-11-27 | Exercise page redesign | The animation is a full-width 380 px stage under the app bar, Movement / Muscles on the stage; under it a swipeable card per form (the correct form with its cues, each mistake with its line and region; swiping plays that form) replaces the chips and their line; then How to do it, Mistakes and Details tabs; the info table stays its seven rows; no personal records on the page. Not built yet | https://claude.ai/artifact/GEGQYC6oV96g6h38z6BLmC |

Rules still binding that the studio does not show:
- Colours stay muted and black is not a default accent; the plates'
  competition colours are the one accepted exception.
- Forge owns the theme engine, type scale, controls, cards and feedback
  states; the app keeps what is about its product (set bubbles, the set
  panel, exercise cards, what calendar marks mean).
- A form that edits something has Save in the top bar; an action that ends
  or starts a flow is a full-width button at the page's bottom, in the
  Scaffold's bottom bar so a snackbar sits above it.
- Choice pickers open as bottom sheets, a time as the system picker;
  confirmations stay dialogs, whose Cancel is the secondary button.
- A locked control stays in full colour with a lock and opens the paywall.
- Every menu row has an icon.
- Loading is shown inside each component that loads, never a page spinner.
- A state no board draws uses the components' standard forms (EmptyView,
  SectionCard's loading and error, the button's loading, a snackbar) and is
  drawn in the studio afterwards.
- A setting's default option is labelled "(default)".
- Dates carry the year only when it is not this year.
- Opening focuses the field in the workout, exercise and cardio note
  sheets, the Bar weight dialog, the plate dialog's weight and the
  builder's Rename dialog; Save as program, the new custom exercise page
  and the set sheet's note open unfocused.
- A widget with more than one reasonable look is picked by the owner from
  drawn variants (the forge's `workflow/design.md`).

## Feature notes

How each feature behaves, by area. Read the area of the feature you are
about to touch, and keep it true when you change it.
How anything looks, and every screen text, is in the studio and the ARB
files, not here.

### Subscription and paywall

- **Subscription wiring**: `forge_purchases`, entitlement `premium`. RevenueCat
  when this platform's public SDK key is passed with `--dart-define`
  (`REVENUECAT_IOS_KEY`, `REVENUECAT_ANDROID_KEY`; never committed), else the
  fake in debug and profile builds (a debug-only "Fake store" section on the
  Profile tab steers it), else, in release, the package's `UnavailableBackend`:
  nobody is Premium and the paywall says purchases are not available yet.
  The signed-in uid is the RevenueCat user (guests too; linking keeps it),
  identified at startup and on every auth change, retrying failures.
- **Premium gate**: `context.watchPremium()` gives unknown / free / premium for
  locks; `await context.requirePremium()` before entering a premium feature
  (`lib/features/subscription/presentation/premium.dart`). Unknown never shows
  a paywall or a lock. The client value is for UI only; paid data is
  enforced by `entitlements/{uid}` in the rules.
- **Client vs server Premium**: only `revenueCatWebhook` (live on dev and
  prod) writes `entitlements/{uid}`, so client Premium (fake or RevenueCat)
  and server access can disagree: the fake never reaches the server, and a
  real purchase reaches it seconds to minutes later. Features treat a
  server refusal of premium content as locked, whatever the client says.
  On dev, `tool/set_premium.sh` writes the entitlement for demos.
- **RevenueCat webhook** (`functions/src/revenuecat_webhook.ts`; what each
  event type writes and the `{reason}` every response carries, visible in
  RevenueCat's delivery log, are in that file and its tests, which use the
  docs' sample events). Contract:
  https://www.revenuecat.com/docs/integrations/webhooks,
  https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields,
  https://www.revenuecat.com/docs/integrations/webhooks/sample-events
  - Auth: the `Authorization` header must equal the Functions secret
    `REVENUECAT_WEBHOOK_AUTHORIZATION` exactly (the secret holds the whole
    value set in the dashboard, e.g. `Bearer <random>`), else 401. Neither
    header nor body is logged. The function is public: RevenueCat has no
    Google credentials.
  - Only 200 counts as delivered; RevenueCat retries anything else about 5
    times over 80 minutes. So handled and deliberately ignored events (TEST
    and unknown types included) answer 200, and only an Auth or Firestore
    failure answers 500.
  - Sandbox and production events are treated alike: App Review and
    TestFlight buy in the sandbox against prod, and that must unlock server
    content. An event for a uid the project's Auth does not have (the other
    project's, a deleted account) is skipped and its `entitlements/{uid}`
    deleted; anonymous RevenueCat ids are never written.
  - Grants and refunds: only events naming `premium` count (the temporary
    grant names none). A grant never shortens Premium already known. A
    cancellation keeps Premium to the end of the period; only a refund
    (`cancel_reason` CUSTOMER_SUPPORT) or EXPIRATION ends it, and not when
    it is for a product other than the stored `productId` while the stored
    Premium still runs (a plan switch). A billing issue runs to the end of
    the grace period; a temporary grant lasts 24 h. A missing expiry is
    lifetime only for NON_RENEWING_PURCHASE. TRANSFER moves the old uids'
    known Premium to the new uids.
  - Order and redelivery: events may arrive late, out of order or twice
    (`lastEventMs`, `lastEventIds` on the document): a newer event replaces
    the state, an older one only extends Premium still granted, and one
    already applied is a no-op.
  - Not done: RevenueCat recommends fetching `GET /subscribers` after each
    event instead of trusting the payload; that needs a secret REST key and
    would fix the payload's blind spots (a transfer from an anonymous id or
    a deleted account, e.g. a restore by the new guest after deleting the
    account, grants the server nothing until the next renewal; two
    concurrent subscriptions are tracked as one `productId`).
- **Paywall moments** (2026-11-19): besides a Premium feature
  (`requirePremium`) and Profile's card, the app offers the paywall by
  itself at two moments. `onboarding`, once per user: when the program
  suggestion is left, whichever way (Start, See other programs, or nothing
  to suggest). `workoutDone`: when the summary of every third workout from
  the first (the user's finished-workout count is 1, 4, 7 …) is left by
  Done, back or Open programs, not by Edit, which goes on to fix the
  workout (2026-11-24); the paywall shows first, then the summary goes. An
  unknown count (offline) never shows it, except for a `firstEver`
  workout: one whose exercises had no stats while no stored workout is
  found (server, else cache; unreadable is not first). A moment shows only
  to a user known to be free whose settings have loaded; Premium, or a
  status still unknown, skips it unmarked. The once-per-user moment is
  marked shown at once in `settings.seenTips` (`onboardingPaywall`), so it
  follows the account across devices and reinstalls.
- **Hard paywall from the store setup**: the current RevenueCat offering's
  metadata decides whether the onboarding moment's paywall (and the
  app-open one below) can be closed: `dismissible` false (a JSON bool, or
  the string "false") removes close, back and the sheet drag until a
  purchase or restore; absent or anything else is closable. While the
  plans load that paywall has no close; a failed load is closable, so
  nobody is trapped. Every other paywall is always closable, whatever the
  metadata. Debug builds on the fake store switch it with "Offering
  dismissible" among the Fake store rows. Which installs get a hard
  paywall is RevenueCat's targeting, set up in its dashboard, not in the
  app.
- **Hard paywall for paid traffic** (2026-11-20): Apple Search Ads is
  asked once per install whether it came from a campaign: the AdServices
  token (iOS 14.3+, no consent or ATT needed) is sent from the device to
  Apple's attribution API (not ready yet: three attempts 5 s apart).
  Apple's final answer (the campaign id, or not attributed; a device
  without a token counts as not attributed) is kept on the device; with no
  final answer (offline, Apple down) it is asked again on later launches,
  but only while the signed-in user is not past onboarding. After the
  RevenueCat user is identified (once per uid and launch) the kept answer
  is applied to it: if attributed, the custom attributes `ad_network` =
  `apple_search_ads` and `ad_campaign_id` = the campaign id are set and
  the offering is reloaded, so RevenueCat's targeting rule serves offering
  `hard` (the packages and products of `default`, metadata `{"dismissible":
  false}`): the soft paywall's page, plans and trial without close and
  back. An offering load waits up to 5 s for an attribution in progress;
  slower, failed, not attributed, Android and the fake leave the soft
  offering. Not attributed never clears the attributes. RevenueCat's own
  collection (`enableAdServicesAttributionTokenCollection`) is on too, for
  its charts only: it answers within 24 hours, too late for this paywall.
  Which campaigns get the hard paywall is the targeting rule's list of
  campaign ids, changed in the dashboard without an app update; a device
  in developer mode gets Apple's test record, campaign 1234567890.
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
    questions): App Privacy gets Usage Data › Advertising Data, linked to
    the user, purposes Analytics and App Functionality, not used for
    tracking; no ATT prompt, no `NSUserTrackingUsageDescription`, privacy
    manifest unchanged (AdServices is not a required-reason API). The
    privacy policy should say that installs from Apple Search Ads are
    recognised to choose the subscription offer.
- **Hard paywall on every app open** (2026-11-20): the onboarding moment
  is marked shown before it opens, so killing the app on it must not let a
  hard-offering user in for free. The paywall opens at moment `appOpen`
  (never marked in `seenTips`; the offering's metadata decides whether it
  closes) when an open is due: each launch, each return from the
  background, each time the entitlement turns inactive and each time this
  paywall is gone without Premium (a `go` from a notification tap, a
  redirect, a failed load that let it close). A due open waits until every
  open page is past the start (onboarding and its paywall, the
  verification page, the splash), the app gate shows no page, no account
  deletion runs and no other paywall is open. Premium ends it; an unknown
  entitlement waits; a free user's offering is loaded once: soft or failed
  ends it until the next due open, hard opens the paywall. A pending
  purchase keeps it open until approved and is not remembered across a
  relaunch.
- **Paywall** (`/paywall`, full screen): prices and trial are the store's
  (monthly 7.99 USD, yearly 39.99 USD with a 7-day trial on yearly only;
  the fake store's plans use these numbers). Yearly is listed first,
  whatever the store's order, and selected by default; a trial shows only
  when the plan carries one; restore and the legal links
  (`lib/app/legal_links.dart`) are always visible. Three plan layouts are
  kept for the A/B/C test, the rest of the page shared: A lists the plans
  as rows, B shows one card per plan side by side, C shows one plan
  (yearly) with a way to the monthly one. A pending purchase shows a
  waiting card whose dismissal closes the paywall (Premium unlocks by
  itself once approved); on a paywall that cannot be closed the card has
  no dismissal and the paywall stays until the approval brings Premium
  (2026-11-19). A successful restore closes the paywall; the result shows
  in a snackbar (2026-11-15).
- **Win-back offer** (2026-11-20): a lapsed subscriber the App Store offers
  a win-back (iOS 18+, Apple decides eligibility) sees the free month on
  every plan that carries one, in place of any trial or intro offer
  (Forge's `Plan.winBack`, set only when eligible); buying the plan
  applies it. Everyone else, and Android, sees the paywall unchanged. The
  fake store offers its plans' free month once the user's subscription has
  ended ("End subscription now (win-back)" among the Fake store rows).
  - Not created in App Store Connect yet: it refuses until the subscriptions
    are approved (STATE_ERROR.NON_APPROVED_SUBSCRIPTION). After the first
    approval create one per plan: 1 month free, eligibility paid at least 1
    month and lapsed 1 to 12 months, no wait between offers, priority high,
    not promoted on the App Store.
- **Manage subscription** (2026-11-20): on iOS it presents RevenueCat's
  Customer Center (themed in the RevenueCat dashboard), whose cancel path
  first offers the "1 month free" promotional offer; a claimed month or a
  change arrives through the entitlement stream. Where the Customer Center
  cannot show (the fake store, an error) and on Android (until Play is set
  up) the store's manage page opens instead; if that fails too, a
  snackbar says so.
- **Paywall A/B/C test** (Firebase Remote Config + A/B Testing,
  2026-11-13; `forge_remote_config`): the Remote Config string
  `paywall_layout` picks the layout, `a` (list), `b` (cards) or `c` (one
  plan); the app's default is `a`, and an empty or unknown value is A too.
  Fetched against the build's project, at most every 12 h in release and
  every minute otherwise. Startup activates what an earlier launch fetched
  and fetches the next values in the background, so the layout is stable
  for a session, a new install sees A in its first session and its arm
  from the second, and a failure only leaves the defaults. Debug builds on
  the fake store override it with the "Paywall layout" Fake store row.
  Events: `paywall_view` {`layout`} once per paywall open, when the plans
  first show to a user without Premium (the activation event);
  `paywall_purchase` {`plan`: `monthly` or `yearly`, `layout`} on each
  purchase or trial start that granted Premium on the paywall (the goal);
  a pending purchase approved later and a restore are not counted. Events
  follow the analytics consent below: prod counts release builds only, for
  users who did not turn "Share usage data" off. Remote Config itself is
  fetched for every user, whatever that switch says (2026-11-13): such a
  user gets a layout but is never measured, and the privacy policy says
  so. The parameter and the experiment are set up in the console.
- **Store set-up** (2026-11-20). App Store: group
  "GetWorkout Premium" with `getworkout.premium.monthly` (7.99 USD) and
  `getworkout.premium.yearly` (39.99 USD, 7-day free trial), 175
  territories, equalized prices; the Paid Apps agreement is active.
  RevenueCat: iOS app with the In-App Purchase key, entitlement `premium`,
  offering `default` ($rc_monthly, $rc_annual, metadata `dismissible:
  true`). Webhooks: sandbox → dev, sandbox and production → prod
  (TestFlight and App Review buy in the sandbox with prod builds; each
  project skips uids it does not know), each with its own
  `REVENUECAT_WEBHOOK_AUTHORIZATION`. TestFlight internal group "Team".
  Purchase, renewal, restore to a new guest, cancellation and expiration
  were checked on prod with TestFlight build 7 (2026-11-24, 2026-11-25).
  Promotional offers "1 month free" exist on both plans for the Customer
  Center's cancel path: `retention_1m_free` (monthly) and
  `retention_1m_free_yearly` (yearly).
- **App Store listing** (2026-11-22; screenshot canvas
  https://claude.ai/artifact/EbzyhQps5J6xmubwaEjA48): name "GetWorkout: Gym &
  Fitness Log", subtitle "Workout tracker & programs", keywords
  "fitness,workout,exercise,lifting,training,bodybuilding,muscle,body,plan,
  strength,weight,planner,log", description led by exercises and programs;
  Health & Fitness, Lifestyle; age 13+; copyright "2026 Yiğit Çuhadar". Seven
  1320x2868 screenshots (Exercises model, Workout logger, Programs, Weekly
  volume, Body, Today, Strength) captured from the dev app over
  `tool/seed_demo.dart` data; the paywall capture is both subscriptions'
  review screenshot. App Privacy: 16 types, all linked, none tracking; custom
  EULA = the Terms; review notes: guest sign-in, no demo account. Sold in the
  US, UK, Canada, Australia, New Zealand and Ireland only; iPhone only (#216).
- **App Store submission** (2026-11-24): version 1.0.0 goes with both
  subscriptions and manual release. The price is free, content rights "no
  third-party content", the regulated medical device declaration "No". The
  medical device declaration and attaching an app's first subscriptions to a
  version exist only on the App Store Connect website, not in the API.

### Account and privacy

- **Account page**: the Data row reads backed up when the server takes
  the device's pending writes within 2 s, so a normal write never flashes
  "Waiting to sync"; no time is recorded. The subscription row opens the
  paywall when free and Manage subscription for a subscription, nothing
  while checking or for lifetime Premium. A failed sign-out offers Retry,
  which signs out without asking again. A guest gets the guest card
  (create an account, or sign in to an existing one), the subscription row
  and "Delete my data".
- **Analytics consent** (`lib/features/account`):
  `settings.analyticsConsent` of each user, guests included (linking keeps
  it, signing in to an existing account takes that account's answer). Per
  user, never per device, and opt-out: false is off; true and null (never
  answered) collect. Never asked: there is no consent page; the "Share
  usage data" switch under Profile → Privacy saves an explicit true or
  false, and the settings feature never writes the field. Analytics and
  Crashlytics collect in prod release builds and, so events can be checked
  in DebugView, in debug and profile builds into the dev project
  (2026-11-20), for the signed-in user, with their uid as the user id;
  never the advertising ID, Android ID or IDFV, and no ad personalisation
  signals (the `AD_ID` permission is removed). Collection starts off
  natively (Info.plist, AndroidManifest.xml), so on a fresh install
  nothing is collected until the signed-in user's answer is known; later
  launches start from the answer that user last gave on this device.
  Whenever the signed-in user changes or is unknown, collection goes off
  until that user's stored answer is read, and stays off when the read
  fails. A missing answer counts as yes only from the server: a cached
  copy without one may predate a no from another device. Turning it on
  first deletes the crash reports recorded before it. A deletion underway
  does not follow consent, so the deleted document (read as no answer)
  never turns collection back on.
- **Privacy policy link**: Profile → Privacy, in the browser.
  `LegalLinks.privacyUrl` (`lib/app/legal_links.dart`) is the one place the
  address is written; the Android build reads it from that line into
  `R.string.privacy_policy_url` for Health Connect's
  `PrivacyPolicyActivity`.
- **Legal pages** (2026-11-22): `legal/` has privacy, terms, `kvkk.html`
  (the Turkish KVKK notice) and `support.html`, live on prod at `/privacy`,
  `/terms`, `/kvkk` and `/support`. The app links only the policy, which
  links the KVKK notice. Not reviewed by a lawyer. Decided: body data
  rests on performance of the contract, with no consent step; the
  controller is the owner by name and full address; Analytics retention is
  stated as 14 months; deleting an account leaves analytics and crash data
  until they expire (14 months; Crashlytics 90 days), the RevenueCat
  record, `revenueEvents` without the uid and the support email threads,
  and the policy says so; Gmail (getworkout.support@gmail.com) is named as
  a processor; the Firebase advertising-ID code stays linked and the
  policy says no advertising identifier is used for tracking; no KVKK
  standard contracts: the transfers abroad (Google/Firebase, RevenueCat,
  Apple) are listed; the Terms are the custom EULA with Apple's minimum
  terms; no VERBİS mention. `ios/Runner/PrivacyInfo.xcprivacy` declares
  UserDefaults CA92.1, no tracking and the App Privacy answers' sixteen
  collected types.
- **Deleting an account**: Account → "Delete account" ("Delete my data"
  for a guest) opens a page saying what is deleted, then a confirmation
  dialog. A store subscription is not cancelled. Steps: the router holds
  everyone in place, so the vanished profile cannot open onboarding and
  write the user's document again; the workout in progress stops keeping
  and syncing; the device's pending writes are sent (10 s at most; offline
  fails with nothing asked or deleted); the callable `deleteAccount`
  deletes. For an account with a credential it wants a sign-in from the
  last 5 minutes, else the app asks for a renewed sign-in (the password,
  or a button per linked provider) and tries again; a guest is deleted
  without that check. A user with Apple linked always goes through Apple
  first: the app signs in again with Apple and passes the fresh
  authorization code, with which `deleteAccount` revokes the app's Apple
  tokens before deleting anything (App Store 5.1.1(v)). It revokes with
  the `APPLE_SIGN_IN_KEY` secret (set per Firebase project before
  deploying `deleteAccount`), not Firebase's own revocation, which fails
  with `invalid-credential` on a device. A closed sheet, a failed Apple
  sign-in or a refused revocation deletes nothing. Once the server deleted
  the data, still signed in (so nothing of the next guest is touched), the
  app removes the user's kept workouts file, cancels every scheduled
  notification, records no consent for them, resets the analytics id and
  unsent crash reports, and marks Firestore's offline copy to be cleared
  at the next start; then it signs out and a new guest starts at
  onboarding. A local leftover is logged, not reported. If only the sign-in is
  left (the function's `details.reason`) the user stays held on the page,
  which offers only a retry. A function not deployed or not callable is
  shown as not available yet, never as done; anything else that failed
  before the data went gives the workout back.
- **Email verification** (blocking; `forge_auth`'s `EmailVerificationPage`,
  route `/verify-email`): only an email and password account must verify;
  Google or Apple next to it counts as verified, and guests are unchanged.
  Creating or linking an email account mails the link at once (a failed
  send still signs up; Resend covers it). Until verified the router shows
  the page instead of the app, at start too (existing unverified users
  included) and after signing in to an unverified account; once verified
  it goes on like the splash gate (Today, or onboarding).
  - There is no "I've verified" button: the page reloads the user every
    4 s while the app is visible, stops while it is hidden, and reloads at
    once when it shows again. Resend counts down 60 s from the last link
    this session sent, or after a `too-many-requests` answer; a page
    opened in a later session can send at once.
  - Changing the address from the page uses Firebase's
    verify-before-update-email on the same account (same uid, same data);
    the page then waits for the new address and Resend resends to it.
    `email-already-in-use` may not be reported with email enumeration
    protection on; the link then fails when opened.
    `requires-recent-login` is first answered by signing in again with the
    password this session used (kept in memory only, dropped on sign-out
    or deletion); without it the user is asked to sign in again. Signing
    out from there starts a new guest on onboarding and deletes nothing.
  - Confirming an email change revokes the session and Firebase signs the
    user out; with the password from this session the guest start signs in
    to the new address instead of a new guest. Without it (the app was
    restarted since) the user lands as a new guest on onboarding and signs
    in with the new address; the data stays on the account. Not checked on
    a device yet.
  - Email templates are Firebase's defaults in both projects (sender
    `noreply@<project>.firebaseapp.com`, the link handled at
    `https://<project>.firebaseapp.com/__/auth/action`, locale en). To
    customise later in the console (Authentication > Templates): sender
    name, subject and text, the action URL (a custom domain on Hosting),
    and a custom sender domain.
- **Hosting** (2026-11-20): `legal/privacy.html` and
  `legal/terms.html` are live at https://getworkout-prod.web.app/privacy
  and `/terms` (hosting target `legal` on prod; `firebase deploy --only
  hosting:legal --project getworkout-prod`). The admin panel is target
  `admin`: getworkout-dev.web.app on dev, the site
  getworkout-admin.web.app on prod, deployed with `tool/deploy_admin.sh
  <dev|prod>`. Contact getworkout.support@gmail.com, minimum age 13 (or
  the local age of digital consent), Turkish law and Istanbul courts.
- **Delete account, confirming with a provider** (2026-11-18): after a provider confirms, deletion goes on by
  itself, with no second tap. Picking another account in the provider's
  sheet brings the dialog back saying it is a different account. A
  failure on the Apple path never shows the password error: offline and
  a different Apple account keep their own messages, the
  password-looking codes (`invalid-credential`, `wrong-password`) and
  anything else show the delete failure, and a closed Apple sheet says
  nothing.
- **Google sign-in set-up**: Android's Credential Manager needs the signing
  certificate's SHA on the Firebase Android app; the debug keystore's SHA-1
  and SHA-256 are registered on dev.
- **App Check** (2026-11-20), monitoring first; enforcement moved after
  release (2026-11-24). App Attest is registered for the iOS app on dev and
  prod and nothing is enforced. Storage and the app's callables are enforced
  once the metrics show nearly every request verified; Firestore,
  `sendAnnouncement` and the other admin callables wait until the admin web
  build, which does not activate App Check, gets a reCAPTCHA Enterprise
  provider. `revenueCatWebhook` is an HTTP endpoint and stays as it is. A
  debug build prints its token in the native log; it is added under App Check
  › Apps › Manage debug tokens on dev, and a token lives per install.
  Enforcing is per product (API `services/<service>` `enforcementMode:
  ENFORCED`).

### App shell, settings and onboarding

- **Sex question with body models** (2026-11-21): onboarding and Your
  profile › Sex share one question, which shows the two body models. Every
  screen showing the body model shows the user's: female for a user who
  answered female, male otherwise. The models' Blender sources are
  `design/models/*.blend`.
- **Navigation** (2026-11-13): five tabs, Today / Programs / Exercises /
  Progress / Profile, each a branch of the shell with its own stack, kept
  alive and built the first time it shows. "Add to program" pushes the
  builder in the tab its exercise is in; a custom exercise's edit form
  opens in the Exercises tab from wherever its page is. The active workout
  is full-screen over the tabs and minimizes to a bar above them on ⌄,
  back, or a drag down on the grabber or the header. Tapping the open tab
  returns it to its first page the way back would. A `go` (a link, a
  notification tap) replaces its tab's stack (each tab is its first path
  segment), but a page there with unsaved changes (program builder, custom
  exercise form, workout edit, measurement day) is never dropped silently:
  one router guard (`lib/core/unsaved_changes.dart`) brings that page up
  (the workout or paywall above the tabs put away, the workout staying in
  its bar) and asks with the page's own discard prompt: keep editing stays
  there, discard makes the navigation again. Pages without changes, other
  tabs' stacks, pushes and tab switches are left alone. Back and the guard
  share one prompt per page, so nothing asks twice.
- **Navigation gestures** (2026-11-18): every pushed page is the
  platform's page route (`AppPage`, `lib/core/pages.dart`): on iOS the
  Cupertino slide with the left edge back swipe. Every pushed route needs
  a `pageBuilder`: go_router's page for a plain `builder` route has no
  transition and no swipe here. Tab roots and the start pages (splash,
  retry, onboarding, suggested program) have no transition. Pages over the
  flow (the paywall, the exercise picker's Add form) are an iOS sheet
  (`SheetPage`) that a drag down closes, from its list's top too, and keep
  a close button; on Android a full-screen dialog. A page that refuses to
  pop (unsaved changes) still follows the edge swipe; let go where it
  would leave, it springs back and the page's own prompt asks, as back
  does.
- **Profile tab** (2026-11-13): one page: the account header, the Premium
  card, Your profile, the settings groups (Units, Workout, Reminders,
  Connected apps, Appearance), Privacy and, in debug builds on the fake
  store, the Fake store rows. Every change saves at once; a failed save
  shows a snackbar.
  - An Apple relay address (`@privaterelay.appleid.com`) is never shown:
    a named user shows the name alone, and a user with no name and no
    other address who signed in with Apple shows as an Apple account.
  - A guest's header opens the guest account sheet (`forge_auth`); its
    email choice opens Sign in in create mode, which links the guest.
  - The Premium card opens the paywall for a free user and Manage
    subscription for a subscriber (trial, renewing, ending, payment
    problem); lifetime or granted Premium and an unknown status get no
    action.
  - Rest sound (`settings.restTimer.alert`: chime and vibrate (default),
    chime, vibrate or off): a rest reaching zero in the app plays
    `assets/sounds/rest_chime.wav` (generated for the app, no licence),
    mixed with other audio and silent in silent mode. The rest
    notification sounds the same: one Android channel per choice
    (`rest_chime_vibrate`, `rest_chime`, `rest_vibrate`, `rest_silent`),
    as Android fixes a channel's sound and vibration; iOS cannot vibrate
    without a sound, so Vibrate is silent there. Keep screen on
    (`settings.keepScreenOn`, default on) holds while a workout is in
    progress.
  - Connected apps: the health store (Apple Health, or Health Connect),
    On / Off from step access, read again on resume; On opens the store's
    settings, Off the Steps page (which explains before asking); hidden
    without a health store.
- **Start and sign in** (2026-11-17): the splash shows its slow-start line
  after 2 s; a guest session that cannot start shows the failed splash
  with Retry. On sign in, email errors that belong to a field show under
  it, the rest as one retryable error; "Continue as guest" shows only with
  nobody signed in, so never for the app's guest. Pushed from Profile or
  Account (`/profile/account/auth`) sign in opens full screen over the tab
  bar.
- **Units**: stored metric; kg/lb and cm/in chosen by the user. A single
  lifted weight that matches the user's unit within two decimals was typed
  in this unit and shows as typed; otherwise it was typed in the other
  unit and shows rounded, to whole lb (80 kg → 176 lb) or half kg (45 lb →
  20.5 kg), or to two decimals when that would show a positive weight as
  0. Display only: fields store what is typed, converted to kg; an
  untouched field stores nothing, and typing back the number a field
  showed keeps its stored kg. The estimated 1RM is computed, so it always
  shows rounded the same way; volume, body weight and the calculators keep
  their own formatting.
- **Week start** (2026-11-13): the whole app uses one first day of the
  week, in every weekly view, chart, strip and weekday list, the program
  week plan (and so the done days the workout reminders know) and the
  measurement reminder's day. Settings → Appearance → "Week starts on":
  Automatic (default), Monday, Sunday or Saturday (`settings.weekStart`,
  written only when not automatic). Automatic is the phone's region, not
  the app's language: the device locale, followed on change. With a
  region, CLDR's weekData `firstDay` for it (CLDR 49, a const table;
  unlisted regions Monday): `en_TR`, `tr_TR`, `en_GB` Monday, `en_US`
  Sunday, `ar_EG` Saturday, `MV` Friday (only Automatic can give Friday).
  Without a region, the language's first day in intl's date symbols, else
  Monday. A new week start moves the program week plan once the new week's
  done days arrive, keeping the known ones meanwhile, and not while the
  list shows a failure. Only views change: stored dates, program weekdays
  and schedules, `nextDate` and program lengths (counted from the start
  date) never depend on it.
- **Language**: Settings → Appearance → "Language": Automatic (default),
  English or Türkçe, each language in its own name, never translated
  (`settings.language`, `en` \| `tr`, written only when not automatic;
  absent or unknown is automatic, so per user like the week start, and
  automatic while signed out). Automatic is the phone's first language the
  app has, else English. The app switches at once with no restart, and
  everything that reads the language follows the choice: content, the
  generator's `lang`, dates, numbers, and the notification, lock-screen
  and self-ended-workout texts. Reminders are written and the announcement
  topic followed in the user's settings' language, again when it changes;
  while a signed-in user's settings load nothing is followed. Not routed:
  the Android channel names (made at start, in the phone's language), the
  week start (the phone's region) and the support details' `locale` (the
  phone's).
- **Onboarding questions** (2026-11-13; design pass 2026-11-17): a welcome
  page, then one question per page, all nine needing an answer: goal,
  level, days per week, equipment, sex, birth year, height, weight, target
  weight. There is no skipping and no closing summary; the last question's
  button ends the questions. A ruler or wheel has to start somewhere
  (170 cm, 70 kg, age 30), so a number question counts as answered when it
  shows; the target weight follows the weight until the user picks one.
  The link to an existing account shows on the welcome page for a guest
  only. In Your profile every answer can be changed but not removed.
  - Equipment: a row picks its set (the equipment profiles, see Exercises
    and content); a set's details sheet lets the user untick and tick
    single items and picks the tuned set. Equipment that matches no set
    selects no row and shows as custom equipment with its item count
    (bodyweight aside), editable in the same sheet; items that now match a
    set select its row, and picking a set replaces them. The generator's
    equipment question is the same.
  - Permission steps after the last question: training-day reminders,
    only while the device does not let the app notify yet (already
    allowed, the step is left out and the reminder stays as it is):
    accepting asks the system and, if allowed, turns the workout reminder
    on at its default time; refused or declined moves on silently. Then
    steps and cardio from the health store, wherever one exists and steps
    cannot be read yet (never asked, refused or, on iOS, undetermined):
    Connect asks where the system still can (never asked; Android refused
    asks again) and otherwise opens the store's or the app's settings;
    Skip moves on. While a step waits on the system's prompt neither
    button takes a tap, so a slow prompt is never asked for twice.
  - The suggestion page shows the recommended program with why it fits
    (the user's goal, days and equipment set that the program matches, an
    unmatched answer left out) and has no "Not now". Start saves a copy
    among the user's programs without starting it and opens its page; the
    user's existing copy opens instead. On a locked premium program Start
    opens the paywall: subscribed, Start waits until the program unlocks,
    then saves it and goes on as above. When the server has not unlocked
    it by the end of the detail cubit's retries (about 14 s; the webhook
    can take longer, and the fake store never reaches it), or the days
    cannot load, Start stops waiting with a snackbar and a tap reads the
    days again (2026-11-27). Closed without subscribing, the
    suggestion is passed like leaving it (onboarding completes, Today,
    nothing saved) without the onboarding paywall, since one was just
    closed (2026-11-21).
  - Finishing onboarding also logs the weight answer as the user's first
    weigh-in, dated then, so Body is not empty afterwards; nothing is
    logged when the user already has a weigh-in that day, so a retry never
    adds a second one.
- **Days per week recommendation**: the days question recommends the days
  most lifters at the user's level train (beginner 3, intermediate 4,
  advanced 5) and tags that row. Nothing is preselected: the user still
  picks, and a saved answer stays the one selected. Onboarding uses the
  level just answered; Your profile › Training days uses the saved level.
  With no level known nothing is recommended.
- **Birth year**: a plausibility range (age 13-100), not an age gate. An
  implausible year is only not accepted as an answer; nothing is blocked.
- **First-use tips**: four inline banners (`TipBanner`, never modal), each
  dismissible, none until the user's settings have arrived: effort, inside
  the effort question the first time, until it is dismissed or an effort
  is picked; set types, at the top of the add-set sheet, until a type is
  picked there; automatic warm-ups, at the top of the workout in progress
  once warm-ups were added to it automatically, until the setting is
  changed; the body model, under the Exercises tab's model once it has
  loaded, until it is dismissed or a muscle is opened from the model.
  Dismissing or using the thing marks it seen for good, in
  `settings.seenTips` (codes `effort`, `setTypes`, `autoWarmups`,
  `muscleModel`; the paywall moments use the same list; the app has no
  local flag store, and this follows the user across devices). Tips are
  only ever added to that list (`arrayUnion`), never written with the
  other settings, so two devices and codes from newer versions are kept.
- **Explanations for beginners**: each set type has a one-line description
  in the add-set sheet and the bubble's long-press menu. The set bar names
  the kind of set in words (warm-up 1 of 2, drop set 2 of 3; the lock
  screen and rest notification follow) and shows a warm-up's or drop set's
  description. A help button next to the effort question and row opens
  one help sheet: what effort is and what the app does with it, every step
  of the user's scale, Failed, warm-up sets (with the automatic ramp) and
  drop sets.
- **Update and maintenance gate** (2026-11-20; `forge_app_gate`): three
  rules from Firebase Remote Config, checked against the installed
  marketing version (`1.2.0` of `1.2.0+7`; the build number is not
  compared, since a store release always raises the version).
  - Keys, all with in-app defaults that ask nothing, so an absent key
    never blocks: `min_version_ios`, `min_version_android`,
    `recommended_version_ios`, `recommended_version_android` (strings,
    default `''`: a version such as `1.2.0`; missing parts are 0, a value
    that is not a version asks nothing), `maintenance` (boolean, default
    `false`, one switch for both platforms; per platform only through a
    console condition) and `maintenance_message` (string, default `''`:
    the app's own text; a language is added later with a console
    condition on the device language). Created on getworkout-dev
    (2026-11-20, group "App gate", "use in-app default"); not on prod
    yet.
  - Order: maintenance first (an update does not help while it lasts),
    then the minimum, then the recommended version.
  - Below the minimum the app is replaced by a page whose only action
    opens the store (`https://apps.apple.com/app/id6836913044`,
    `https://play.google.com/store/apps/details?id=com.getworkout.app`).
  - Below the recommended version (and at or above the minimum) a sheet
    offers the update, at most once per launch. Update closes it for this
    launch only; any other way of closing it dismisses that
    `recommended_version_*` value for good (`app_gate.json` in the app
    support directory); a new value offers it again.
  - While `maintenance` is true a page shows `maintenance_message`, or the
    app's own text, and a retry that fetches Remote Config at once.
  - When: startup checks before `runApp` from what the last launch fetched
    (local only, so offline the app opens as before), then the rules are
    fetched in the background, on every resume and on the retry, ignoring
    the 12 h fetch interval; a failed fetch keeps the last rules. Only the
    gate's keys take a fetched value mid-session; `paywall_layout` keeps
    one value per session. The app stays mounted under a gate page and
    comes back as it was.
- **Android** has never been built or run with the changes since the rest
  timer; CI does not build it, and Forge runs no Android check until the
  Android release is prepared. The first build needs Android platform 37 and
  AGP 9.1.1 downloaded. Unbuilt and unchecked until then: the steps changes
  (minSdk 26, `FlutterFragmentActivity`, `PrivacyPolicyActivity`), the camera
  manifest changes and backup rules, the FCM manifest entries (default
  channel, icon, auto-init flag; an announcement to a fresh install must land
  on the `workout` channel), and the workout's ongoing notification (workout
  and rest modes with the app in front, in the background and killed, with and
  without exact alarms; no duplicate after a relaunch; removed on finish,
  discard and sign-out; the Android 16 status bar chip; taps).

### Exercises and content

- **Exercise sync**: clients read `exercises` of every status, so a
  retirement or a return to draft is noticed by the incremental sync on
  `updatedAt`, and filter to `live` on device. A cache whose document count
  differs from the server's `count()` is rebuilt with a full fetch.
- **Content ownership**: Firestore is the source of truth for content once
  it is seeded. `content/*.json` is the seed and the bulk-edit path;
  the admin panel edits Firestore directly and leaves `contentHash` alone, so
  the import skips (and fails on) documents edited there unless `--force`.
- **Exercise coverage** (`tool/coverage_report.dart`): prints the live
  library by muscle, equipment, equipment profile, level and pattern, and
  its gaps and text defects; it exits non-zero only when the files do not
  validate. The server generator's rules are checked by
  `generatorRulesCheck`. The seed has 422 exercises, 419 live (content
  review of 2026-11-21). Kept on purpose: the weekly-set warnings of the
  arm focus, glute focus, calisthenics and kettlebell programs and of
  Bodyweight Progressions' side delts and biceps (each is a focus or
  equipment-limited program whose summary says so); hammer curls' main
  muscles are biceps and forearm (brachioradialis is filed under forearm);
  pike and handstand presses list mid delt as secondary like every other
  overhead press.
- **3D model**: our own renderer, written in Dart. A body model has 36
  meshes: 18 muscle groups (left/right split except abdominal) plus the
  body; `body_male.glb` and `body_female.glb` share the mesh names, and
  the app loads the one of the user's sex. The exercise page shows it
  twice, front and back side by side with the worked muscles coloured,
  both fixed so the page scrolls over them; the Exercises tab's model
  stays interactive.
- **Equipment profiles**: one list (`EquipmentProfile`) serves
  onboarding's quick picks and the catalogue's `equipmentProfile`. Full
  gym = everything; home gym = barbell, plates, dumbbells, bench, pull-up
  bar (a barbell at home implies a rack, which has no code); dumbbells =
  dumbbells and a bench; bodyweight = pull-up bar and dip bars; bands =
  resistance bands. Bodyweight is always available and is never stored.
  Profiles store only equipment codes, so changing a pick's equipment
  never touches stored data.
- **Custom exercises**: ordinary exercises everywhere the catalogue is
  listed, marked "Custom". Ids are `custom_` plus a Firestore auto id, so
  they never collide with catalogue ids (`ex_...`) and an id alone tells
  which kind it is. They have no level, movement pattern or family: level
  and pattern filters never match them, and they have no alternatives or
  variations and are no one's. They sort first, by name, in popularity
  order. A name may repeat a catalogue name; the label tells them apart.
  Equipment left empty means unspecified and counts as doable with any;
  bodyweight with other equipment is refused when Save is tried. Deleting
  one also removes it from favourites in the same write; programs then
  show it as unavailable, like a retired exercise, and workouts keep their
  copy. Added to a program, one rests 90 s by default, having no rest of
  its own. The 500 limit is checked by the app on create, counting what
  Firestore's cache holds; rules cannot count.
- **Exercise list**: the Exercises tab opens on the interactive model
  under a search box. The box is an entry, not a field: it opens the one
  exercise list page (`/exercises/list`, declared before `:id`), pushed
  above the model so back returns to the model as it was. The list page
  holds search, filters, sort, the count, favourites and the + for a
  custom exercise. Opened from the box, the search starts empty and takes
  focus once the route's transition has completed. A muscle on the model
  opens the same page at `/exercises/list?muscle=<code>`, without the
  keyboard; one gesture opens one page (a muscle opens nothing while a
  page already covers the model).
  - State: search text, the filters and the sort are app-wide and last
    while the app runs (a user change resets them). A muscle chosen on the
    model belongs to that visit, held only by the page's location:
    arriving makes it the only muscle filter and clears the search, the
    other filters and the sort staying; leaving the page (back,
    re-selecting Exercises, a `go` elsewhere) or a link to another muscle
    over it takes that muscle filter away again, unless the user already
    removed or changed the muscle filter, which then stays as they left
    it. So the box always opens without a model-chosen muscle.
  - While the page's muscle is the only muscle filtered, the list switches
    between the exercises it is a main muscle of and those that also work
    it, each with its count and in the list's order, so search, filters
    and sort apply inside them; removing it or adding another muscle gives
    the plain list, and one muscle picked by hand in the filter sheet is a
    plain filtered list.
  - Every exercise list in the app is this one widget; the exercise
    picker (for programs, the generator, the workout and workout history)
    uses it with its own state and no sections. The picker's route
    (`…/pick`) takes `max`, `multiple` and a `form` (`add`, `swap`,
    `replace`); Add opens from the root navigator, over the tab bar, while
    Swap and Replace open at the sibling `…/swap` inside their tab; each
    place declares the most its list holds (40 a workout, 20 a program
    day). Creating a custom exercise from the picker opens the form above
    it (`…/pick/new?name=`), and the picker chooses the new exercise once
    the catalogue holds it (5 s at most).
- **Exercise detail** (2026-11-13): the ⋯ menu offers "Add to workout"
  (the workout in progress, else asking to start one), "Add to program",
  the favourite and, for a custom exercise, Edit and Delete, the same in
  every place the page opens. Anything an exercise lacks is left out, so a
  custom exercise shows the model, its tag, logging type, equipment and
  Note and nothing below. Similar exercises lists variations and
  alternatives; an alternative of the same family is listed once, as a
  variation, and a row opens that exercise in the same tab. A catalogue
  exercise has no user note (removed 2026-11-26):
  `users/{uid}.exerciseNotes` is no longer read or written and stays in
  old documents. An exercise's records and progress are on its strength
  page, opened from Progress.
- **Body model files** (2026-11-20, 2026-11-21): the 36 parts of
  `body_male.glb` and `body_female.glb` are named by muscle code:
  `<code>_left`/`<code>_right`, the single `abdominal`, and the body
  `none`. The 4-view drawings the models were generated from are in
  `design/body_models/{male,female}/{front,right,back,left}.png`.

### Exercise animations

- **Where it stands** (keep this entry current): built end to end and on
  main; animations play in exercise detail and on the open workout card
  for every approved recipe, solved on the phone by `forge_motion`.
  Recipes approved: 300 of 419 live exercises (the last 2 on
  2026-11-27), and all 31 kits; dev and prod hold all of them since
  2026-11-27. `ex_lat_pulldown` stays a draft: its
  mistakes are not drawn. Not started: about 118 exercises (bands,
  machines, suspension and small groups), and those skipped for gear
  without a kit (a wall, a rack, a trap bar, plates) or, like the
  kettlebell snatch and clean, by their session. What is open is under
  Open.
- **Tools** (`tool/animation/`; prerequisites under Operations; each
  script's header says what it does, and
  `recipe.py`'s is the reference of the recipe and kit format):
  `preview.sh <exercise id> [keys|loop|hands] [male|female]` renders the
  correct form and every mistake into `build/animation/`; `validate.py`
  checks the recipes on both bodies; `batch.py` prints the counts by
  status, the kits and the next batch; `page.py` builds a batch's review
  page (after a fix, render the loops again and look at a frame of the
  page's own copy before publishing); `export.py` writes the skinned
  bodies and their `.rig.json` files into `assets/models`.
- **A recipe**: the correct form and the exercise's mistakes, each a set of
  key poses with their times; the gear; a status. A mistake is the correct
  form with the few values that go wrong changed, the catalogue `mistakes`
  line it shows, and the body region to ring. A mistake no pose can show
  (breathing, tempo, load) gets no animation and the recipe says so. A pose
  gives the pelvis, the spine's angles, where each hand grips and each foot
  stands, where elbows and knees point; the solver does the rest, so hands
  stay on the bar and feet on the floor. Muscles come from the catalogue's
  `mainMuscles` and `secondaryMuscles`, never from the recipe.
- **Between keys** (2026-11-26): the motion rests only at the first and
  last key, at a hold (the same pose twice in a row) and where it turns
  back (the same pose before and after a key); it passes through every
  other key at speed, so a mid pose shapes the path without a stop. A hand
  that moves between two keys keeps the arm's stretch between them, so a
  straight arm swings straight instead of along the chord; a hand that
  stays in place is left where the pose puts it. `pose.py` and
  `forge_motion` do the same.
- **Feet** (2026-11-26): a foot takes a `roll` (the sole turning inward)
  next to its toe-out and toes-down angles. A standing foot does not
  slide, but it may turn on the spot from one key to the next (a pivot),
  and it stands somewhere else after a key that lifts it (a step): between
  a standing and a lifted key the foot travels as a lifted foot from where
  its ankle was. So a body can step, walk, jump and switch sides inside
  one loop.
- **Gear** (2026-11-25): designed once. A piece of equipment is a kit in
  `content/animations/_kits.json`, built from boxes, cylinders and balls
  that stand still, follow the two hands, one hand (a dumbbell) or one
  foot (an ankle strap), or stretch between two points (a cable); each kit
  has a status of its own (`draft`, `approved`), and all use the same four
  tones (`gear`, `steel`, `pad`, `plate`). A recipe only names kits, says
  where each stands and sets the few values a kit offers (a plate's size);
  the validator refuses anything else. A new kit, or a change to one, is
  shown to the owner on its own before any exercise that uses it goes to
  review; a change to a kit changes every exercise using it, so those are
  rendered again. Under every exercise lies a light floor disc with the
  body's soft shadow, in the preview and in the app.
- **Status** (in the recipe file): `draft` (being written), `review`
  (rendered, checked, waiting for the owner), `approved`, `fix` with the
  owner's `note`. A mistake carries its own status. Only `approved`
  recipes are imported. `batch.py` prints the counts and the next batch;
  the count in Where it stands is the only state kept here.
- **Order**: by equipment group, the catalogue's first matching code
  deciding: barbell (barbell, ez_bar, trap_bar, smith_machine, landmine,
  plate), dumbbell and kettlebell, cable, machine (machine, sled,
  back_extension_bench), bars (pull_up_bar, dip_station, rings,
  suspension_trainer), bands, then bodyweight and the rest. Inside a group
  whole families together, the family with the most popular exercise
  first, then `familyRank`. A batch is about 5 exercises with their
  mistakes (10-15 animations) and never splits a family.
- **A batch, step by step**: (1) list the batch (`batch.py`), build any
  kit it lacks and get that kit approved; (2) write the recipes, one
  family per Implementer so no two touch a file, rendering the key poses
  and correcting until `validate.py` and the checks below pass; (3) the
  Reviewer looks at every sheet against the checks and the exercise's own
  `setup`, `execution`, `mistakes` and `cues` text; (4) import the
  drafts to dev and to prod, where they land in the draft documents only
  admins see (a standing exception to asking before prod, 2026-11-26), so
  the owner watches them in the released app, with a line per exercise on
  what to look at; (5)
  ask the owner which exercises need a fix, then what to change in each;
  (6) fixes go back through 2-4 and are shown again; (7) when the owner
  approves, statuses become `approved`, the count here is updated, the
  batch's PR is merged, and the batch is imported to dev and to prod at
  once (2026-11-26: an approved batch goes straight to prod, no second
  question). A batch that needs a solver, body file or app change not yet
  in a released build is held from prod until that build is out, and the
  owner is told. No recipe is marked `approved` and no batch is merged
  without the owner's answer. Where a batch is reviewed today (2026-11-26):
  its drafts are imported as draft documents and the owner reviews them in
  the released app with the admin account (Drafts for admins, under In
  Firestore); a `page.py` review page is an optional local aid.
- **Checks before the owner sees an exercise**: a standing pose has locked
  knees (leg stretch 0.995 or more); a grip matches how the bar is really
  held, looked at in the `hands` close-ups of both bodies, not only
  solved: the bar runs through the closed fist at the base of the fingers,
  the fingers wrap it, the thumb closes with them, the wrist is straight
  or stacked over the forearm; no limb is stretched past its reach (the
  preview prints each limb's stretch; above 0.99 means the target was not
  reached); feet that stand are flat on the floor and do not slide; hands
  stay on the bar or handle through the whole loop; the bar or handle
  moves on the path the exercise's text describes; gear does not pass
  through the body or the floor; start and end pose are the same, so the
  loop does not jump; the lowering is slower than the lifting; nothing
  contradicts the exercise's `mistakes` list.
  **From the owner's review in the app** (2026-11-26, 65 notes on the
  first 241 drafts; every recipe passes these too, the ones the owner did
  not look at included): no hand, forearm or elbow goes into the thigh,
  knee, hip, belly or chest (sit-up top, Russian twist, deep squat hold,
  sumo squat, kettlebell deadlift); a bar or a dumbbell goes round the
  body on its way between two keys, by a mid key, never through it (hip
  thrust, snatch, sumo deadlift, cleans); an elbow angle the movement keeps
  is the same at every key, which the preview shows as the same arm stretch
  (raises, flies, shrugs, straight-arm pulls, swings), and arms that hang
  with a weight are straight at every key, the top of a deadlift included;
  no ankle, foot, knee, thigh, shoulder or forearm turns as no joint turns:
  a direction that flips between two keys spins the limb on the way, and a
  foot in the air points as a relaxed foot would, the same at every key
  unless the movement turns it; on a bench the hips and the whole back lie
  on the pad, centred, never on its edge or corner; a bar that rests on the
  back or the shoulders touches them; nothing hangs in the air that would
  fall (a renegade row always has one hand on the floor); nothing is faster
  than a person does it; a mid pose shapes the path and a hold is the same
  pose twice, with about the same speed on both sides of a mid key; a
  movement that reads wrong as a whole is rebuilt from the exercise's own
  `setup` and `execution` text. A session checks these on the rendered key
  poses from two angles, and with a script that samples every clip frame
  by frame where it has one; it says which recipes it only checked by
  numbers. Known and accepted: one pose cannot seat both bodies, so a back
  sinks 1-3 cm into a pad on the male body where it just touches on the
  female one.
- **Hands** (2026-11-26): the grip point is 6.4 cm from the wrist along
  the fingers and 3.6 cm into the palm, where two finger joints curled 75
  degrees each close round a 28 mm bar; the thumb turns about its base by
  1.2 times the curl. A bar grip uses `curl` 75. A hand that holds the bar
  elsewhere says so with `hold` ([along the fingers, into the palm]): the
  front squat's rack rests the bar on the fingers (`hold` [0.10, 0.028],
  `curl` 30). The same numbers live in `forge_motion`; the two change
  together. An EZ bar does not turn with the hands, so its bends lie
  across the palm only at the bottom.
- **What the body models taught**: at rest the palms face forward, not the
  thighs; the arms are short for the height, so a deadlift starts with a
  near-horizontal back; the female hand ends higher than the male one, so
  landmarks are measured, not assumed. The viewer sorts whole triangles by
  depth: gear is cut into cells of at most 9 cm and must not overlap the
  body. The rig and export tools accept an already skinned body file.
- **In Firestore**: `tool/validate_content.dart` checks the recipe files
  against the catalogue and the kits (only approved kits in an approved
  recipe); geometry stays with `validate.py`. `tool/import_content.dart`
  writes `animationKits/main` and every approved recipe's
  `exercises/{id}/animation/main` after the other content, skips unchanged
  ones by `contentHash`, and deletes the document of a recipe that is no
  longer approved (a recipe file removed leaves its document alone).
  - Drafts for admins (2026-11-26): a recipe that is not approved is
    written to `exercises/{id}/animation/draft` and every kit, draft ones
    included, to `animationKits/draft`. The app reads the draft pair in
    place of the approved one only for a user whose ID token has the
    `admin` claim (`tool/set_admin.sh`), so the owner reviews drafts in
    the released app while nobody else sees them; approving a recipe
    deletes its draft. An approved recipe sent back with `fix` keeps its
    published animation until the fix is approved (2026-11-26: a flagged
    animation is still better for everyone else than none).
  - The app reads the animation and the kits from Firestore's cache when
    it holds them (a known absence included) and refreshes them from the
    server for the next read; otherwise from the server. So an animation
    opened once plays offline, and a fixed recipe shows from the second
    opening on. No animation document means none; missing kits or text
    that is not a JSON object is a failure.
- **In the app** (2026-11-25): with an animation, exercise detail's first
  card has two tabs, the animation (first; the tab is not remembered) and
  the front and back muscle pair; with none, while loading, on failure and
  for custom exercises the card shows the muscle pair alone. Under the
  animation one chip per clip: the correct form, then each mistake in
  catalogue order, numbered because the catalogue has no short names for
  mistakes (a mistake whose recipe entry is `shown: false` has none); the
  picked mistake's catalogue text shows under the chips. The body is the
  profile's sex; a clip is solved once, when first picked, and again when
  the body changes. The view turns and zooms and has pause and half speed:
  both are kept while another clip is picked and forgotten when the view
  closes, and switching the speed restarts the loop. In the workout in
  progress only, each exercise of an open card that has an animation gets
  a play button; its sheet plays the correct form over the running workout
  with the cues and links to the exercise's detail page.

### Programs

- **Programs**: a name of 1-60 characters, 1-7 days, day names of at most
  40 characters, 1-20 exercises per day, an optional length of 1-52 weeks;
  lengths count UTF-16 code units in the fields and in validation. The
  Firestore rules validate the top-level fields only (`name`, `days` count,
  `origin`); the app validates days and items. Items whose exercise's
  logging type changed are fitted to the new type when the builder loads
  them, and the user is told.
- **Programs tab** (2026-11-13): the active program comes first with this
  week's days by date, each done, missed, next or planned. Weeks count
  from the start date, as the length does (`ProgramSchedule.week`); a
  program that ran its length shows as finished. The tab starts nothing
  and has no missed-day choices: Today's workout card starts the day and
  answers a missed one, another day than the next starts from the program
  page, and an empty workout starts on Today. The entries to the
  ready-made programs, the generator (locked without premium) and the
  builder are the same with or without programs. The weekly sets card is
  only on the program page.
- **Program page** (2026-11-13; Edit moved into the menu 2026-11-15): the
  menu has Edit, Duplicate and Delete; the page starts the program, or
  changes its days and stops it, or shows the premium lock (Start locked;
  an active locked copy can still be stopped). Each day can be started
  from its card (the premium gate for a locked copy). While the program
  is active the page warns when its schedule and days do not match; not
  once it finished. Which days are open is the page's view state, never
  stored: the next day while the program is active, the first day while
  it is not; again from there once its days change (an edit may move
  them), and the next day opens once it moves on, e.g. on Start. Each
  program id gets its own page (keyed in the router), so a copy opened
  from Duplicate never acts on the original. "Add to program" on an
  exercise without programs opens the builder: inside the Programs or the
  Exercises tab it is pushed above the exercise in that tab, and saving
  or leaving returns there, so the exercise can be added; from a workout
  or the history it opens in the Programs tab. In the builder, + Day
  selects the new day and opens its Rename dialog; opening the builder or
  switching days never takes the focus.
- **Training days** (2026-11-19, 2026-11-20): Start program, Run it again,
  Change days and "Start this program" open one Training days sheet with
  two modes. Custom: each program day gets its weekdays; a weekday holds
  one day, so picking a weekday another day holds moves it to this day;
  Save is off while no weekday is picked. Simple: the user picks exactly
  as many weekdays as the program has days; Save is on only at that
  count, and at it an unpicked weekday does nothing while a picked one
  turns off; the days go onto the picked weekdays in the user's week
  order, the first day on the earliest (`ProgramSchedule.inWeekOrder`).
  The sheet opens Simple when the schedule is exactly that
  (`isInWeekOrder`) or empty, else Custom. Starting suggests one weekday
  per day spread over the week, the days in turn, so starting opens
  Simple (except a 7-day program in a Sunday-first week, whose
  ISO-ordered suggestion opens Custom). Simple to Custom carries the
  picks over in week order (too few picks leave the last days on no
  weekday); if nothing was picked since Simple opened, Custom comes back
  as it was. Custom to Simple keeps the weekdays when each day is on
  exactly one (`hasEachDayOnce`, put in week order on Save), else starts
  with none picked.
- **Schedule**: `activeProgram.nextDate` is a calendar date stored as a
  `YYYY-MM-DD` string, so it is the same date in every time zone, and
  `startedAt` is a device-clock timestamp because starting a program must
  work offline. Every training weekday does the fixed program day
  `activeProgram.schedule` gives it, every week (2026-11-19: a 2-day A/B
  program on Mon A, Tue B, Thu A, Fri B); a day may be on several
  weekdays or on none. The next day (`nextDayIndex` on `nextDate`) comes
  first; after it each training weekday does its own day, so finishing a
  day plans the first training weekday after it with that weekday's day,
  whichever day was done. A day moved to another date (Do it today, Move,
  the calendar's move) keeps its own day there, in place of that date's
  own day, which is left out that time; the weekdays after it do their
  own days again (2026-11-19). Moved earlier in its week with the
  calendar's move, it takes its own date along (2026-11-19): Thursday's A
  moved to Wednesday leaves Thursday a rest day this week, and the
  weekdays after Thursday do their own days (`activeProgram.movedFrom`,
  cleared once the next day is planned anew). Moved later, the training
  weekdays in between are left out. A missed next day stays the next day
  until the user does it today, moves it to the next training weekday or
  skips it (the first training weekday from today then does its own
  day); meanwhile it is planned on the first training weekday from today,
  and the week plan shows it once, on its date, as missed. Starting a
  program plans the first training weekday from today with its day, so a
  program started mid-week begins with the day planned for that weekday,
  not always day 1 (2026-11-24); when that is today and the day was
  already done today (a workout of that program and day started today)
  it counts as done, as finishing it would have, and the next training
  weekday comes next. Changing the training days replans the next day as
  the new schedule gives it, from today (from tomorrow when it was
  planned after today, as today's day may be done). A schedule naming
  days the program no longer has keeps them inside it (index modulo the
  day count) and the program page asks to change the training days. A
  program with a length ends that many weeks after its start date.
- **Catalogue rules** (`lib/features/programs/domain/catalogue_rules.dart`):
  every catalogue program must pass the app's own `validateProgram`, and
  its session lengths are the app's `estimateDay`. On top: every exercise
  fits the program's equipment profile (through `equipment` or an
  alternative set) and is at most one level above the program (no advanced
  exercise in a beginner program); `equipment[]` is computed from the
  exercises' primary equipment; live programs are exactly 6 free and 23
  premium. Weekly sets per major muscle (pec, lat, mid delt, biceps,
  triceps, glute, quads, hamstrings) are warned about outside 6-12 for
  beginner, 10-18 for intermediate and 12-20 for advanced programs:
  narrower than the volume screen's 10-20 reference band, as they say
  what a program of one level should prescribe. Focus programs and
  equipment-limited ones exceed or miss a band on purpose and say so in
  their summary.
- **Catalogue in the app**: clients read the whole `programs` collection,
  every status, and keep the live cards on device by `order` (no composite
  index; offline from Firestore's cache after the first load). A premium
  program's days are read only once the user is known to have premium; days
  the rules refuse to a user with premium show as unlocking and are read
  again three times (after 2, 4 and 8 s), then on Retry, since the
  entitlement may not have reached the server yet; a refused free program
  is a failure. Days read under an earlier premium status are dropped, and
  a page updates by itself once the paywall grants premium. A locked
  premium program still lists its days (names and exercise counts are on
  the card). "Start this program" waits for the exercise library and the
  user's programs, and is blocked with a message when a day uses an
  exercise no longer in the library (copying without it would change the
  program). After the copy offer, the replace confirmation and the
  Training days sheet it copies the program into `users/{uid}/programs`
  (`origin: catalog`, `sourceId`, `premium` for a premium one) through the
  builder's validation, starts the copy and opens it; when a copy from
  the same `sourceId` exists, it is offered first. Duplicate copies it the
  same way and opens the builder on the copy. An exercise opened from a
  ready-made program opens its alternatives and variations inside the
  Programs tab. A program fits the user's equipment ("Only my equipment")
  when they own all its primary `equipment` or all of its equipment
  profile (an unknown code or a missing list is not owned); while their
  equipment is unknown the filter filters nothing.
- **Recommended for you** (`recommendPrograms`, 2026-11-21):
  - The user's equipment type (`EquipmentProfile.typeOf`): the preset
    equal to their owned equipment; otherwise the most similar preset:
    items both have over items either has (bodyweight left out), so a
    preset with much more than the set scores low too; ties to the
    smaller preset, then enum order; nothing shared (or nothing owned) is
    bodyweight.
  - Never recommended: a program whose `equipmentProfile` is not that type
    (less or more equipment alike); a level more than one step from the
    user's (beginner and advanced never meet); days per week more than one
    from the user's. An unknown answer (old profiles) skips its
    elimination and scores 0.
  - Score: goal 3 for the same, 1 for a related one (build muscle ↔ get
    stronger, lose fat ↔ general fitness), else 0; level 2 for the same,
    1 for one level below the user's, 0 for one above; days 2 for the
    same, 1 for one more or fewer.
  - Ranked by score alone (no free/premium split), ties in catalogue
    order, at most 3; fewer, or none, when fewer are left.
  - The match line names only exact matches: goal, level, days; the
    equipment whenever it is known.
  - They derive from the profile and the equipment, so any change to the
    goal, level, days or equipment changes them.
  After onboarding the best recommendation is offered, premium or not;
  with none, or the catalogue offline, onboarding lands on Today, and so
  does signing in from onboarding to an account already onboarded.
- **Ready-made programs page** (2026-11-13, 2026-11-15): a search by name
  and the filters Only my equipment, Level, Days per week, Goal and
  Equipment; while the equipment is unknown, Only my equipment opens the
  filters sheet, which says why. Every time the page opens the Equipment
  filter is set to the user's equipment type alone, replacing the filters
  of the last visit; while the equipment is unknown it is set once known,
  unless the user changed a filter first; never on the onboarding
  suggestion, whose recommendations ignore the filter. It is a normal
  filter: it counts among the filters on (each chosen value counts one)
  and Clear removes it. With no search and no filter but that default
  (or none), the page shows the user's active copy, then Recommended for
  you (up to 3; the active program's source stays out and the next best
  takes its place; no section when there are none), then the other
  programs in catalogue order, none of the recommended repeated. A search
  or any other filter hides the active copy, the section and the count,
  and lists every match. A row is marked as fitting the user by
  `TrainingProfile.suits` (goal, level and days per week), or as Premium
  while locked.
- **Copies of premium programs** (2026-11-11): a copy of a premium
  ready-made program is marked `premium: true` and keeps the mark through
  edits and duplicates. Without premium it stays visible and readable but
  cannot be started, rescheduled or trained; an active one shows as
  locked in the Programs tab and is not stopped, so it resumes when
  premium returns. While the premium status is unknown these actions
  wait. `programAccess` is the one check, also for starting a workout
  from such a program (Today's card, the calendar, a day on the program
  page): locked opens the paywall and starts only if premium was bought;
  `ActiveWorkoutCubit` refuses it too. A workout in progress from it can
  always be finished; free workouts are never gated. The gate is
  client-side only: the copy lives in the user's own collection, and the
  rules only check that `premium` is a boolean.
- **Program generator** (2026-11-22):
  - Decisions: every rule is editable in the admin panel, with a
    simulator; the entry stays on the Programs tab, Premium only, and
    onboarding keeps suggesting a ready-made program; a generated program
    is one repeating week, saved as `origin: generated`, never `premium`;
    progression stays the workout's hint.
  - Questions: goal, level, days per week (2-6) and equipment from the
    profile, then session length, focus areas (up to `focus.max`, may be
    none), areas to leave out (up to `skip.max`, may be none: areas the
    user does not want to train), sensitive areas (any number, may be
    none), equipment style, split ("Let the app choose" first). There is
    no leave-out question for exercises: one is swapped or removed on the
    preview. The equipment style question shows only when the user's
    equipment has both a machine kind (machine, cable, Smith machine) and
    a free-weight kind (barbell, EZ bar, trap bar, dumbbell, kettlebell),
    else it is `any`; the split question shows only when more than one
    split fits the days, level and goal.
  - The app (`lib/features/generator`): the entry shows for everyone,
    locked without premium. The questions load `generator/options` first;
    offline, nothing published yet and a failure each say so, with Retry.
    The four profile answers are prefilled from the profile and the owned
    equipment, and a changed answer counts for this program only, never
    the profile. Session length starts at 60 minutes when offered, else
    the middle option. A page that stops applying while on screen (the
    options change) gives way to the nearest one before it.
  - Area pickers: the body model paints and picks with the options' area
    maps, `focusAreas` on the focus page and `skipAreas` on the leave-out
    page; a tap on a muscle picks the first area (in vocabulary order) of
    that page's map holding it, a muscle in none does nothing. Without
    the maps (an older options document) only the list is offered. A
    focus area cannot be left out; picking a left-out area as focus takes
    it out. The most areas are `maxFocusAreas` and `maxSkipAreas`.
  - Preview: calls `generateProgram` with the answers, seed 0 and the
    app's language. The first program's failures fill the page: offline,
    not premium (asked again by itself after 2, 4 and 8 s, as the
    entitlement may not have reached the server, then a message with
    Retry), no template or no exercises (back to the questions), no rules,
    anything else a failure with Retry. Regenerate sends the next seed and
    the kept items per day; one that fails (after the same premium
    retries) leaves the program on screen and says so. Kept items are
    sent only as the server takes them, and their target weights, which
    the server does not take, are put back on the same exercise of the
    same day. An edited item enters the program only once valid. The
    weekly sets are counted by the app; the uncovered notice shows the
    server's `uncovered`, and after any edit the `targeted` muscles no
    exercise of the week works as a main muscle. Save stores the program
    with the server's day names and `lengthWeeks` and opens it; every
    program the server returns logs `program_generate` (goal, days).
  - Engine (`functions/src/generator/engine.ts`; pure: the same answers,
    rules, exercises, seed and kept items give the same program):
    1. Template: the fitting one (days, level, goal) of the chosen split,
       or of any split, with the highest priority; none fitting is the
       typed refusal `no-template`.
    2. Candidates: live exercises doable with the equipment, at most one
       level above the user, tier not `never`, no stress area the user
       marked, no main muscle of an area the user leaves out (those
       muscles have no target either). A day none of whose priority 1
       slots has a candidate (a leg day without legs) gives its place to
       the template's other days, taken in turn and numbered ("Upper A
       2"); when no day is left the answers are refused (`no-exercises`).
    3. Picking: a slot takes the best-scoring candidate fitting it that
       is not on the day yet; the score weighs tier, equipment, level,
       what the week's other days already use, popularity and the seed.
       A second exercise of a family on one day only when nothing else
       fits; a `fallback` exercise only fills a priority 1 slot; slots
       sharing a `key` take the same exercise; a slot nothing fits is
       left out.
    4. Dose: each slot starts at its role's fewest sets; reps, rest and
       hold time come from `dosing` by goal, role and logging type.
    5. Time: a day costs the app's estimate (`estimateDay`, rebuilt in
       TypeScript and held to the Dart one by the vectors in
       `test/fixtures/estimate_vectors.json`) plus a set-up time per
       exercise, grouping applied.
    6. Filling: priority 1 slots (a session too short for them loses the
       last ones that are not focus work, down to three exercises);
       priority 2 slots while the session and the caps have room; sets
       one at a time to the slot whose main muscle is furthest below its
       weekly target (1 per main, 0.5 per secondary muscle, as the app
       counts); extra accessory slots for focus muscles still short;
       priority 3 slots; then sets again, to the targets and the caps.
    7. Focus: a focus muscle's target and cap rise, a slot picking it
       counts one priority higher, its sets are added before the
       priority 2 slots, and inside a role it comes first.
    8. Order: primary, secondary, accessory, core; inside a role the
       template's order. The first fitting `grouping` rule joins
       neighbouring slots into supersets or circuits (rest only after
       the round), never two with the same first main muscle.
    9. Kept items (Regenerate) take the first slot of their day they
       fit, or stand as extra; their exercise, sets and reps stay, even
       when the day then runs past the session.
    A day never has more than 20 items, the app's limit. Two late passes
    keep an unusual week sound: when repeated days stack a muscle past
    its cap, the latest days give up such priority 1 slots while they
    keep three exercises; and a targeted muscle nothing trains directly
    gets one accessory exercise on the shortest day with room. The
    result names the muscles with a target and no direct work
    (`uncovered`); with `explain`, each item's slot, score parts and the
    next best candidates.
  - Exercise data: `generatorTier` (staple, standard, fallback, never) on
    exercises and `stressAreas` where there are any, edited in the admin
    panel; the content rules accept both as optional, and an exercise not
    rated counts as standard.
  - Rules: one versioned document (`generator/rules`, Data model), edited
    and published from the admin panel. The validator lives only in the
    function (`functions/src/generator/rules.ts`): the content tools
    (`tool/import_content.dart`, `tool/validate_content.dart`) check the
    seed `content/generator/rules.json` through the built
    `functions/lib/generator/cli.js` (Node; a problem refuses the
    import). The import writes the seed as version 1 (the rules, their
    version copy and `generator/options`, each only if absent) when the
    project has no rules; once it has, the panel owns them.
  - The exercise and muscle codes the engine needs are in
    `functions/src/generator/vocabulary.ts`; a Dart test holds them equal
    to `vocabulary.dart`.
  - Seed rules, known gaps (rules version 1, 2026-11-22): they leave 69 of the
    140 standard answers with a target muscle without direct work and 83 with
    a day under half the session; the intermediate Upper/Lower gives glutes 21
    sets, above the 20 band. The exercise ratings and seed rules are the
    Architect's first pass.
- **Program progress**: doing another day of the active program shows it as
  done but leaves the schedule. Done days are read from workouts by date
  only, so no composite index is needed.
- **Add to program**: an exercise's page appends it, with the default
  targets, to a day of one of the user's programs through the program's
  validation; a full day cannot be picked, and without programs it offers to
  create one.
- **Save as program**: offered on a free workout's summary only (a program
  day's summary offers saving its changes to the day instead, see Workout
  › Workout summary). The workout becomes a one-day program of the user's
  own: its working sets, the rep range done or the longest duration, the
  heaviest weight (least assistance) as target, the exercise's default
  rest (90 s for a custom one). Exercises no longer in the library are
  left out; a program that would not be valid (over 20 exercises) is
  refused.

### Workout

- **Starting a workout**: Today starts the next program day, the calendar
  a planned day, a program's page any of its days; an empty workout
  starts only on Today; an exercise's page adds it to the workout in
  progress or, after asking, starts one with it. With no program day to
  do, Today points a user who has programs of their own at them (the
  Programs tab); without any it offers the ready-made ones. A program day
  waits until the user's custom exercises are loaded; exercises really
  gone are left out and the user is told how many. Starting while a
  workout is in progress asks to resume it or discard it.
- **Workout left open**: it ends itself. The device keeps when its last
  set was ticked (`LocalWorkouts.lastSetAt`, never in Firestore); 4 hours
  (`workoutIdleLimit`) after it, or after the start with no set done, the
  workout is stored ending at that last set, or, with no set done, thrown
  away. A local notification saying which (id 4, the `workout` channel,
  shown only where notifications are allowed; nothing asks for it) is
  scheduled for that moment and moved with every set. The workout ends
  while the app runs (a timer), when the app comes to the front, or when
  it next starts; a finish by hand or a discard cancels the notice. The
  summary of one that ended itself opens by itself above the open pages
  and has Edit, which closes it and opens the workout in the editor
  (`/today/workouts/:id/edit`).
- **Empty workout**: a workout with no exercise (`Workout.isEmpty`; with
  none there is no set, ticked or not, and a note alone does not count) is
  open but not in progress (`ActiveWorkoutState.inProgress`): no bar in the
  shell, not kept in the local file (an empty one kept by an older version
  is dropped on load), no rest, never stored, and starting another simply
  replaces it. Leaving its page (back or minimize), Discard and Finish end
  it, all without asking. A free workout starts empty and is in progress
  from its first exercise; a program day (or an exercise's page) starts
  with exercises, so it is in progress at once; removing the last
  exercise makes any workout empty again.
- **Workouts on the device**: per user one JSON file
  (`workouts_<uid>.json` in the app's private support directory, version
  2) holds the workout in progress (with its rest and the user's pick,
  both optional fields), finished workouts the server has not confirmed
  yet, and the exercises whose stats need rebuilding. It is rewritten
  after every change (only the latest of a burst, replaced atomically, so
  moving a workout from in progress to finished is one write) and read on
  launch, the workout in progress behind the minimized bar. A user never
  gets another's. A file that cannot be read, or of an unknown version,
  is renamed `.unreadable-<time>`, never overwritten, and the user is
  told. The workout id is made at the start, so storing a workout twice
  stores it once.
- **Logging a set**: empty fields show a suggestion, which ticking takes;
  each value comes from the first that has it: this workout's previous done
  set of the same type and exercise, the same working set last time, the
  program target (weight, bottom of the rep range, duration). A warm-up only
  follows the warm-up before it. A done set edited into an invalid one is
  unticked. A weighted or assisted bodyweight set without a weight has none
  added. Effort is a whole number, see Effort scale. Sets take a note of
  up to 200 characters. Durations are typed in seconds.
  Implausible weight: logging a weight more than double the reference
  asks first (log it, or fix the weight, which leaves the set unlogged).
  The reference is the closest done set of the same type and exercise
  before it in this workout that has a weight, as hints follow (so a
  working set is never held against a warm-up), else the same working set
  last time; with neither, or a reference of 0, nothing is checked
  (`implausibleWeightReference`). Unticking never asks.
- **Workout screen**: shared by the workout in progress and editing a
  stored or past workout; its look is in the studio. One card per
  exercise, or per superset/circuit; only the card of the selected set is
  open, and tapping another opens it on its first undone set, else its
  last. Sets are named everywhere by `setLabel` and `setToDo` (W, 1, 2D;
  "of N" counts working sets), as on the lock screen and in the rest
  notification. The exercise detail page opens above the workout
  (`/workout/exercises/:id`, and `/progress/calendar/exercises/:id` above
  the edit page), so back returns to the workout as it was.
  - Reordering: holding an exercise's header collapses every card to one
    line, then the card (a superset or circuit as one, never split or
    dropped inside another) follows the finger; once dropped the cards
    open again with the same set selected. Not while edits are refused
    (saving, finishing). Screen readers get Move up / Move down actions.
  - Selection: until something is picked it is the next set to do
    (`nextSet`, which knows supersets), else the first exercise; ticking
    moves it to the next set to do, and edits keep it on its set or
    exercise (`set_selection.dart`). The pick is kept with the workout in
    progress in the local file (one that no longer points into the
    workout is dropped), so each time the workout page opens (the
    minimized bar, Today, a lock-screen or notification tap, a relaunch)
    it goes on where the user left it (2026-11-19).
  - Sets: tapping a set's bubble selects it; long-pressing it offers the
    types it can be (Warm-up, Working, Drop set) and Remove set
    (2026-11-15; also as screen-reader actions), the same as the set
    panel's "more" sheet. Adding a set asks its type (a drop set only for
    rep-based exercises); a warm-up goes after the existing warm-ups,
    other sets at the end. Changing a set's type keeps warm-ups first: a
    set made a warm-up moves to after the other warm-ups, a warm-up made
    a working set becomes the first working set, normal and drop sets
    stay in place (`retypedSetPosition`); the selection follows the moved
    set, and a running rest forgets the set it followed, as for any move.
  - Set panel: at the bottom of the page, at most 60 % of it
    (`SetBarLayout.maxBottomShare`); what does not fit scrolls inside it.
    It holds the selected set's values, a drop set's drops, the tick and
    the "more" sheet (set type, note, removal), which follows the
    selection; an invalid tick's message shows in it. While typing, the
    keyboard carries Next / Done: Next goes to the following value
    (weight, reps, then a drop's values in order; off on the last), Done
    closes the keyboard, and a tap on another value moves the typing
    there keeping what was typed. A running rest shows inside the panel
    (see Effort scale).
- **Effort scale**: optional per working set; picking the chosen step
  again clears it. Settings offer Off, By feel (the default), RIR and RPE:
  `settings.effortScale` holds `feel`, `rir` or `rpe` (the older `off`
  reads as by feel); Off is `settings.askEffort` false, which only stops
  the question: efforts are still shown and picked in the kept scale, and
  picking a scale turns the question on again. Every scale is stored the
  same way, as RIR 0-5 (`rpe = 10 - rir`): by feel Easy stores 4,
  Moderate 2, Hard 1, Max 0, and a stored RIR shows as Easy from 4,
  Moderate at 2-3, Hard at 1, Max at 0. RIR offers 5+ down to 0; RPE
  offers "6 or less" (stores RIR 4, and a stored RIR of 5 shows as it),
  then 7 to 10 (2026-11-13). Every scale ends with Failed (the last rep
  was attempted and not completed), stored as `toFailure` with RIR 0;
  there is no separate failure switch, and any set with `toFailure` shows
  Failed whatever its RIR. Effort shows in the chosen scale everywhere
  and is only stored and shown; nothing else uses it yet, and the help
  says just that.
  The question: right after a working set without an effort is ticked in
  the workout in progress, the set panel asks its effort in place of the
  set's values, with no Skip (2026-11-18); warm-ups are never rated, and
  editing a past workout never asks. If the tick started a rest, the rest
  runs as a line above the question (time, +15 s, Skip rest). The
  question has no timeout, with or without a rest. It goes when a step is
  picked (stored on that set), a set is picked or an exercise opened,
  another set is ticked (its own question replaces it), any set is
  unticked, an edit moves sets, or the workout finishes; it does not show
  while edits are refused (finishing). After it, while the rest that tick
  started still runs and a set is left to do, the panel is the rest
  countdown (+15 s, Skip rest, the next set), and the next set's values
  return when the rest ends, or at once when a set is picked or added.
  Opening the workout page anew drops a question whose tick started no
  rest and an invalid tick's message; a question whose tick started a
  rest stays. A selected done working set shows its effort under its
  values (an undone set never does); the panel then takes its own height
  instead of its 60 %, scrolling only when taller than the page.
- **Automatic warm-up sets**: Settings → Automatic warm-up sets
  (`/profile/warmups`):
  - Scheme: Off, Light (60 % × 6), Standard (50 % × 8 · 75 % × 4, the
    default, also for users who never chose), Full (40 % × 8 · 60 % × 5 ·
    80 % × 2) or Custom: 1 to 5 sets, each a percentage (10-95) and reps
    (1-20), kept in the order entered. A set added to Custom starts
    midway from the last to 90 % (on 5 %) with half its reps. Custom
    starts, the first time, from the scheme chosen then (Standard's sets
    from Off) and keeps its sets while another scheme is chosen.
  - Which exercises: every exercise, or the first exercise for each
    muscle group: an exercise gets warm-ups only when no exercise before
    it in the workout that is itself done with a weight and reps
    (`weight_reps`) has the same main muscle (the first of its
    `mainMuscles`; one without any is a group of its own). Push-ups
    before bench press or a plank before loaded core work do not count; a
    loaded one counts even if its warm-ups were deleted. Decided as the
    exercise enters the workout (a program day in day order, superset
    members one after the other; one added or swapped in against the
    exercises before it); reordering later adds or removes nothing.
  - Stored as `settings.warmups` (`scheme` `off`/`light`/`standard`/
    `full`/`custom`, `custom` [{`percent`, `reps`}], `scope` `every`/
    `firstPerMuscle`). The older `settings.autoWarmups` is still written
    (false only for Off) for app versions before the schemes; when the
    two disagree an older version wrote last and wins (false reads as
    Off, true with Off as Standard); without `warmups`, false is Off and
    true or missing Standard. Malformed custom sets are dropped or
    clamped; Custom without sets reads as Standard.
  - When: only `weight_reps` exercises get them (not weighted or
    assisted bodyweight, reps-only or timed ones): one empty warm-up per
    set of the scheme before the working sets, when the exercise enters a
    workout in progress: a program day started, an exercise added (also
    to an empty workout, and starting with an exercise), or swapped in
    while none of its sets is done. A swapped-in exercise loses its
    untouched warm-ups (nothing entered, not done) where it may have
    none. The scheme and the unit are the user's settings: a program day
    waits for them (up to the catalogue wait); while they have not
    arrived, or cannot be read, nothing gets warm-ups and warm-ups
    suggest no ramp. Never on a past workout, never to exercises already
    in the workout when the setting changes, and none when the exercise
    already has a warm-up or they would pass the set limit.
  - Values: suggestions, like any set's. Warm-up n follows the scheme's
    set n (past the last, the last; with Off, hand-added warm-ups follow
    Standard's): its percentage of W for its reps, W being the first
    working set's weight as typed, else as suggested; rounded to the
    fixed 2.5 kg or 5 lb step, never below one step nor above W. They
    follow W until typed over or ticked; while W is unknown (or 0) they
    fall back to the usual warm-up rule. In the workout in progress this
    applies to every warm-up of a `weight_reps` exercise, added
    automatically or not; editing a past workout keeps the plain rule.
  Warm-ups keep their meaning everywhere: no stats, volume, records or
  "of N", no rest.
- **Progression hint** (2026-11-15): shown when every working set last
  time reached the top of the program's rep range (exercises lifting a
  load for reps with a range): the heaviest of them one step up, the
  step being the exercise's `incrementKg` (in lb rounded to 2.5 lb, at
  least 2.5), else 2.5 kg / 5 lb. A tap fills every working set not done
  yet, then the hint goes. A card's "last time" is the best working set:
  the heaviest, then the most reps.
- **1RM**: Epley, `weight * (1 + reps / 30)`; sets above 12 reps are ignored.
- **Swapping an exercise**: the same logging type keeps the sets, another
  gets as many empty ones; up to eight alternatives are offered before the
  whole library. With some sets done (2026-11-15), only the sets not done
  move to the new exercise, placed after the old one, which keeps its
  done sets; in a superset or circuit the new exercise takes the old
  one's place and the finished one leaves the group, just before it. The
  picker says which sets stay logged, warm-ups apart. Swap leaves the
  exercise menu once every set of the exercise is done.
- **Workout limits**: name 1-100 characters, note 1000, exercise note 500,
  set note 200, 40 exercises, 30 sets each, 5 drops per set. The rules
  validate the top-level fields of `workouts` and `exerciseStats` (allowed
  keys, types, sizes); the app checks sets before storing.
- **Rest timer**: ticking a set starts a rest of the rest chosen for the
  exercise in this workout (exercise menu › Rest time;
  `WorkoutExercise.restS`, kept on a group's last exercise and, like the
  goal, only in the local file, never with the finished workout), else
  its program item's `restS`, else the exercise's `defaultRestS`, else
  the user's default (`settings.restTimer`: `enabled`, default on;
  `defaultS`, 90 s, 15-600; `notify`; `alert`). A rest of 0 is none. In a
  superset or circuit rounds count working sets (warm-ups belong to no
  round, so a warm-up on one exercise shifts nothing), and only the
  group's last exercise with a working set in that round starts the rest,
  for the rest of the group's last exercise (as the program estimate
  counts it); the next set follows the same rounds, the group's warm-ups
  first. The workout's last set to do starts none and ends a running
  one, as nothing is left to rest for (rests between exercises stay).
  Warm-ups start none and leave a running one alone; a drop set rests
  like any set. A new tick replaces the running rest; the set that
  started it no longer done (unticked, or edited invalid) ends it; an
  edit that moves sets (remove or move an exercise, remove a set) keeps
  it running unlinked. Finishing, discarding and a user change end it.
  The rest is its end time on the device clock, kept with the workout in
  progress in the local file, so it survives minimizing, backgrounding
  and restarts. A rest ending more than 30 min ahead (600 s plus "+15 s"
  room; "+15 s" never goes past it) is not believed: dropped on load, and
  not run when the clock was set back. A damaged rest in the file is
  dropped, a set position not in the workout forgotten; the workout is
  never set aside for it. One that ended while the app was away ends
  quietly; one that reaches zero in front of the user is announced as
  `settings.restTimer.alert` says and shown as over for 3 s. +15 s moves
  the end. −15 s (the Live Activity's button only) moves it earlier and
  ends the rest when 15 s or less is left; a rest moved either way keeps
  its start, so its progress does not jump.
- **Rest notification**: local, id 1, on the Android channel of the
  chosen rest sound (`rest_chime_vibrate`, `rest_chime`, `rest_vibrate`,
  `rest_silent`; high importance). Scheduled only when the app hides and
  cancelled when it shows or the rest ends, since the notifications
  package cannot hide one over the app in front. A rest moved while the
  app is hidden (a Live Activity button) reschedules it in place, never
  cancelling it first, so a suspension in between cannot leave none. A
  rest left running when the app is killed in front gets none. The wish
  is the user's (`settings.restTimer.notify`, written only by their
  answer or the settings switch); the permission is the device's and is
  never written to Firestore. On a device not asked yet, any workout
  start asks in the app first, before the workout opens, only while the
  rest timer is on; closing the dialog is a Not now, and the system is
  asked only after Allow. With no answer yet on a device that already
  allows notifications (e.g. allowed in onboarding) nothing is asked:
  Start takes it as an Allow. Not now is remembered on that device only
  (a marker file in app support), so other devices still ask; a device
  refusal leaves the wish, so devices that allow it still notify. Allow
  then asks, on Android, for exact alarms (without them the notification
  may be late).
- **Workout on the lock screen**: the workout in progress is on the lock
  screen, drawn by the system so its times run without the app; its look
  is in the studio. It follows `ActiveWorkoutState.inProgress`: shown
  from the first exercise until the workout is finished or discarded, or
  the user changes or signs out; kept while finishing. Nothing is shown
  or removed until the workout is loaded at start; then one left from an
  earlier run is updated or removed. While `settings.restTimer` is
  enabled a running rest is shown instead, with the next set, and turns
  back into the workout when it is over, skipped or unticked. The workout
  shows the set to do now: the next one (`nextSet`) after the set ticked
  last in this run of the app, whatever became of its rest, forgotten
  when that set is unticked or no longer done after an edit; after a
  restart, after the kept rest's set. It is silent whatever `notify`
  says: the rest notification alone announces the end. A show or removal
  that fails (also iOS with Live Activities off) is logged once and the
  same content is not tried again until the app shows again; changed
  content is tried at once.
  - Android: ongoing, silent notifications on their own channel `rest`
    (named from when it showed rests only; default importance, as lower
    ones may be hidden on the lock screen), one at a time: the workout,
    id 3, counting up, or the rest, id 2, counting down with a timeout at
    its end, so the system removes it even with the app killed. When a
    rest starts the workout is scheduled back for the rest's end (exact
    when the device allows exact alarms, else possibly late, never a
    stale countdown); it has its own id because a notification replaced
    as the countdown times out could be removed with it. A rest cut short
    drops the scheduled one and shows the workout at once. Both ask for
    promotion to a Live Update (Android 16,
    `POST_PROMOTED_NOTIFICATIONS`). A tap opens the app with payload
    `active-workout`, handled like the iOS tap. They need the
    notification permission and never ask for it. No foreground service
    (nothing has to run, and it would need a declared type and Play
    review), so from Android 14 the user can swipe them away while
    unlocked, until the next change. No buttons.
  - iOS (16.2+, below that nothing shows; 2026-11-19): one Live Activity
    for the whole workout from the `RestTimer` widget extension (target
    and bundle id kept from when it showed rests only), started by the
    app in front through `forge_live_activity`; its texts come from the
    app. Once every set is done but the workout is not finished it says
    so and points to the app; logging a set and Finish stay in the app.
    During a rest the lock screen has −15 s, +15 s and Skip (iOS 17+).
    They are `LiveActivityIntent`s, running in the app's process without
    opening it: the Runner moves the rest shown at once (15 s more up to
    30 min ahead, 15 s less ending it when 15 s or less is left, Skip
    ending it) and hands the press to Dart, which answers only once the
    press is applied to the workout's rest and the rest notification
    moved (at most 5 s), so iOS keeps the app awake until then. A press
    before Dart listens is kept in the Runner's user defaults until it
    does. No push updates (`pushType: nil`), so the app cannot change the
    activity while suspended: the activity's stale date is the rest's
    end, and the widget draws the rest only while it is not stale and
    its end is ahead, so at the end the system redraws it as the workout
    by itself. iOS ends an activity after 8 h (kept on the lock screen up
    to 4 h more); the app's next update in front then starts a new one,
    as after the user swiped it away. A tap elsewhere than a button opens
    the app with `getworkout://workout` (the `getworkout` scheme in
    `CFBundleURLTypes`); the Runner keeps that URL until Dart takes it,
    so a tap that launched the app is not lost; Flutter's own deep
    linking is off (`FlutterDeepLinkingEnabled` false). The tap joins the
    notification taps' path: kept until the app is past its start and
    the workout is loaded, then the workout page is pushed through the
    router as from the minimized bar (so the unsaved-changes guard sees
    it), unless it is open already or no workout is in progress. No App
    Group and no `live_activities` plugin (it needs iOS 16.1 for the
    whole app): the app keeps iOS 15, ActivityKit weak-linked.
  - iOS traps: content the extension cannot decode draws as an empty
    workout without an error, so a key renamed in
    `ios_workout_lock_screen.dart` must be renamed in
    `WorkoutActivityContent` too. Signing problems of the `RestTimer`
    extension show only in the device log (`sudo log collect
    --device-udid …`); a stale free-team profile once made iOS end each
    activity at once, fixed by an `xcodebuild -allowProvisioningUpdates`
    build after deleting it. A Live Activity started by a build before
    the bridge moved into `forge_live_activity` is no longer seen by the
    app and stays until iOS ends it.
- **Finishing**: the workout, its exercises' stats and, when it did the
  active program's next day, the program moved on
  (`users/{uid}.activeProgram`) are one batch, so the server takes all or
  none; it works offline. Whether the program moves on is decided from
  the programs the device knows at that moment; if they are not loaded
  the program is left and the summary says so. The finished workout stays
  on the device until the server confirms it (its batch is acknowledged;
  see Unconfirmed workouts); one the server refused comes back as the
  workout in progress, once none is open, and the user is told, so a
  workout is never lost. Its program advance went back with the batch.
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
  celebrates none, in its summary or as tags on its page.
- **Workout summary**: duration, volume (weight × reps of the working
  sets of `weight_reps` and `weighted_bodyweight`; assistance is no
  load), working sets and records, then the muscles worked and each
  exercise's done sets; its look is in the studio. The comparison reads
  the program's finished workouts by `programId` (no composite index),
  from the server within 2 s, else the cache, before the batch is
  written. A free workout's summary offers Save as program (see
  Programs). A program day's summary offers saving its changes to the day
  instead (2026-11-15), and only when the workout changed the day: an
  exercise added, removed or swapped, the order, a working set count or a
  rest; reps and weights do not count. The changes are judged on the
  workout as it was before finishing (every set) against the day's items
  (`changedProgramDay`). It asks first, then the day's next workouts use
  these exercises and sets; kept items keep their targets, new ones take
  them from their sets. The offer goes once saved.
- **Stats update**: stats are computed from what the device knows at
  finishing, the server's when it answers for all of them within 2 s, else
  the cache's (transactions do not work offline). Stats from the cache,
  and those that cannot be read at all (offline, never loaded here; left
  alone rather than overwritten), are listed on the device and, once the
  finished workouts are confirmed, rebuilt from that exercise's workouts
  read from the server (`rebuildStats`, at most 500 workouts; beyond that
  they are left). This also repairs two devices finishing at once.
  History keeps the latest 1000 points, each with its `workoutId`. A
  rebuild first waits for the device's pending writes, so it never reads
  past an edit the server has not seen; offline it waits until the device
  is online. A rebuild that an edit or a finish of the same user crossed
  is done again, so the last stats write always comes from a read after
  every change.

### History and editing

- **History**: the calendar's list (see Calendar) holds the finished
  workouts of the month shown, read with the month (no paging). Rows carry
  no records mark. The workout page (its look is in the studio) names
  exercises from the catalogue (custom ones included), else by the name
  stored with the workout (retired and deleted ones); a program that no
  longer exists shows as deleted. It shows the week of the active copy's
  run (`ProgramSchedule.runWeek`, none for a workout before the run
  started), efforts on the chosen scale, and a record tag only on a set
  holding a record the exercise still keeps (`GetHeldRecords`: one read
  of each exercise's stats; a record beaten later loses its tag).
- **Editing workouts**: editing, deleting and adding a past workout store
  the workout in one batch, never changing `activeProgram`; a past workout
  has no program (a program day only fills its exercises), the edit page
  deletes too (it then closes with the workout's page), and moving a
  program workout's start only moves the day shown as done. Edits keep
  ticked sets only and pass the finishing checks (`isStorable`); the use
  case also refuses a start or end in the future and a duration over
  24 h. The batch carries the stats of every exercise touched, before and
  after, rebuilt with `rebuildStats`, only when the server returned all
  their workouts within 2 s after the pending writes; stats are never
  rebuilt from the cache, which may lack workouts. Every exercise touched
  then joins the device's stale-stats list and is rebuilt from the
  server, as after finishing. An exercise with more than 500 workouts
  keeps its stats, on both paths and in the rebuild, so after an edit
  they may stay stale.
- **Past workout** (2026-11-15): the calendar's + first asks the date (up
  to today), start time, duration and, with an active program, a program
  day whose exercises fill the page. A past workout has no name field: it
  is named after its program day, else "Workout". Saving with unticked
  sets asks first and leaves them out.
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
  only then does absence on the server count as refused. A refused edit
  or delete is undone by Firestore together with its stats (one batch)
  and reported on the calendar.

### Today and progress

- **Today tab** (2026-11-18): what to do now, in three parts: the workout
  card, a "Start empty workout" row (every day; it asks first while a workout
  is in progress) and the calculators card. The week strip, this week's sets
  and steps are Progress's. The app never calls the empty workout "free":
  users read that as "at no cost". The workout card shows:
  - A workout in progress (not an empty one): the card is that workout with
    Resume, which opens it like the workout bar and never starts another. A
    workout stores no day name, so its program day shows only while that day
    would still give it its name (not since renamed, moved or deleted). While
    the workout in progress is still looked for, the card shows only its
    title, never Start.
  - An active program: the program (opening its page) with its next day,
    planned date and Start. It shares the Programs tab's program list cubit
    (one instance), so both tabs show the same plan. A next day planned after
    today with none missed makes today a rest day: the rest-day card with
    "Start <day> early", or, when a workout was finished today, a done-today
    block over the next day's row; until today's workouts are known the card
    shows only its title.
  - A missed day shows the three choices (Do it today, Move, Skip) instead of
    Start, only while the program is open, as in the Programs tab; Start comes
    back once it is answered (2026-11-15). A failed choice is reported by the
    prompt that made it, so the two tabs never both do; a write the server
    refuses later is reported once by the shell, whichever tab is open.
  - A locked premium copy shows its day locked, Start opening the paywall; its
    missed day stays the locked block. While the premium status of a premium
    copy is unknown the card shows only its title, as the Programs tab waits,
    so a missed day never shows as a planned one with Start.
  - Without a program, or once it finished: one way on, to the user's saved
    programs (none finished) or else to the ready-made programs.

  No quick actions besides the calculators card (the calculator pages, the
  Plates calculator's bar and plates page too, are routes of the Today tab,
  `/today/calculators/...`) and the rest-day card's suggestions: cardio is
  logged under Progress → Cardio, a past workout is added on the calendar. The
  rest-day card's walk reads today's steps against `settings.stepGoal` (again
  when the goal changes and on resume) and only checks access, never asks the
  system. Loading never shows a spinner on this tab (2026-11-15). The tab
  moves to the new day when the app resumes.
- **Progress tab** (2026-11-13, 2026-11-15): one card per area, each opening
  its page from anywhere on the card; each reads through its own cubit and
  shows its own failure, so one area failing leaves the others. Body: the
  latest weight with its change since the previous weigh-in, the newest body
  fat and the last 2 weeks' weights. Calendar: this week's strip (the app's
  only one); no month count. Weekly volume (the app's only this-week sets):
  this week's sets against the active program's planned weekly sets (every day
  of a week once), the four most trained muscles, then how many trained
  muscles are in, below and above the band; without a running program the
  count alone. Strength: the most recently trained exercise that has an
  estimated 1RM, its latest workout's best e1RM and the change since the first
  e1RM of the last 2 weeks (none with a single estimate there); it opens the
  strength list. Cardio: this week's distance, sessions and minutes. Steps
  (the app's only steps card): today against the goal; a link to the Steps
  page while not set up; no card without a health store. The Body and Strength
  cards cover the last 2 weeks (`progressCardRange`) for everyone
  (2026-11-19); longer history is on the chart pages.
- **Measurement-day prompt** (2026-11-15): shows under Progress's Body card
  while the measurement reminder is on, from two days before its next date
  through that day (`measurementPromptDays`), until a measurement day is saved
  in that time. Swiping it away hides it until the next date; that is kept on
  the device.
- **Calendar**: Progress → Calendar is one scrolling page, the month card and
  the month's list (the studio). It follows the month's dates plus six days on
  each side live: workouts and cardio by local start date, a range on one
  field, so no composite index. One month ahead shows the program's planned
  days. The list holds workouts, cardio, program days planned (with Start) and
  missed (Do it today); a date is marked for each of those four. Planned days
  follow the week plan's logic over any range. A program day done (a workout
  of the active program and that day, on that local date) shows only as its
  workout, and a day done twice on one date shows once, in the Programs tab
  too. A next day done on its date without the program moving on (it was not
  loaded at finishing) is done, not planned or missed, here and in the
  Programs tab, whose missed-day prompt knows only this week's done days. The
  missed next day shows on its date as missed, and again where it is planned
  now. Only the next day moves: to a day from today to the last day of its
  week; the days after it follow. A planned day starts like any program day,
  so a locked premium copy's days show but open the paywall. A workout opens
  its page under the calendar, a cardio session its page (which finds only the
  500 newest sessions). If the programs cannot be read, what was done still
  shows. The calendar reports workout edits the server refused.
- **Weekly volume**: each completed working set counts 1 for every main muscle
  and 0.5 for every secondary one; warm-ups do not count, a drop set counts as
  one set. This is the programs' own counting (`muscleSets` in
  `exercises/domain/muscle_volume.dart`). An exercise's muscles are the
  library's current ones (custom exercises included), else, for a retired or
  deleted one, those stored with the workout. Each muscle is judged against
  the reference band of 10-20 sets a week whatever the user's level: below,
  within (both ends inside) or above. Progress → Weekly volume shows one week,
  the current one first; earlier weeks are free to browse, later than the
  current one never. A workout belongs to the week of the local date it
  started, like a program day, so a daylight saving change never moves it. The
  model is painted by weekly sets on the heat scale, which tops out at 20; a
  muscle with no sets keeps the body's colour. Tapping a muscle lists the
  exercises and workouts that gave it sets. The 12-week trend (the week shown
  and the 11 before it, each week's total sets) is free for everyone
  (2026-11-24), so the page always reads those 12 weeks. Changing week keeps
  the week before on screen until the next arrives, so the model keeps its
  camera. The Progress card reads the same use case with one week, never the
  trend.
- **Strength**: Progress → Strength lists the exercises with stats (the whole
  `exerciseStats` collection, live), most recently trained first, searched by
  catalogue name, custom exercises included; it stays loading until every
  exercise is named or known to be gone (one no longer in the library shows as
  removed, since stats keep no name). If that collection read grows too
  costly, the fix is a small last-trained index written in the same batch as
  the stats. An exercise's page opens from the list only. It charts each
  workout's best e1RM, lists the records (best e1RM, heaviest weight, most
  reps, best set volume, longest time) with the set that made them, and the
  sessions in the range; an exercise that never had an e1RM (bodyweight,
  timed) shows no chart and every session. A workout's best set: the highest
  e1RM (then the heavier, then more reps) for a load, the least assistance
  (then more reps), the most reps, the longest time, or the heaviest timed set
  (then the longer); a record's set among equal values is the heavier one (for
  the heaviest weight the one with more reps). Ranges: 2 weeks (the default),
  6 months, 1 year and all, every one free (2026-11-24); a range starts at
  local midnight of the same day that many months back, or that month's last
  day when it is shorter. Records are all-time.
- **Charts**: every chart is Forge's (`Chart.line`, `Chart.bar`,
  `MultiSeriesChart`); the app has no chart code of its own.
- **Cardio**: Progress → Cardio is one scrolling page (the studio): this
  week's summary (distance only when a session has one), the 12-week minutes
  chart, then the sessions per week, newest first; a session opens its page
  with Edit and Delete (2026-11-15). Weeks start on the app's first weekday
  for the summary, the chart and the list alike, as on the Progress card. The
  list follows the 500 newest sessions, plus the workouts of the last 366 days
  in Apple Health or Health Connect (through `forge_health`, read on opening
  and on app resume, never stored; the store's cardio kinds become the
  matching type, strength work is left out). Those need the workouts
  permission (Android: READ_EXERCISE, READ_DISTANCE,
  READ_TOTAL_CALORIES_BURNED, READ_HEART_RATE); without it none are read. The
  Steps page's Allow access asks for steps and then workouts. They show on the
  Cardio page, the Calendar (read once per user, marked and counted as cardio)
  and the Progress card, and cannot be edited or deleted here. Their tag names
  the store on iOS; on Android the app that saved them when its package is
  known (Strava, Google Fit, Samsung Health, Garmin Connect, Fitbit and a few
  more), else Health Connect. Pace is rounded to the nearest second.

### Body, steps and calculators

- **Weight log and measurement days**: Progress → Body. A quick log is an
  entry with only `weightKg` (today keeps the current time, another day is
  noon). A measurement day is a step flow, weight → each tracked measurement →
  front, right, left, back photos, every step skippable, the last one saves;
  nothing entered saves nothing. Edit re-runs the same form or flow,
  prefilled; skipping a step keeps the stored value (a value typed there is
  dropped), and only an emptied field with Next clears one; an entry's own
  measurements stay steps even if no longer tracked; a value left as shown
  keeps its stored metric value exactly. Leaving the flow asks first when a
  value differs from how it opened or a picture was taken. The flow loads the
  previous photos itself, so it works when opened first (e.g. from a
  reminder). Both sides of a pair (upper arm, forearm, thigh, calf) that are
  steps share one step with a Left and a Right field, skipped or cleared field
  by field as above.
  - `settings.trackedMeasurements` (the measurement codes of Data model) is
    stored only once the user chooses; every stored list counts as chosen.
    Until then the default is chest, waist, hips, both upper arms and thighs,
    plus the body-fat measurements of the profile's sex once it is known.
    Edited from the flow's app bar.
  - Limits: weight as the profile (30-300 kg), measurements 10-250 cm; values
    are typed to one decimal in the user's unit, so half a shown lb or inch
    step of slack lets the limits as shown pass (66.1 and 661.4 lb, 3.9 in).
  - Saving or deleting an entry sets `profile.weightKg` to the weight of the
    most recent dated entry that has one (calculators and the target distance
    use it); with no such entry the profile weight is left. A weight given
    elsewhere (onboarding's) is logged as a quick weigh-in dated now, unless
    that day already has a weigh-in.
  - Firestore rules validate `bodyEntries` (date timestamp, numeric
    `weightKg`, `measurements` and `photos` maps whose known keys hold numbers
    and strings).
- **Body page** (2026-11-13, 2026-11-16): two views, Overview and Compare (the
  measurement summary's comparison, below); the looks are in the studio.
  Overview's three figures: the latest weigh-in's weight, the newest body fat
  and the lean mass of the two, each changed against the measurement day
  before the newest one, counted only for values dated after it. The chart
  shows up to three series the user picks: weight, body fat, fat mass, lean
  mass and every measurement as lines, weekly sets and daily steps (a week's
  average, today's partial day left out) as bars, plus the target weight line
  while weight shows. Weight carries its rolling 7-day average (the mean of
  the weigh-ins in the 7 days ending on each, within the range). Each series
  keeps its own scale; tapping a day shows the values of that date (a pair of
  measurements as the mean of its sides). Every series and every range is free
  (2026-11-24); the ranges are Strength's, and the range control shows only
  with entries older than 2 weeks. Daily steps show only where the health
  store can be read; under "All" they go back to the oldest body entry or one
  year, whichever is older. The choice of series is kept on the device only
  (2026-11-13), one JSON file per user in the app support directory, so there
  is no data model field and a new device starts from the default (weight, and
  body fat once an entry has one); an unreadable file counts as not chosen.
- **Body fat** (derived, never stored): US Navy, the calculators' own formula,
  from an entry's measurements and the profile's sex and height. The waist is
  measured at its narrowest and the abdomen at the navel, so men need `neck` +
  `abdomen`, women `neck` + `waist` + `hips`; which measurement is the
  formula's waist is one mapping, shared with the calculators' prefill. An
  entry without them, or with values the formula rejects, shows none. Shown
  with one decimal as a chart series (only once some entry has one), in each
  history row, on the entry and as a change in compare. "Measurements to
  track" has a Body fat box: ticked exactly while all its measurements are
  tracked (nothing stored); ticking it ticks them, unticking it unticks those
  not in the standard set (men: neck and abdomen; women: neck), keeping the
  rest; if none would change it stays ticked and says to untick one of them.
  Without the sex or height it links to the profile details instead. Each
  measurement step shows a one-line hint of where to put the tape.
- **Camera orientation**: the photo camera holds the screen in portrait and
  locks the capture to portrait. `camera_avfoundation` 0.11.1 turns the iPhone
  17 family's Center Stage front camera 90° wrong (flutter/flutter#196204, no
  fix released), so the app overrides it with a patched copy in
  `third_party/camera_avfoundation` (pristine 0.11.1 minus `example/`; every
  change marked `PATCH` in `DefaultCamera.swift`). The patch applies the fixed
  angles relative to the connection's starting rotation; `RotationCoordinator`
  follows the phone's physical orientation and so cannot honour the portrait
  lock.
- **Measurement summary** (2026-11-16): one screen at
  `/progress/body/summary/:id`, opened in place of the flow right after a new
  measurement day is saved, never after an edit. The same comparison is the
  Body page's Compare view, which a measurement day's page opens for that day
  at `/progress/body?compare=<id>`. Without a link Compare shows the newest
  measurement day that has an earlier one, the only measurement day alone, or
  that there is none; the later day can be picked from the measurement days
  after the earlier one. A measurement day is an entry with measurements or
  photos (quick weight logs are not, as for the reminders). The baseline is
  one of the measurement days dated before the entry: the previous one by
  default, the first (oldest) or any other of them; the control shows only
  with two or more. A chosen day that is deleted or moves after the entry
  falls back to the previous day. Body fat, fat mass and lean mass come from
  each day's own weight (fat and lean mass need the later day's weight);
  otherwise a notice says what is missing (sex or height with a link to the
  profile, the measurements, values the formula rejects, the day's weight).
  Every value either day has shows before → after with the difference. The
  target (hidden without a target weight or a weight that day): an estimated
  date at the rate between the two days, given only when the target is not
  reached (within 0.05 kg), the earlier day has a weight, the days are at
  least 7 days apart, the weight moved toward the target, and the date is
  between now and 2 years from now; else the distance, or that it is reached.
  The photos of every pose either day has are compared on Forge's before/after
  slider; both days' photos are fetched from the backup when missing, once per
  screen. Without an earlier measurement day the screen shows the day alone:
  its values without changes, the target, and the photos without a slider.
- **Photos**: private app storage plus Cloud Storage backup. Never the gallery
  and never the device's own backups: Android's backup rules
  (`res/xml/data_extraction_rules.xml`, `backup_rules.xml`) exclude
  `files/users/` and `files/body_photo_backup.json`; iOS sets
  `isExcludedFromBackup` on the photos' folder (the
  `getworkout/backup_exclusion` channel in `AppDelegate.swift`).
  - Taking: `forge_camera`'s ghost camera, the previous photo of the pose at
    35% over the live preview (mirrored with a mirrored front-camera preview);
    back camera first. Stored shrunk (longest side 1600 px, JPEG 85, turned
    upright, metadata such as location stripped) in the app support directory
    at the storage path, the same string the entry's `photos` map holds. The
    camera's own file is removed once stored, on a retake or skip, and when
    the flow is left. A path carries a revision (`{pose}-{capture ms}.jpg`),
    so a retake is a new path and every device sees its copy is out of date. A
    photo can be retaken, not removed alone.
  - Saving is one change: all photos are stored, then the entry is written,
    and only then are uploads queued; a failure removes what that attempt
    stored, and a retry reuses the flow's entry id. The photos a retake
    replaced, or a deleted entry's photos, are removed (here and queued for
    the backup) only once the server confirms the write; a refused save
    removes its new photos instead, so an undone change leaves nothing.
  - Backup runs in the background: every photo's state (upload, delete,
    uploaded) is kept in `body_photo_backup.json`, written one save at a time;
    a file that cannot be read is renamed `.unreadable-<time>` and never
    overwritten. Work is done for whoever is signed in, the user checked
    before each task; failures stay queued and are retried at start, sign-in,
    app resume and the next queued change; a newer state for a path wins over
    a task still running. Nothing is uploaded or fetched while signed out.
    Each entries snapshot reconciles: photos on the device that an entry names
    and the queue does not know are queued for upload (a lost queue, or photos
    from before the backup). A photo missing on the device (a new phone, or a
    retake made on another one) is fetched when a page shows it.
  - Account deletion stops the user's backup and drops their queue before the
    `deleteAccount` callable runs, so no upload lands after the server deleted
    `users/{uid}/`; it resumes the backup if the deletion did not happen, and
    removes the photos with the rest of the device data. Guests are backed up
    like accounts: their uid is the one linking keeps. A guest who is left
    (signed out, or replaced by signing in to an existing account) can never
    come back, so their photos and queue on the device are removed at that
    moment.
  - Orphans: on every sign-in, once the server has answered (a snapshot not
    from the cache; unlimited, so old entries count, and including writes not
    sent yet), the user's photos on the device that no entry names, the queue
    does not know and are older than ten minutes are removed: those of a save
    stored but never written, or refused while the app was closed.
  - `storage.rules`: owner only, `image/jpeg`, under 5 MB, file names
    `(front|right|left|back)-<digits>.jpg`.
- **Steps**: read-only from Apple Health / Health Connect through
  `forge_health`; never stored. The platform store in every build on iOS and
  Android; the fake only in debug and profile builds on other platforms. The
  Steps page (Progress tab; the studio) reads the last 30 days in one call and
  derives today and the week from it; it reloads on app resume and on pull,
  never by polling. Access: unless already granted, a one-screen explanation
  comes first and the system is asked only after "Allow access"; that the user
  was asked is remembered on the device (a marker file in app support),
  because HealthKit never says. An Android refusal offers opening Health
  Connect and asking again; a missing Health Connect offers its store page. On
  iOS a month of zeros shows a hint to allow access in Settings, never a
  denial. A failed refresh keeps the steps and says so. The page shows this
  week or the last 30 days (the choice kept only while the page is open, week
  first), with the daily average and the days the goal was reached counted
  over the chart's days before today (today's partial day and days to come
  left out, as on Body; hidden on a period's first day). The goal is
  `settings.stepGoal`, 10,000 by default, 1,000-50,000, in steps of 100; a
  typed number is saved on the nearest 100 (2026-11-15). Each change saves at
  once; the row shows and steps from the last pick until its write comes back,
  so quick taps all count, and drops it when a save fails. Open: the steps
  domain imports `forge_health` whole, platform code included; once the
  package exposes a domain-only library, import that instead.
- **Calculators start from what the app knows**: one read of the profile and
  the body entries when a calculator opens. Sex, age (current year minus birth
  year) and height from the profile; weight from the newest dated entry that
  has one, else the profile; neck, waist, abdomen and hips each from the
  newest entry that has it (they may be from different days: neck is rarely
  measured and changes little, waist drives the result); body fat (BMI/FFMI)
  by the US Navy formula from those, when sex, height and the measurements
  allow it; activity from `daysPerWeek` (2 light, 3-5 moderate, 6 active). The
  body fat calculator shows the waist measurement of the selected sex (abdomen
  for men, waist for women), none while the sex is unknown. 1RM and the
  macros' calories stay empty (no single source); the goal and target weight
  map onto no calculator input. A value from the body log shows the date it
  was measured (body fat takes the oldest of its circumferences'); profile
  values have none. Known values are starting values only: nothing is written
  back. A value arriving late fills only inputs the user has not changed; a
  value the user saved is theirs, even one they cleared. A source that cannot
  be read adds nothing. An input rejects a value outside its range; reps take
  1-100, so a set above 12 reaches its own row message.
  - Bars: units, bar and plates come from settings. The EZ bar and the trap
    bar have their own weights next to the bar's, defaulting by the unit (EZ
    10 kg / 25 lb, trap 25 kg / 55 lb) until customised; the workout's plate
    breakdown uses the bar of the exercise's equipment (barbell first, then
    trap, then EZ).
  - Calories: the daily energy need is maintenance, with lose, keep and gain
    rows at 7,700 kcal per kg: 0.5 kg and 0.25 kg a week, or 1 lb and 0.5 lb
    for a pound user (named unrounded); a target raised to the daily minimum,
    or no loss below it, says so.

### Help, feedback and the review prompt

- **Help & feedback**: two ways in: Profile › More › "Help & feedback" (source
  `profile`) and "Write to us" in the review prompt, which opens the form
  above the page that asked (source `rating`). A message (at most 2000
  characters) and an optional reply email, prefilled with the account's (an
  Apple relay address included; empty for a guest); no topic. The app adds its
  version, the device details and the user id; device details that cannot be
  read are sent empty rather than stopping the message. Sending writes
  `users/{uid}/feedback/{id}` (Data model) without waiting for the server,
  like every write: offline it goes out later. The form checks what the rules
  check; a write the rules refuse after that is only logged. No email or push
  notification of new messages (owner's choice); they arrive in the admin
  panel's Support inbox.
- **Review prompt** (forge_review; 2026-11-20): two kinds of moment. Every
  workout summary counts once on the device (by workout id); every app open
  (Today shown at launch, and each resume) counts the local calendar day once.
  The first ask comes at the first moment that can ask once two workouts were
  counted or the app was opened on three different days, whichever comes
  first: the second workout's summary, or Today at an open on or after the
  third day. The summary of the user's first workout ever counts but never
  asks. Later asks only at a summary with a new record at least 30 days after
  the last ask; never twice in one app version (`FeedbackModule.reviewRules`).
  A free user's summary that asks still leaves through the workout paywall:
  the ask while the summary shows, the paywall on Done. Today asks only while it
  is in front with nothing over the tabs (no paywall, workout, dialog or
  sheet); a day counted while covered asks at the next open that is not. An
  ask is recorded when it is decided, so closing the app on it still counts,
  and one covered in the instant between deciding and showing is spent unseen.
  The history lives in shared preferences, so a reinstall starts it again. The
  ask is the app's own question first: yes opens the platform's review prompt,
  and the platform decides whether it shows (iOS: at most 3 times a year;
  never in TestFlight); no offers the feedback form.

### Notifications

- **Reminders**: `settings.reminders` (Data model) holds a workout reminder (a
  time of day) and a measurement reminder (every 1, 2 or 4 weeks from a first
  date, which also gives its weekday); both are off by default.
  - Workout: one local notification at the time on every date the schedule
    plans a day for, 28 days ahead (at most 28 pending); none for a day done
    on that date, none once the program has run its length, none for a locked
    premium copy. Only the next day is named; later ones name the program, as
    they are due only if the user keeps to the plan.
  - Measurement: one for each of the next four occurrences of the series
    except dates that already have a measurement day (quick weight logs do not
    count), so a measured one leaves three and the ids stay distinct. Picking
    the series' own weekday or cadence changes nothing; another weekday
    restarts the series on that day's next date.
  - Horizon: reminders are only planned while the app runs, so a user who does
    not open the app for four weeks gets no more workout reminders, and the
    measurement reminder stops after its four planned occurrences.
  - Planning runs again on every program list, settings or measurement-day
    change, on every user change and on resume; equal pending reminders stay.
    While the user's settings, programs or measured dates load or fail, or the
    premium status of a premium copy is unknown, the pending ones are left as
    they are, so a start never drops reminders; a reminder turned off is
    always cleared, and a change of user or signing out drops them at once.
  - Ids: rest 1; on the Android lock screen rest countdown 2 and workout in
    progress 3; workout 100-127 (by date); measurement 200-203 (by
    occurrence); announcement in front 300. Android channels: `workout` for
    everything except the rest countdown (`rest`); both are created when
    notifications initialise at app start (no permission needed), so a pushed
    announcement finds `workout` before any local notification. Reminders do
    not ask for exact alarms on Android (they may fire up to an hour late).
  - Taps: a workout reminder opens Today (tapped while the workout in progress
    is in front it stays there), a measurement reminder a new measurement day
    (unless one is already open), an announcement Today. A tap at launch waits
    until the app is past splash and onboarding.
  - Permission: turning a reminder, or the rest notification in the settings,
    on asks in the app first (unless the device already allows), then the
    system; after a refusal the wish is stored on anyway and the app's
    notification settings are offered; declining the app's own question
    changes nothing. While the device refuses, the Reminders group starts with
    a notice that asks on a device never asked, else opens the settings. The
    platforms read a device never asked as refused, so the app keeps a marker
    file (`notifications_asked`, app support) written by every request.
- **Announcements**: FCM topics `announcements_<locale>` (`announcements_en`
  in v1), followed once the device allows notifications, for the device's
  language, leaving the other languages' topics. Notification messages: the
  system shows them in the background (Android: channel `workout`, icon
  `ic_notification`); in front the app shows them as a local notification. A
  tap opens Today; no deep links in v1. Besides the language's topic the
  device follows `announcements_<locale>_free` or `_premium` as the user's
  Premium entitlement says, leaving the other, and switches when it changes;
  while it is unknown the tier topics are left as they are. Everyone stays on
  the plain topic, which app versions before the split also follow
  (2026-11-24). Follows run one at a time, so two Premium changes never
  interleave their topic changes. Without a push token (iOS without APNs)
  nothing is followed and nothing fails visibly; a failed subscription is
  tried again on resume. Allowing notifications never waits for the
  subscription. FCM auto-init is off in the native config
  (`firebase_messaging_auto_init_enabled`, `FirebaseMessagingAutoInitEnabled`)
  and turned on only when following, so a device that never allows
  notifications gets no push token. The install's push token is stored on its
  device record for the panel's test sends (Admin panel › Device records). The
  topic following, the foreground display and the token are forge_messaging's;
  the app passes in the prefix, its languages, the segments `free` and
  `premium`, id 300 and the payload.
- **iOS push set-up**: the APNs key W3KP8AP8K2 is uploaded to both Firebase
  projects (development and production). The first topic follow right after
  notifications are allowed may find no APNs token yet and subscribe only at
  the next start or resume.
- **Sending announcements**: the admin panel's Announcements page calls
  `sendAnnouncement` (Data model › Cloud Functions has its idempotency and
  failure rules) for a language of `languages` and an audience (everyone,
  free, Premium), now or at a scheduled time, after a confirmation that it
  cannot be recalled. Title at most 65 and body at most 240 characters after
  trimming (UTF-16 units on both sides; longer is cut off on most lock
  screens). A send carries a random request id; the page sends the same
  trimmed text and language again under the same id, a new id only for other
  text or after a send went through, so a retry after an unclear failure
  (offline, timeout) never sends twice. The history is
  `announcements/{requestId}`, the latest 50. A request still `sending` 5
  minutes after `requestedAt` shows as unknown (check a device before sending
  again); nothing recovers it automatically. Messages carry the Android
  channel `workout`, APNs `sound: default` and a time to live of 3 days, so a
  dated announcement is dropped rather than arriving weeks late.
  - Schedule (2026-11-24): a new schedule starts on the next full hour at
    least an hour away, in the admin's local time; a time under a minute or
    over 30 days away is refused with the reason, and the time is checked
    again on Schedule. After a send the form keeps its language and audience
    and goes back to Now. Scheduled rows sort soonest first and can be
    cancelled after a confirmation; a cancelled one stays in the history.
  - A test send goes to the admin's own devices; its result shows apart from
    the send's and it is not recorded.

### Analytics

Decision (2026-11-20): Firebase Analytics with the BigQuery export (no second
analytics tool), collection on by default with an opt-out, and reports in the
admin panel's Dashboard, not in a separate dashboard tool.

- **Collection**: Analytics and Crashlytics collect for every user in prod
  release builds unless that user turned "Share usage data" off (Profile →
  Privacy). `settings.analyticsConsent` keeps its meaning per user: false is
  off, true or null (never answered, including everyone who has not been
  asked) is on. Users who said no before keep no. No consent page is shown, in
  onboarding or over the tabs. Still never the advertising ID, Android ID or
  IDFV, and no ad personalisation signals. Legal basis in the privacy policy:
  legitimate interest with an opt-out; the owner accepts the KVKK/GDPR risk of
  not asking first.
- **Held until the answer is known**: a new install collects only once the
  user's stored answer is read. Until then Forge's telemetry holds events and
  screens (at most 100), sends them in order on collect and drops them on a no
  or a user change; the user id and the user properties are set once
  collection starts.
- **User id**: the Firebase uid is the Analytics user id (also RevenueCat's
  app user id), so events can be joined with Firestore and RevenueCat in
  BigQuery; it is cleared on sign-out and reset on account deletion.
- **Screen views**: `screen_view` whenever another page, sheet or dialog route
  comes in front, a tab switch included, named by the route (`today`,
  `program_detail`, `paywall`, …; the names sit on the routes in
  `router.dart`), not by widget class. A dialog or sheet opened without a
  route logs none.
- **Events and user properties**: the catalog is the code:
  `lib/features/analytics/domain/analytics.dart` holds every event, user
  property (`level`, `goal`, `days_per_week`, `premium`, `acquisition`,
  `account`, `has_program`), parameter and code. Rules the code cannot say:
  - Names are snake_case; parameter values are codes and content ids, never
    free text; flags are `"true"` / `"false"` strings, as Analytics takes no
    booleans.
  - `paywall_view` (the paywall A/B test's activation event) and
    `paywall_purchase` (its goal) keep their names and the `layout` parameter
    unchanged. `moment` is `user` for a paywall the user opened; `offering` is
    left out when the store gives none.
  - `notification_tap`, not `notification_open`: Analytics reserves that name
    for FCM and refuses it. `app_exception` is Crashlytics' own.
  - `premium_lock_tap` has two features, `generator` and `premium_program`;
    nothing else is locked.
  - Only new entries are logged: `weight_log`, `measurement_day_save` and
    `cardio_log` not on edits, `program_create` / `program_edit` only on the
    builder's save (Save as program after a workout logs none).
  - `workout_start` is `free` or `program` when the workout starts and `past`
    when a new past workout is saved; `workout_complete` is for live workouts
    only. An empty workout left again is no `workout_discard`. `workout_count`
    is the server's count before the workout plus one, left out when the
    server does not answer; then `first_workout_complete` follows the
    summary's first-ever. `personal_record` is one per record kind beaten.
  - `onboarding_step` fires each time a step shows, Back included; the
    permission prompts come before the program suggestion, and `permissions`
    fires once, at the first prompt. `onboarding_complete` fires when the
    suggestion is left.
  - `sign_up` is a guest linking (it fires before an email address is
    verified), `login` signing in to an existing account; an account with
    several ways in names one (Apple, then Google, then email). `sign_out` is
    logged before the sign-out so it is still the user's; `account_delete`
    once the server deleted the data, before collection stops. Deleting an
    account resets Analytics, so the next guest is a new `first_open`.
  - `program_start` is `onboarding` when the program page was opened from the
    suggestion; `program_generate` counts every generated program, Regenerate
    included. `exercise_search` is a search typed into an empty field, in the
    library or the picker. `steps_connect`'s `granted` is whether steps can be
    read (iOS never tells a refusal). `rest_skip` also counts on the lock
    screen.
- **Checked** (2026-11-20, 2026-11-21): the events were seen on the iOS
  simulator against dev. Not seen yet: Android. Crashlytics symbol upload
  works: the Runner's `flutterfire upload-crashlytics-symbols` phase reads
  `firebase.json` (Debug/Profile → dev app, Release → prod app). Debug builds
  make no dSYM, so the dev console lists those as missing; that only affects
  simulator crash reports.
- **BigQuery** (2026-11-20): Firebase is linked to BigQuery on prod and dev.
  Google Analytics exports daily only (no streaming: the Dashboard shows up to
  yesterday), all three apps, no advertising identifiers, into
  `analytics_<property>` in the `europe` multi-region. Crashlytics exports too
  (`europe`), for crash-free rates on the Dashboard. The privacy policy states
  14 months: that is Google Analytics' own retention for event and user data
  on both properties (prod 565341735, dev 565325900, account "Default Account
  for Firebase" 146870395) and the default partition expiration of
  `firebase_crashlytics` and `firebase_sessions` on dev and prod (2026-11-21).
  Open: `analytics_<property>` (daily `events_` tables) gets a 14-month
  default table expiration once its first export lands.
- **Dashboard functions** (`functions/src/dashboard`): the Dashboard reads
  BigQuery and RevenueCat's metrics through admin-only functions, never from
  the browser. Each project has its own panel: the prod panel shows prod data,
  the dev panel dev data. `dashboardNightly` (09:00 Europe/Istanbul) and the
  admin-only `dashboardRefresh` store the reports in `dashboard/`: the 7, 30
  and 90 day periods (ending at the latest `events_` day), retention (8
  complete weekly install cohorts, day 1/7/30), revenue and a status (`ok`,
  `no-data` before the first export, or `error` naming the parts that failed;
  the others are still written). The admin-only `dashboardRange` answers a
  custom range of at most 366 days live. Admins read `dashboard`;
  `revenueEvents` and `dashboardRevenue` stay server-only.
  - Revenue is RevenueCat's API v2 overview metrics, prod only: RevenueCat has
    one project, so the dev panel shows no revenue (2026-11-21). A daily copy
    is kept in `dashboardRevenue/{day}`; MRR of a past day is the latest
    snapshot in the week up to it, read ascending (a descending id query needs
    an index). Deploying needs the `REVENUECAT_API_KEY` Functions secret (a v2
    key with `charts_metrics:overview:read`) on both projects.
  - `revenueCatWebhook` also keeps every event it reads in
    `revenueEvents/{event id}`. Trials and paid purchases count production
    events on prod and sandbox ones too on dev; they join Analytics through
    the user id. Deleting an account clears the uid from its `revenueEvents`
    (sums kept, 2026-11-21), before and once more after the sign-in goes.
  - Users in crash-free and top issues are Crashlytics installations against
    Analytics' active app instances.
- **Dashboard page** (`/dashboard`, the panel's landing page; 2026-11-21): ten tiles over
  Growth, Funnel, Retention, Revenue, Usage and Quality, for 7, 30 or 90 days
  or a custom range, each tile with its change against the period just before.
  It reads every `dashboard` document once on open and again after Refresh now
  (client timeout 540 s). A custom range lies in the 14 months up to the last
  day (timeout 300 s; longer than 366 days is refused before asking). Before
  the first export it shows that there is no data yet and the revenue snapshot
  only. Tile changes: counts in whole percent (nothing when the previous
  period is unknown or zero), shares in points to one decimal.

### Admin panel

- **Menu** (2026-11-21): a left menu in groups
  (People, Content, App), opening on Dashboard. Dashboard is under Analytics
  above, Announcements under Notifications.
- **Users** (2026-11-21; the functions are in Data model › Cloud Functions):
  an email/uid search over a table of the latest sign-ups with Load more. A
  user's page keeps every action in one panel (Premium grant and revoke,
  password reset, admin grant and revoke, delete) and lists the user's
  devices. Granting Premium offers 1 week, 1 month, 1 year and Lifetime;
  deleting an account is confirmed by ticking a box. Granting and revoking
  need RevenueCat write permissions on the `REVENUECAT_API_KEY` v2 key.
- **Device records** (`users/{uid}/devices/{installId}`, Data model): the app
  records the device for each signed-in user at launch, after every sign-in or
  account switch and when FCM issues a new token, but writes only when the
  user, model, platform, OS version, app version or push token changed since
  this install last wrote, or that was 24 hours ago or more, so "last seen" is
  right to the day. The token is read only once FCM auto-init is on (after
  notifications were allowed), so no install gets one just for this. Before
  every sign-out (Account's and the email verification page's) the app clears
  the token from that user's record of this install, so test announcements
  stop reaching a device its admin left (2026-11-24). Best effort: it gives up
  after 3 seconds (offline) and the sign-out goes on; the next user's record
  then carries the token.
- **Support inbox** (`/support`; 2026-11-21): the threads (Open and Closed,
  the latest 100 of each, live) beside the picked thread; it replaces the
  Feedback page. A thread is New, Replied (set by sending a reply) or Closed.
  Reopen puts it back to New, or Replied once replied to; a closed thread
  keeps the reply box, and sending reopens it as Replied. A picked thread
  stays open when it moves to the other list. Replies go through
  `sendSupportReply` (Data model › Cloud Functions), at most 5000 characters,
  as Send reply or Send and close. The email comes from the bare
  getworkout.support@gmail.com and quotes the user's message. A failed send
  keeps the text and says why; sending the same text again reuses the request
  id, so it is never emailed twice. A reply still sending after 5 minutes says
  it may not have been emailed. A sender who left no email gets no reply box,
  only a note saying why and Close. The Gmail app password is the Functions
  secret `SUPPORT_GMAIL_APP_PASSWORD`, also kept in the keychain under that
  name.
- **App settings** (`/app-settings`; 2026-11-21): the app's Remote Config keys
  on one page, in two groups: Paywall (`paywall_layout`) and Update and
  maintenance (`maintenance`, `maintenance_message` and the four version keys,
  checked as versions). Apps fetch within 12 hours.
  - `paywall_layout` stays editable while its A/B test runs (2026-11-21) and
    the page says a change also reaches users outside the test, since A/B
    Testing's experiments are not in the template.
  - A key using the in-app default shows the app's default; editing it
    publishes an explicit value. Setting a changed field back removes the
    change. A key's conditional values (A/B tests, language conditions) are
    listed read-only and never written; a default set by an experiment,
    rollout or personalization shows as such with no input.
  - Publishing confirms with only the changed keys and makes a new version.
    After a publish the page reloads, keeping edits that still differ. A
    publish refused as stale offers Reload; the edits stay, compared against
    the reloaded values.
  - History lists the latest 20 versions with who published (the admin's
    email, or the Firebase console). An older one shows what restoring it
    would change in these keys (defaults only; conditional values and other
    parameters stay); restoring publishes those defaults as a new version.
- **Exercises and Programs** (2026-11-21): both lists are a table
  with a filter column and a one-line health summary whose Details opens the
  full list. The editors have separate Save (stays Live), Save as draft and
  Retire; blocking problems are summed up at the top, each leading to its
  field.
- **Program editor**: edits `programs/{id}` and its `detail/main` in one
  transaction, so both are written or neither; a save is refused when either
  changed since the editor loaded them, and keeps `contentHash` and unknown
  card fields, as the exercise editor does (unknown fields inside days and
  items are dropped, as the import rejects them). `daysPerWeek`, `equipment`
  and `minutes` are computed from the days on save and shown read-only, so
  they always match the rules. Every save, drafts included, must pass
  `programProblems` and have an unused id and a unique name and order, as the
  import rejects an invalid file whatever its status; the 6 free / 23 premium
  split of live programs shows as catalogue health and never blocks, nor do
  the weekly-set warnings. The picker offers live exercises; a new item takes
  the builder's defaults and the exercise's rest.
- **Table sorting and filters** (2026-11-21): every column header of Exercises
  and Programs sorts, a second click flips it. Until a header is clicked the
  order stays popularity (Exercises) and catalogue order (Programs); blanks
  are last either way, ties fall back to the default order. Filters combine
  (AND).
  - Exercises "Problems only" is an exercise the library health concerns: an
    invalid document (which covers every missing required field), one an error
    or warning names by id, or a live member of a family a finding is about;
    library-wide findings such as coverage or an unused popularity name none.
  - "Unused by programs" is an exercise no program of any status uses; a
    retired exercise never counts as unused. It is its own switch because
    unused exercises outnumbered the real problems about 250 to 2.
  - Programs "Problems only" is a program the editor would show a catalogue
    rule problem or a weekly-sets warning for.
  - Both lists read every program's days, one listener per program's
    `detail/main` (a collection group query would need a new rule); the
    Programs list also reads the exercise library for the rules.
- **Generator**: one draft of `generator/rules` edited over five tabs
  (Templates, Dosing, Volume, Selection, Areas) plus the Simulator; switching
  tabs keeps the edits. It shares the publish bar, the change table and the
  history pane with App settings.
  - Changes: a changed field shows its old value; templates and splits are
    matched by id, and a template added in the draft stays new whatever id it
    is given, its id editable only then. A split can be removed only while no
    template uses it. Number fields write only text that reads as a number;
    scores take negative numbers; chip lists keep their stored order.
  - The server is the only validator: `generatorRulesCheck` runs a second
    after the last edit and before the review; each problem leads to its tab
    and field. An edit that adds, removes or moves an item drops the previous
    problems at once. Review and publish waits for a check of the current
    draft without problems.
  - The review lists every change, the check's warnings for the draft against
    the loaded version's own (standard answers with no program, a target
    muscle without direct work, a day under half the session) and takes an
    optional note (at most 300). The page stays publishing until the new
    version is loaded. A `stale` refusal keeps the draft and offers Reload;
    the draft is then compared with the new version.
  - History lists the last 20 versions; picking one puts its rules into the
    draft (asking first when there are changes), and the publish says it
    restores that version while the draft is unedited since. Leaving the page
    with changes asks first, and the browser asks before the tab is closed or
    reloaded. With no rules published (version 0) nothing is editable: the
    content import seeds the rules.
  - Simulator: runs `generateProgram` with `explain: true`, against the
    published rules or the draft (sent as `rules`). Its answers are its own,
    kept while switching tabs and never part of the draft; a change of rules
    drops what they do not offer. The draft can be run only once checked
    without problems; with no changes left or with problems it falls back to
    the published rules, saying why. The server caches the published rules for
    60 s, so when a published run's version is not the loaded one the page
    says so and shows the weekly sets without targets. A scored exercise opens
    to its score's parts and the next candidates; weekly sets show against the
    level's targets plus the focus extra.
- **RevenueCat web script**: the admin web build bundles and loads the
  RevenueCat web script, because `purchases_flutter` registers a web plugin.
  Harmless; revisit if the admin build is split from the app.
