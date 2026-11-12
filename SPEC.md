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
- **Client vs server Premium**: until the RevenueCat webhook exists nothing
  writes `entitlements/{uid}`, so client Premium (fake or RevenueCat) and
  server access can disagree. Features treat a server refusal of premium
  content as locked, whatever the client says. On dev,
  `tool/set_premium.sh` writes the entitlement for demos.
- **Paywall**: full-screen `/paywall`, yearly selected by default, prices as
  the store gives them, trial shown only when the plan carries one, restore
  and legal links always visible. Terms and privacy URLs live in
  `lib/app/legal_links.dart`; placeholders until the pages exist.
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
- **Offline**: Firestore's persistent cache is the local database. The workout
  in progress is also kept in a local file so a crash never loses sets.
  Derived numbers are computed from workouts on read wherever the query is
  small; the only stored summary is `exerciseStats`.
- **3D model**: our own renderer, written in Dart, built first because it is
  the riskiest part. Source model has 37 meshes: 19 muscle groups (left/right
  split except abdominal and oblique) plus the body. A female model with the
  same mesh names is required before release; the user supplies it.
- **Units**: stored metric. kg/lb and cm/in chosen by the user.
- **Programs**: a name of 1-60 characters, 1-7 days, day names of at most
  40 characters, 1-20 exercises per day, an optional length of 1-52 weeks;
  lengths count UTF-16 code units in the fields and in validation. The
  Firestore rules validate the top-level fields only (`name`, `days` count,
  `origin`); the app validates days and items. Items whose exercise's
  logging type changed are fitted to the new type when the builder loads
  them, and the user is told.
- **Schedule**: `activeProgram.nextDate` is a calendar date stored as a
  `YYYY-MM-DD` string, so it is the same date in every time zone, and
  `startedAt` is a device-clock timestamp because starting a program must
  work offline. A missed next day stays the next day until the user does
  it today, moves it to the next training weekday or skips it; the week
  plan shows it once, on its date. A program with a length ends that many
  weeks after its start date.
- **Effort scale**: optional per set, off by default. RIR by default, worded
  plainly ("How many more reps could you do?"); RPE selectable. Stored as RIR
  (`rpe = 10 - rir`).
- **1RM**: Epley, `weight * (1 + reps / 30)`; sets above 12 reps are ignored.
- **Volume**: each completed working set counts 1 for every main muscle and
  0.5 for every secondary muscle. Warm-up sets do not count. A drop set counts
  as one set. Reference band is 10-20 sets per muscle per week.
- **Equipment profiles**: one list, `EquipmentProfile` in
  `vocabulary.dart`, serves onboarding's quick picks and the catalogue's
  `equipmentProfile`. Full gym = everything; home gym = barbell, plates,
  dumbbells, bench, pull-up bar (a barbell at home implies a rack, which has
  no code); dumbbells = dumbbells and a bench; bodyweight = pull-up bar and
  dip bars; bands = resistance bands. Bodyweight is always available and is
  never stored. Profiles store only equipment codes, so changing a pick's
  equipment never touches stored data.
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
  "Use this program" waits for the exercise library and the user's
  programs, and is blocked with a message when a day uses an exercise no
  longer in the library (copying without it would change the program). It
  copies the program into `users/{uid}/programs` (`origin: catalog`,
  `sourceId`, `premium` for a premium one) through the builder's
  validation and opens the copy, which is started like any own program;
  when a copy from the same `sourceId` exists, it is offered first. An
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
  free recommendation is offered (use it, browse, or Today); with none, or
  the catalogue offline, onboarding lands on Today, and so does signing in
  from onboarding to an account already onboarded.
  `ProgramsModule` takes the premium status and the premium action as
  parameters, so programs never import the subscription feature; bootstrap
  passes `SubscriptionModule.premiumStatus` (the app-level
  `EntitlementCubit` as unknown / free / premium) and
  `SubscriptionModule.showPaywall`. The program cubits follow that status,
  so a page updates by itself once the paywall grants premium; pages get
  the premium action from their page widget, never from `sl`.
- **Copies of premium programs** (decided by the user, 2026-11-11): a copy
  of a premium ready-made program is marked `premium: true` and keeps the
  mark through edits and duplicates. Without premium it stays visible and
  readable but cannot be started, rescheduled or trained; an active one
  shows as locked on the Programs tab and is not stopped, so it resumes
  when premium returns. While the premium status is unknown these actions
  wait. `programAccess` is the one check, also for starting a workout
  from such a program (Start <day> on the Programs tab, ▶ per day on the
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
- **Steps**: read-only from Apple Health / Health Connect; not stored.
- **Photos**: private app storage plus Cloud Storage backup. Never the gallery.
- **Privacy**: minimal set. In-app account deletion, privacy policy link,
  consent for analytics and crash reports. No age gate, health notice or data
  export (the user accepted the EU risk).
- **Onboarding questions**: goal, level, days per week and equipment need
  an answer to continue. The personal questions (sex, birth year, height,
  weight, target weight) can each be skipped with "Skip this question";
  "Skip for now" still ends onboarding with whatever was answered.
- **Birth year**: a plausibility range (age 13-100), not an age gate. An
  implausible year is only not accepted as an answer; nothing is blocked.
- **Custom exercises**: ordinary exercises everywhere the catalogue is
  listed (the catalogue cubit merges the signed-in user's in), marked
  "Custom". Ids are `custom_` plus a Firestore auto id, so they never
  collide with catalogue ids (`ex_...`) and an id alone tells which kind it
  is. They have no level, movement pattern or family: level and pattern
  filters never match them, and they have no alternatives or variations
  and are no one's. They sort first, by name, in popularity order. A name
  may repeat a catalogue name; the label tells them apart. Equipment left
  empty means unspecified and counts as doable with any. Deleting one also
  removes it from favourites in the same write; programs then show it as
  unavailable, like a retired exercise, and workouts keep their copy. Added
  to a program, one rests 90 s by default, having no rest of its own. The
  500 limit is checked by the app on create, counting what Firestore's
  cache holds (kept current by the catalogue's listener); rules cannot
  count.
- **Notifications**: local for rest end, workout reminders and measurement
  reminders; FCM topic push for announcements.
- **Navigation**: five tabs, Today / Programs / Exercises (center, the model)
  / Progress / Profile. The active workout is full-screen and can be minimized
  to a bar above the tabs.
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
- **Logging a set**: empty fields show a suggestion, which ticking takes;
  each value comes from the first that has it: this workout's previous done
  set of the same type and exercise, the same working set last time, the
  program target (weight, bottom of the rep range, duration). A warm-up only
  follows the warm-up before it. A done set edited into an invalid one is
  unticked. A weighted or assisted bodyweight set without a weight has none
  added. Effort is a whole number: RIR 0-5 (5 means 5+) or RPE 10-5. Sets
  take a note of up to 200 characters. Durations are typed in seconds; a
  minutes and seconds input is left to the design phase.
- **Records**: heaviest weight (every type with a weight except assisted),
  best e1RM and best set volume (`weight_reps`, `weighted_bodyweight` on the
  added weight), most reps (rep types), longest duration (duration types).
  Warm-ups never count: a session of only warm-ups adds no history point and
  leaves "last time", which holds working sets only. A drop set's volume
  includes its drops, its other records use its first part. A record must be
  beaten, not equalled; an exercise's first workout sets its records but
  celebrates none.
- **Workout summary**: duration ("< 1 min" under a minute), volume (weight ×
  reps of the working sets of `weight_reps` and `weighted_bodyweight`;
  assistance is no load), working sets and exercises.
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
- **History**: Progress → Workout history lists finished workouts newest
  first, 20 per page, while its page is open. The first five pages are live
  listeners (cache first, so they work offline); older pages are read once.
  A page gets a fixed end (`endAtDocument`) once the page after it
  (`startAfterDocument`) loads, so pages never skip or repeat a workout.
  Rows carry no records mark: it would need every exercise's stats. The
  workout page names exercises from the catalogue (custom ones included),
  else by the name stored with the workout (retired and deleted ones); a
  program that no longer exists shows as deleted.
- **Editing workouts**: editing, deleting and adding a past workout store
  the workout in one batch, never changing `activeProgram`; a past workout
  has no program, and moving a program workout's start only moves the day
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
  history list.
- **Program progress**: doing another day of the active program shows it as
  done but leaves the schedule. Done days are read from workouts by date
  only, so no composite index is needed.
- **Calendar**: Progress → Calendar shows one month (previous / next;
  tapping a date of a neighbouring month opens that month), weeks starting
  on the locale's first day. It follows the month's dates plus six days on
  each side (every date its first and last week can show) live: workouts
  and cardio by local start date, a range on one field, so no composite
  index. A date is marked for a workout done, cardio done, a program day
  planned and a program day missed. Planned days come from
  `ProgramSchedule.plan`, the week plan's logic over any range: a program
  day done (a workout of the active program and that day, on that local
  date) shows only as its workout, and a day done twice on one date shows
  once, on the Programs tab too. A next day done on its date without the
  program moving on (it was not loaded at finishing) is done, not planned
  or missed, here and on the Programs tab, whose missed-day prompt knows
  only this week's done days. The missed next day shows on its date as
  missed (resolved on the Programs tab, not started here) and again where
  it is planned now. A planned day starts through `startProgramDay`, so a
  locked premium copy's days show but open the paywall. A workout opens
  its history page, a cardio session its page (which finds only the 500
  newest sessions). If the programs cannot be read, what was done still
  shows. `MonthGrid` (`lib/features/calendar/presentation/month_grid.dart`)
  is generic except for `CalendarDate`; move it to `forge_ui`, taking
  `DateTime` dates, when that package is next changed.
- **Starting a workout**: the Programs tab starts the next day, a program's
  page any of its days, the Today tab an empty workout until that tab is
  built, and an exercise's page adds it to the workout in progress or, after
  asking, starts one with it. A program day waits until the user's custom
  exercises are loaded; exercises really gone are left out and the user is
  told how many. Starting while a workout is in progress asks to resume it
  or discard it.
- **Add to program**: an exercise's page appends it, with the default
  targets, to a day of one of the user's programs through the program's
  validation; a full day cannot be picked, and without programs it offers to
  create one.
- **Swapping an exercise**: the same logging type keeps the sets, another
  gets as many empty ones; up to eight alternatives are offered before the
  whole library.
- **Save as program**: a free workout becomes a one-day program of the
  user's own: its working sets, the rep range done or the longest duration,
  the heaviest weight (least assistance) as target, the exercise's default
  rest (90 s for a custom one). Exercises no longer in the library are left
  out; a program that would not be valid (over 20 exercises) is refused.
- **Workout limits**: name 1-100 characters, note 1000, exercise note 500,
  set note 200, 40 exercises, 30 sets each, 5 drops per set. The rules
  validate the top-level fields of `workouts` and `exerciseStats` (allowed
  keys, types, sizes); the app checks sets before storing.
- **Rest timer**: ticking a set starts a rest of its program item's
  `restS`, else the exercise's `defaultRestS`, else the user's default
  (`settings.restTimer`: `enabled`, default on; `defaultS`, 90 s, 15-600;
  `notify`), which the workout cubit follows itself. A rest of 0 is none.
  In a superset or circuit rounds count working sets (warm-ups belong to
  no round, so a warm-up on one exercise shifts nothing), and only the
  group's last exercise with a working set in that round starts the rest,
  for the rest of the group's last exercise (as the program estimate
  counts it); the next set follows the same rounds, the group's warm-ups
  first. Warm-ups start none and leave a running one alone; a drop set
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
  "Rest over" for 3 s. +15 s moves the end; there is no −15 s.
- **Rest notification**: local, scheduled only when the app hides and
  cancelled when it shows or the rest changes, since the notifications
  package cannot hide one over the app in front; a schedule that lands
  after such a change is cancelled again. A rest left running when the
  app is killed in front gets none. The wish is the user's
  (`settings.restTimer.notify`, written only by their answer or the
  settings switch); the permission is the device's and is never written
  to Firestore. On a device not asked yet, the first rest the user starts
  asks in the app with one line, unless they said no or said yes and the
  device already allows it; the system is asked only after "Allow", never
  on its own. "Not now" is remembered on that device only (a marker file
  in app support), so other devices still ask; a device refusal leaves
  the wish, so devices that allow it still notify. "Allow" then asks, on
  Android, for exact alarms (without them the notification falls back to
  an inexact alarm, possibly late). The rest notification has id 1 on one
  Android channel, `workout` ("Workout", high importance).
- **Weekly volume**: Progress → Weekly volume shows one week, the current
  one first; earlier weeks are free to browse, later than the current one
  never. A week starts on the locale's first weekday
  (`MaterialLocalizations.firstDayOfWeekIndex`, `CalendarDate.startOfWeek`);
  with English as the only language that is Sunday, while the program
  week plan and the cardio chart keep Monday. A workout belongs to the
  week of the local date it started, like a program day, so a daylight
  saving change never moves it. Counting is the programs' own
  (`muscleSets` in `exercises/domain/muscle_volume.dart`) over done sets
  that are not warm-ups; an exercise's muscles are the library's current
  ones (custom exercises included), else, for a retired or deleted one,
  those stored with the workout. Each muscle is judged against 10-20 sets
  whatever the user's level: below, within (both ends inside) or above, in
  the theme's tertiary, primary and error colours on the model and the
  bars; a muscle with no sets keeps the body's colour. Tapping a muscle
  lists the exercises and workouts that gave it sets. The 12-week trend
  (the week shown and the 11 before it) is Premium, a locked row opening
  the paywall otherwise. Only Premium reads those 12 weeks (again when
  Premium comes or goes); everyone else reads the week alone. They are the
  user's own workouts, so the gate is client-side only. Changing week
  keeps the week before on screen until the next arrives, so the model
  keeps its camera. `WatchWeeklyVolume` with one week is what the Today
  tab's card will call.
- **Volume charts**: the band bars and the trend are small `CustomPainter`s
  of the volume feature, like the cardio chart; unify them with the app's
  line chart into one chart in `forge_ui` once both exist.

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
shows a card without a readable one without minutes), `equipmentProfile`
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
effortScale, restTimer, bar and plates, stepGoal, reminder times,
trackedMeasurements[], analyticsConsent), `favoriteExerciseIds[]`,
`activeProgram` (`programId`, `weekdays[]` ISO 1-7, `nextDayIndex`,
`nextDate` `YYYY-MM-DD`, `startedAt` device-clock timestamp).

**`users/{uid}/customExercises/{id}`**: `name`, `loggingType`,
`mainMuscles[]`, `secondaryMuscles[]`, `equipment[]`, `note`. Max 500.

**`users/{uid}/programs/{id}`**: `name`, `origin` (`own` \| `catalog` \|
`generated`), `sourceId?`, `lengthWeeks?` (1-52), `days[]` (1-7),
`premium?` (true on a copy of a premium ready-made program and on its
duplicates; see Decisions), `updatedAt`. Starting a catalog program copies it here, so later catalog
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
`history[]` (`date`, `workoutId`, `bestE1rmKg?`, `volumeKg`; one point per
workout). Rebuilt from that exercise's workouts whenever one is edited or
deleted.

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
- [x] Exercise domain and sync — incremental sync by `updatedAt` — library works offline after first sync
- [x] Admin panel — sign-in, exercise list, exercise editor with validation, draft/live/retire — an edit appears in the app after sync
- [ ] Exercise content — 400+ exercises in English, loaded through the admin import — every muscle and equipment profile is covered
- [x] Library — model tab with muscle sheet (main vs secondary), list, search, filters, sort — find any exercise in a few taps
- [x] Exercise detail — text sections, model with worked muscles, alternatives, variations, favorite, add to workout or program
- [x] Custom exercises — short form, edit, delete — shown with a "Custom" label everywhere

Group 4, programs
- [x] Program builder — days, exercise picker, sets and rep range, rest, supersets and circuits, reorder
- [x] My programs and schedule — start a program, pick weekdays, missed-day prompt (do today, move, skip)

Group 5, workout
- [x] Active workout — single list, set rows with last time and goal, set types, drop sets, failure, RIR/RPE, notes, swap, add, reorder, minimize bar, crash recovery
- [x] Free workout — start empty, save as program at the end
- [x] Rest timer — auto start, +15 s, skip, notification
- [ ] Rest timer on the lock screen — iOS Live Activity, Android ongoing notification
- [x] Finish and summary — records with a short celebration, `exerciseStats` update
- [x] History — list, workout detail, edit, delete, add a past workout; stats rebuilt

Group 6, progress
- [x] Calendar — month view of planned and done workouts and cardio
- [ ] Weekly volume — model coloring and bar list against the 10-20 band; 12-week trend (Premium)
- [ ] Strength — per-exercise records and e1RM chart (beyond 12 weeks Premium)
- [ ] Today tab — next workout and week strip, quick actions, volume card, steps card

Group 7, programs for everyone
- [x] Catalog — 25 ready-made programs (6 free), filters, detail, premium lock, admin program editor
- [x] Program generator (Premium) — questions (goal, level, days, session length, equipment, focus muscles, excluded exercises, area to go easy on, preferred split), preview, save as an editable program

Group 8, body and extras
- [ ] Weight log and measurement day — steps for weight, tracked measurements, four photos with ghost overlay, reminders, photo backup, compare
- [x] Cardio — log, list, detail, weekly chart
- [ ] Steps — health permission, today, week and 30-day chart, daily goal
- [x] Calculators — calories (Mifflin-St Jeor), body fat (US Navy), 1RM, plates, macros, BMI and FFMI

Group 9, launch readiness
- [x] Onboarding — nine questions, suggested free program
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
- RevenueCat webhook (`revenueCatWebhook`, needs the Blaze plan): verify the
  Authorization header secret, write `entitlements/{app_user_id}` with
  `premium`, `expiresAt` (a timestamp; lifetime products would need a far
  date, the rules compare it) and `productId` on every event, including
  TRANSFER (two uids) and EXPIRATION. Rules for `entitlements/{uid}` and the
  premium program detail are already in `firestore.rules`.
- Store setup once the accounts exist: products (monthly, yearly with a
  7-day trial) in App Store Connect and Play Console, one RevenueCat project
  with entitlement `premium` and a current offering, the In-App Purchase
  capability on the App ID, the .p8 key and Play service account in
  RevenueCat, server notifications to RevenueCat, license testers. Check that
  `com.android.vending.BILLING` is in the merged Android manifest on the
  first build. Android launchMode (`singleTop`), Kotlin 2.4 and compileSdk 36
  already meet the SDK's needs; iOS uses Swift Package Manager.
- The first Android build after the rest timer needs Android platform 37
  (compileSdk, for flutter_local_notifications 23) and AGP 9.1.1
  downloaded; the disk is nearly full, so free space first. CI does not
  build Android, so nothing has compiled the Android changes yet.
- Release blocker: the Terms of Use and Privacy Policy links in
  `lib/app/legal_links.dart` are placeholders; publish the pages and
  replace them.
- The admin web build now bundles and loads the RevenueCat web script,
  because `purchases_flutter` registers a web plugin. Harmless; revisit if
  the admin build is split from the app.
- `forge_purchases` has no "unavailable" backend; the app swaps in its own
  repository for release builds without keys. Move it into the package when
  it is next changed.
