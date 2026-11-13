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
  same mesh names is required before release; the user supplies it. The
  exercise page shows it twice, front and back side by side with the worked
  muscles coloured, both fixed (`interactive: false`, the back through a
  camera at yaw π) so the page scrolls over them; two CPU-rendered viewers
  share one parsed model and paint once. The Exercises tab's model stays
  interactive.
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
- **Programs**: a name of 1-60 characters, 1-7 days, day names of at most
  40 characters, 1-20 exercises per day, an optional length of 1-52 weeks;
  lengths count UTF-16 code units in the fields and in validation. The
  Firestore rules validate the top-level fields only (`name`, `days` count,
  `origin`); the app validates days and items. Items whose exercise's
  logging type changed are fitted to the new type when the builder loads
  them, and the user is told. The Programs tab opens with three rows, the
  same with or without programs: ready-made programs, the generator and
  "New program" (the builder); no floating button. In the builder, Add
  day selects the new day and focuses its name; opening the builder or
  switching days never takes the focus.
- **Schedule**: `activeProgram.nextDate` is a calendar date stored as a
  `YYYY-MM-DD` string, so it is the same date in every time zone, and
  `startedAt` is a device-clock timestamp because starting a program must
  work offline. A missed next day stays the next day until the user does
  it today, moves it to the next training weekday or skips it; the week
  plan shows it once, on its date. A program with a length ends that many
  weeks after its start date.
- **Effort scale**: optional per set, picked in the set bar (picking the
  chosen step again clears it). Settings → "Effort per set": By feel
  (default), RIR or RPE; there is no "Off" (`settings.effortScale` codes
  `feel`, `rir`, `rpe`; the older `off` reads as by feel). Every scale is
  stored the same way, as RIR (`rpe = 10 - rir`): by feel Easy ("4+ reps
  left") stores 4, Moderate ("2–3 left") 2, Hard ("1 left") 1, Max ("0
  left") 0, and a stored RIR shows as Easy from 4, Moderate at 2-3, Hard at
  1, Max at 0. Every scale ends with "Failed" (the last rep was attempted
  and not completed), stored as `toFailure` with RIR 0; there is no separate
  failure switch, and any set with `toFailure` shows Failed whatever its
  RIR. Effort shows in the chosen scale everywhere (bar, workout detail).
  Effort is only stored and shown (bar, workout detail); nothing else uses
  it yet, and the help says just that. Effort is only asked about a DONE
  working set; warm-ups are never rated. Right after a working set is
  ticked in the workout in progress it is asked in one of two places:
  - **Its tick started a rest** (`restStartedBy`, `askingWithRest`): in
    the rest strip, under the countdown with +15 s and Skip, one line
    naming the set with its values and the scale's short question ("Set 1
    · 80 kg × 8 — how hard?", "… — reps left?", "… — RPE?", the exercise
    first when the selection is on another one), the "?" help and the
    steps with Failed; no Skip of its own. The set bar meanwhile shows the
    next set as usual, so its weight can be set during the rest. It lasts
    as long as that rest (`restQuestionSet`: the rest still that set's and
    running, so "+15 s" extends it): gone when the rest runs out or is
    skipped, when a step is picked (stored on that set; the countdown
    stays), another set is ticked (its own question replaces it), the set
    is unticked, removed or moved, or the workout finishes. Picking
    another set or opening an exercise leaves it. Opening the help changes
    nothing; a rest ending meanwhile leaves the sheet open and the
    question gone. The strip, and so the question, steps aside while the
    keyboard is up.
  - **It started none** (rest timer off, a set mid-round in a superset):
    the set bar becomes the question (`questionSet`): "Set 1 done · 80 kg
    × 8" ("Drop set 2 done · …", the exercise first when the selection
    moved on: "Squat · Set 3 done · 100 kg × 5"), the scale's question
    ("How hard was it?", "How many more reps could you have done?", "How
    hard was it, from 1 to 10?") with the "?" help, the steps with Failed,
    and Skip; no fields and no tick, the keyboard already closed by the
    tick. The bar returns to the next set when a step is picked, Skip is
    tapped, any set is picked or an exercise opened, an edit moves sets,
    or after `WorkoutEditor.effortQuestionTime` (20 s) untouched; any
    touch restarts that time and it waits while the help is open.
  Neither shows while edits are refused (finishing), and an answer refused
  then leaves it open. Editing a past workout never asks on a tick. A
  selected done set shows its effort row under its values, named: "Set 1 ·
  how hard was it?" (`effortRowSet`); an undone set never has one.
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
    it in the workout has the same main muscle (the first of its
    `mainMuscles`, the 19 muscle groups of the vocabulary; one without any
    is a group of its own). Decided as it enters the workout (a program
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
  flipped in such a version is not seen by this one. Malformed custom sets
  are dropped or clamped; Custom without sets reads as Standard.
  Exercises logged with a weight and reps (`weight_reps` only: weighted
  and assisted bodyweight, reps-only and timed exercises get none) start
  with one empty warm-up per set of the scheme before their working sets
  when they enter a workout in progress: a program day started, an
  exercise added (also to an empty workout, and "start with this
  exercise"), or swapped in while none of its sets is done (the selection
  then opens its first warm-up). Swapped for an exercise that takes none,
  its untouched warm-ups (nothing entered, not done) go
  (`withoutUnusedWarmups`). The scheme and the unit are the user's own
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
- **First-use tips**: three inline banners (Material `MaterialBanner`,
  never modal), each with "Got it", none until the user's settings have
  arrived: effort, inside the effort question the first time, in the
  rest strip or the bar (under the steps, so the countdown, Skip and the
  steps stay in view), until it is dismissed, an effort is picked or the
  question skipped; set types, at the top of the add-set sheet, until a
  type is picked there; automatic warm-ups, at the top of the workout in
  progress once warm-ups were added to it automatically
  (`warmupsAdded`), until the setting is changed. Dismissing or using the
  thing marks it seen for good, in `settings.seenTips` (codes `effort`,
  `setTypes`, `autoWarmups`; the app has no local flag store, and this
  follows the user across devices). Tips are only ever added to that list,
  field by field (`arrayUnion`), never written with the other settings, so
  two devices and codes from newer versions are kept. Which tip is due is
  pure logic (`workout_tips.dart`).
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
  from onboarding to an account already onboarded, and skipping onboarding
  ("Skip for now"), which suggests nothing.
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
- **Steps**: read-only from Apple Health / Health Connect through
  `forge_health`; never stored, so `firestore.rules` is unchanged. The
  platform store in every build on iOS and Android; the fake only in debug
  and profile builds on other platforms. The Steps page (Progress tab)
  reads the last 30 days in one call and derives today and the week (the
  locale's first weekday) from it; it reloads on app resume and on pull,
  never by polling. Access: unless already granted, a one-screen
  explanation comes first and the system is asked only after "Continue";
  that the user was asked is remembered on the device (a marker file in
  app support), because HealthKit never says. Android refusal shows "Open
  Health Connect" and "Ask again"; a missing Health Connect offers its
  store page. On iOS a month of zeros shows a hint to allow access in
  Settings, never a denial. A failed request shows on the explanation or
  refusal screen; a failed refresh keeps the steps and says so. The goal is `settings.stepGoal`, 10,000 by
  default, 1,000-50,000 in steps of 500, edited on the page through
  `SettingsCubit`. `GetTodaySteps` (today vs goal) is registered for the
  Today card. Both charts are `BarChart`s with the goal as a line. The
  steps domain imports `forge_health` whole, platform code included; once
  the package exposes a domain-only library (next forge tag), import that
  instead.
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
- **Weight log and measurement days** (`lib/features/body`): Progress →
  Weight and measurements. A quick log is an entry with only `weightKg`
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
- **Body fat** (derived, never stored): US Navy, through the calculators'
  `estimateBodyFat`, from an entry's measurements and the profile's sex
  and height (`entryBodyFat` in `lib/features/body/domain`). Sites: the
  waist is measured at its narrowest and the abdomen at the navel, so men
  need `neck` + `abdomen`, women `neck` + `waist` + `hips`. An entry
  without them, or with values the formula rejects, simply shows none.
  Shown on the Weight and measurements page as a trend chart under the
  weight chart (same range picker and 12-weeks-free rule; only once some
  entry has one), in each history row, on the entry and as a change in
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
  The weight chart is a `LineChart` with the strength ranges: 12 weeks
  free, longer Premium (confirmed by the user); the profile's
  target weight shows with the distance to go. Comparing is the
  measurement summary (below). Saving or deleting an entry sets `profile.weightKg` to
  the weight of the most recent dated entry that has one, through the
  profile's `UpdateProfile` (calculators and the target distance use it);
  with no such entry the profile weight is left. Firestore rules validate
  `bodyEntries` (date timestamp, numeric `weightKg`, `measurements` and
  `photos` maps whose known keys hold numbers and strings).
- **Measurement summary** (`lib/features/body`, planned with the owner):
  one screen, `MeasurementSummaryPage`, titled "Measurement summary" at
  `/progress/body/summary/:id` (opened in place of the flow right after a
  new measurement day is saved; never after an edit) and "Compare" at
  `/progress/body/:id/compare` (a measurement day's page, when it has an
  earlier one, and Progress → "Compare measurement days", the newest
  measurement day, off with "Needs two measurement days" until there are
  two). The app-bar compare icon and the old compare page are gone; no
  sharing or export. A measurement day is an entry with measurements or
  photos (quick weight logs are not, as for the reminders). The baseline
  is one of the measurement days dated before the entry: the previous
  one by default, "First" (the oldest) or any of them from a list ("Other
  date"); the chips show only with two or more. A chosen day that is
  deleted or moves after the entry falls back to the previous day. Order:
  the dates; body fat, fat mass and lean mass (from each day's own
  weight; fat and lean mass need the later day's weight) with changes,
  or one line on what is missing (sex/height with a link to the profile,
  the measurements, or values the formula rejects); every value either
  day has (weight, measurements, pairs on one row, a missing side a dash)
  before → after with the difference, differences in the primary colour
  whatever their sign; the target (hidden without a target weight or a
  weight that day): distance, and an estimated date at the rate between
  the two days, given only when the target is not reached (within
  0.05 kg), the earlier day has a weight, the days are at least 7 days
  apart, the weight moved toward the target, and the date is between now
  and 2 years from now; then the photos of one pose (chips of the poses
  either day has) on a before/after slider, the earlier left of a bar the
  user drags, both photos filling the same 3:4 area (cover), a missing
  one as a note on its half; photos of the shown pose are fetched from
  the backup when missing. Without an earlier measurement day the same
  screen shows the day alone: its date with "No earlier measurement day
  to compare with yet.", values without before or change ("Values"),
  body fat without change, the target without an estimate, and the
  photo of the pose without a slider. The domain model
  (`MeasurementSummary`, `measurement_summary.dart`) does every number;
  `FindBaseline` picks the baseline; `MeasurementSummaryCubit` follows the
  entries and the profile itself. The slider is `forge_ui`'s
  `BeforeAfterSlider`.
- **Privacy**: minimal set. In-app account deletion, privacy policy link,
  consent for analytics and crash reports. No age gate, health notice or data
  export (the user accepted the EU risk).
- **Analytics consent** (`lib/features/account`):
  `settings.analyticsConsent` of each user, guests included (a guest has a
  uid and a user document; linking keeps it, signing in to an existing
  account takes that account's answer). Consent is per user, never per
  device. Null is not answered, which collects nothing. Analytics and
  Crashlytics start off natively (Info.plist, AndroidManifest.xml) and
  collect only in prod release builds, for the signed-in user, after their
  yes; never the advertising ID, Android ID or IDFV, and no ad
  personalisation signals (the `AD_ID` permission is removed). At start,
  collection is what the last applied answer left (the SDKs keep it), or
  the native default (off) on a fresh install; `forge_firebase`'s
  `initFirebase` does not change it, and `FirebaseTelemetry.restore` then
  applies the answer the user signed in at launch last gave on this device
  (one file per uid in app support). Whenever the signed-in user changes
  or is unknown, collection goes off until that user's stored answer is
  read, and stays off when the read fails. `ConsentCubit` (app-wide)
  applies each answer as it arrives; changes run one at a time and the
  latest wins. A yes first deletes the crash reports recorded before it
  and is saved last, so a failure never leaves a saved yes. Asked once the
  server (not a cached copy, which may predate an answer from another
  device) says there is no answer and the same user's profile is past
  onboarding (never while a new user's profile loads in the tabs after
  signing out, deleting the account or switching accounts), in a dialog
  over the tabs only while they are the top route (never over onboarding,
  the workout, the paywall or another dialog), with two equal choices and
  no dismissing. While an account is being deleted (`DeletionUnderway`)
  its consent is not followed, so the deleted document neither asks nor
  records an answer; a deletion that failed follows it again. Changed
  with the switch under Profile → Privacy. The settings feature leaves the
  field alone: its writes merge, and `UserSettings` does not carry it.
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
  for the password (`forge_auth`'s `Reauthenticate`) and tries again. A
  user without a password (Google only) is still asked for one once;
  `Reauthenticate` then fails with `noPasswordCode` and the app tells them
  to sign in again, which renews the sign-in. Skipping the dialog for them
  needs the sign-in methods on `AuthUser` (forge task). A guest is deleted
  the same way, without that check. Once the server deleted the data,
  still signed in (so nothing of the next guest is touched), the app
  removes the user's kept workouts file (unreadable copies too), cancels
  every scheduled notification, records no consent for them and resets the
  analytics id and unsent crash reports, and marks Firestore's offline
  copy, which is cleared (`clearPersistence`) at the next start before
  Firestore is used; then it signs out and a new guest starts at
  onboarding. A local leftover is logged, not reported. If only the
  sign-in is left (the function's `details.reason` says so) the user stays
  held on the page, which offers only "Try again". A function not deployed
  or not callable answers `not-found` / `permission-denied`, shown as
  "deleting accounts isn't available yet", never as done; anything else
  that failed before the data went gives the workout back.
- **Cloud Functions** (`functions/`): TypeScript, Node 22, 2nd gen, all in
  `europe-west1` (`src/config.ts`, set once with `setGlobalOptions`; the
  app's one Dart constant `functionsRegion` in
  `lib/app/functions_region.dart`, used by the app and the admin panel,
  must match). One file per
  function, exported from `src/index.ts`; logic takes its Admin SDK
  access as a parameter so `npm test` (lint, build, `node --test`) runs
  without an emulator; CI runs it. Deploying is the Architect's step
  (`firebase deploy --only functions --project <id>`), never an agent's.
- **Onboarding questions**: goal, level, days per week and equipment need
  an answer to continue. The personal questions (sex, birth year, height,
  weight, target weight) can each be skipped with "Skip this question";
  "Skip for now" still ends onboarding with whatever was answered, and
  lands on Today with no program suggested (the skip is remembered in
  memory only; a later start with a completed profile never suggests).
  "I already have an account" shows on the first question for a guest
  only: once signed in to an account (also a guest just linked to one) it
  is gone.
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
  Permission: turning a reminder on asks in the app with one line first
  (unless the device already allows), then the system; a refusal shows a
  dialog with "Open settings" (the app's notification settings), and the
  reminder is stored on anyway, like the rest notification's wish; while
  a reminder is on and the device refuses, the settings say so with "Open
  settings". All notifications share the Android channel `workout`,
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
- **Navigation**: five tabs, Today / Programs / Exercises (center, the model)
  / Progress / Profile. The active workout is full-screen and can be minimized
  to a bar above the tabs. A `go` (a link, a notification tap) replaces
  its tab's stack; a page there with unsaved changes (program builder,
  workout edit, measurement day) is never dropped silently. One router
  guard (`onEnter`, `lib/core/unsaved_changes.dart`) brings that page up
  (its tab, the workout or paywall above the tabs put away, the workout
  staying in its bar) and asks with the page's own discard prompt: keep
  editing stays there, discard makes the navigation again. Pages without
  changes (an edit left as it opened, a page that saved), other tabs'
  stacks, pushes and tab switches are left alone. Back and the guard share
  one prompt per page, so nothing asks twice.
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
  added. Effort is a whole number: RIR 0-5 (5 means 5+) or RPE 10-5, see
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
  Each time the workout page opens (from the minimized bar, Today's
  "Resume workout", a lock-screen or notification tap, or a relaunch, when
  nothing is kept anyway) the pick is forgotten, so the exercise with the
  next set to do is open on that set (`pageOpened`, called as the page is
  built anew); pages opened above it (the exercise picker or details, the
  sheets, the paywall) and closed leave it exactly as it was, as the page
  is not built anew. An effort question left in the bar (its tick started
  no rest) is dropped then too; one in the rest strip stays while its rest
  runs, as the minimized bar shows that rest. The edit page is unaffected.
  The open card shows its sets as **bubbles** (the owner's pick; the
  "selected set only" view was tried and deleted): a wrapping row of round
  bubbles, a warm-up dashed with "W", a drop set "2D", done ones ticked, the
  selected one in the theme's selected colours, a "+" bubble; a group
  stacks one row per exercise, labelled A1, A2, warm-ups first, then one
  column per round with the round's bubbles joined. Tapping a bubble
  selects its set; long-pressing it opens a menu at the bubble with "Change
  to …" for the other set types it can be and "Remove set" (also custom
  screen-reader actions), the same as the bar's "more" sheet. Adding a set
  asks Normal / Warm-up / Drop set (a drop set only for rep-based
  exercises); a warm-up goes after the existing warm-ups, other sets at the
  end, all empty with the usual suggestions as hints. Changing a set's type
  keeps warm-ups first: a set made a warm-up moves to after the other
  warm-ups, a warm-up made a working set becomes the first working set,
  normal and drop sets stay in place (`retypedSetPosition`); the selection
  follows the moved set, and a running rest forgets the set it followed as
  for any move. The **set bar** sits at the bottom of the page above the rest
  strip and the safe area; while the keyboard is up the rest strip steps
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
  `/progress/history/exercises/:id` above the edit page), so back returns
  to the workout as it was.
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
- **Strength**: Progress → Strength lists the exercises with stats (the
  whole `exerciseStats` collection, live), most recently trained first
  (`last.date`, else the latest history point), searched by catalogue name,
  custom exercises included; it stays loading until every exercise is
  named or known to be gone (one no longer in the library shows as
  removed, since stats keep no name). If that collection read grows too
  costly, the fix is a small last-trained index written in the same batch
  as the stats. An exercise's page is also opened by "Records and
  progress" on the exercise page, above it in whichever tab shows it, so
  Back returns to the exercise. It lists the records (heaviest weight,
  best e1RM, most reps, best set volume, longest time), each opening the
  workout that set it, and charts each workout's best e1RM in the user's
  unit, on an axis of whole kg or lb at least four units tall; an exercise
  that never had an e1RM (bodyweight, timed) shows its records only.
  Ranges: 12 weeks free; 6 months, 1 year and all Premium; a range starts
  at local midnight of the same day that many months back, or that
  month's last day when it is shorter. Records are all-time and free (the
  workout summary shows them too); only the chart beyond 12 weeks is
  Premium, and a free user with older results is told so and offered the
  paywall. The gate is client-side: one stats document holds the whole
  history, so the rules cannot withhold old points without splitting it,
  and no server refusal can occur here.
- **Charts**: `lib/core/line_chart.dart` is a small `CustomPainter` line
  chart (points and formatters only; scaling and ticks are the pure
  functions of `lib/core/chart_geometry.dart`), since neither the app nor
  `forge_ui` has a chart and no chart package is added. Move both to
  `forge_ui` when that package next changes.
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
- **Starting a workout**: the Programs and Today tabs start the next day,
  a program's page any of its days, the Today tab also a free workout,
  and an exercise's page adds it to the workout in progress or, after
  asking, starts one with it. A program day waits until the user's custom
  exercises are loaded; exercises really gone are left out and the user is
  told how many. Starting while a workout is in progress asks to resume it
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
  while the app runs; its texts come from the app. Lock screen and Dynamic
  Island (compact, minimal, expanded) show the same two modes: the
  workout (dumbbell, name, elapsed time counted up by the system, the set
  to do now) or the rest (timer, "Rest", countdown, the next set). No push
  updates (no APNs yet), so the app cannot change it while suspended: the
  content state carries the rest with its end, the activity's stale date
  is that end, and the widget draws the rest only while it is not stale
  and its end is ahead, so at the end the system redraws it as the workout
  by itself; the app replaces it with the workout once it runs again.
  Outside a rest it has no stale date. iOS ends an activity after 8 h
  (kept on the lock screen up to 4 h more); the next update the app makes
  in front then starts a new one, as it does after the user swiped it
  away. Users can turn Live Activities off per app; then nothing shows.
  A tap on it (lock screen and every Dynamic Island presentation, in both
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
  tab's card calls.
- **Charts**: `LineChart` (trends, e.g. e1RM) and `BarChart` (zero-based
  daily or weekly values with an optional target line, e.g. steps) live in
  `lib/core` and share `ChartText` and the pure geometry in
  `chart_geometry.dart`. When `forge_ui` next changes they move there
  together; `BarChart` then gains an optional band and per-bar colours,
  and the volume trend (`VolumeTrendChart` and its painter) is replaced
  by it and deleted. The volume band bars and the cardio chart stay
  feature widgets until then.
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
  from settings as before. 1RM and the macros' calories stay empty (no
  single source); the goal and target weight map onto no calculator
  input. A known number shows as a tile (`KnownNumberField`), not a field:
  its name, the value to one decimal in the user's unit and, for a value
  from the body log, "Measured <date>" (the entry's date; body fat takes
  the oldest of its circumferences'; the year only when not this one).
  Profile values (height, age, a profile-only weight) have no date.
  The tile has an edit icon; tapping it turns it into the normal field,
  focused, holding the value; it stays a field (the cubit's `known` map
  drops it). Focusing a field before the values arrive counts as editing
  it, so a late value never replaces it. Both the waist and the abdomen
  are known; the body fat calculator shows the one for the selected sex
  (abdomen for men, waist for women), or an empty field, unless the user
  typed or started editing it. Sex and activity stay selectors: they
  already show the known choice. They are
  starting values only: nothing is written back. They load once when a
  calculator opens; a value arriving late fills only inputs the user has
  not changed (even one they cleared stays empty). A source that cannot
  be read adds nothing.
- **Today tab** (`lib/features/today`): a scrolling list of independent
  cards, each on its own data, so one failing leaves the others. Next
  workout: while a workout is in progress (`ActiveWorkoutState.inProgress`,
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
  `startProgramDay`. A missed day shows the Programs tab's
  `MissedDayPrompt`, only while the program is open, as there; a failed
  choice is reported by the prompt that made it, so the two tabs never
  both do, and a write the server refuses later by the one
  `ProgramWritesNotice` in the shell, whichever tab is open. While the
  premium status of a premium copy is unknown the card shows only its
  title, as the Programs tab waits, so a missed day never shows as a
  planned one with Start. A locked premium copy shows its day, locked,
  with Start opening the paywall. Without a program, or once it finished: the
  catalogue, the generator and "Start empty workout" (the app never calls
  it "free": users read that as "at no cost"). Week strip: the
  calendar's `calendarEntries` and marks over the current week from the
  locale's first weekday (Sunday in English, like weekly volume, unlike
  the program week plan), drawn by `MonthGrid` as one week; the strip and
  every day open the calendar, which has no route for a given date. Quick
  actions: a free workout, log cardio, add a past workout, the
  calculators (a row, not a card listing all six, which would crowd the
  tab; it opens the list under Profile, which keeps its own row). Volume
  card: `WatchWeeklyVolume` with one week, never the trend, whatever the
  user's premium: the trained muscles counted in, below and above the
  band and the three most trained as band bars; it opens Weekly volume,
  and has no model. Steps card: `GetTodaySteps` against
  `settings.stepGoal` (read again when the goal changes), opening the
  Steps page. Today only checks access and never asks the system: not
  asked here yet, refused or Health Connect missing show one line, "See
  your steps", that opens the Steps page to set it up; a device without a
  health store shows no card. Cards show only their title while loading
  (the cache answers at once; no spinner on the home tab); cubits move to
  the new day and week when the app resumes, and the week strip also when
  a snapshot arrives after the week ended; steps are read again on
  resume.

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
effortScale, restTimer, warmups (autoWarmups for older versions), seenTips[],
bar and plates, stepGoal,
reminder times,
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
upper arm, forearm, thigh, calf; body fat is derived from them and the
profile, never stored), `photos` (map of `front` \| `right` \|
`left` \| `back` → storage path, which holds the photo's revision; see
Storage). A quick weight log is an entry with only `weightKg`; a
measurement day fills all three.

**`users/{uid}/pushTokens/{token}`**: `platform`, `updatedAt`.

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
  programs, workouts, exerciseStats, cardio, bodyEntries, pushTokens and any
  added later) by recursive delete, `entitlements/{uid}`, Storage
  `users/{uid}/` (photos; a project without a default bucket has none,
  logged), then the auth user last, so a partial failure can be retried;
  every step succeeds when nothing is left. Refusals carry a
  machine-readable `details.reason`, which the app maps on: `recent-sign-in`
  (`failed-precondition`, a non-guest signed in more than 5 minutes ago)
  and `sign-in-not-deleted` (`internal`, the data is gone but the auth user
  is not; calling again finishes). Once the auth user is gone it deletes
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
- [x] My programs and schedule — start a program, pick weekdays, missed-day prompt (do today, move, skip)

Group 5, workout
- [x] Active workout — single list, set rows with last time and goal, set types, drop sets, failure, RIR/RPE, notes, swap, add, reorder, minimize bar, crash recovery
- [x] Workout screen redesign — one exercise open at a time, set bar, set bubbles (long-press for type and removal), exercise cards reordered by holding a header, effort by feel / RIR / RPE with Failed, exercise details from the workout, add set by kind
- [x] Free workout — start empty (not in progress until an exercise is added), save as program at the end
- [x] Rest timer — auto start, +15 s, skip, notification
- [x] Rest timer on the lock screen — iOS Live Activity, Android ongoing notification
- [ ] Workout on the lock screen — iOS Live Activity and Android ongoing notifications for the whole workout (workout and rest modes, tap opens it)
- [x] Finish and summary — records with a short celebration, `exerciseStats` update
- [x] History — list, workout detail, edit, delete, add a past workout; stats rebuilt

Group 6, progress
- [x] Calendar — month view of planned and done workouts and cardio
- [x] Weekly volume — model coloring and bar list against the 10-20 band; 12-week trend (Premium)
- [x] Strength — per-exercise records and e1RM chart (beyond 12 weeks Premium)
- [x] Today tab — next workout and week strip, quick actions, volume card, steps card

Group 7, programs for everyone
- [x] Catalog — 25 ready-made programs (6 free), filters, detail, premium lock, admin program editor
- [x] Program generator (Premium) — questions (goal, level, days, session length, equipment, focus muscles, excluded exercises, area to go easy on, preferred split), preview, save as an editable program

Group 8, body and extras
- [x] Weight log and measurement day — steps for weight, tracked measurements, four photos with ghost overlay, reminders, photo backup, compare
- [x] Cardio — log, list, detail, weekly chart
- [x] Steps — health permission, today, week and 30-day chart, daily goal
- [x] Calculators — calories (Mifflin-St Jeor), body fat (US Navy), 1RM, plates, macros, BMI and FFMI
- [ ] Measurement summary — one summary/compare screen (baseline choice, body fat and lean mass, changes, target estimate, photo slider), opened after saving a measurement day, from a day's page and from Progress; where-to-measure hints; body-fat box unticks; one waist mapping for body fat and calculators

Group 9, launch readiness
- [x] Onboarding — nine questions, suggested free program
- [x] Notifications — workout and measurement reminders, FCM announcements
- [ ] Subscription — paywall, RevenueCat, entitlement checks, restore
- [x] Account — delete account, privacy policy link, analytics consent

## Design

<!-- Filled in the design phase, after every feature is ticked. -->

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
- Apple sign-in is enabled in Firebase but not offered: it needs the Sign
  in with Apple entitlement, which only a paid Apple Developer team can
  sign (the free personal team cannot), and on Android an Apple Services
  ID. The App Store requires it wherever Google is offered, so it must be
  added before the iOS release.
- A guest who signs in to an existing account leaves an orphaned anonymous user and its data behind; clean these up with a scheduled function when Cloud Functions arrive.
- Photo backup: `storage.rules` and the `storage` entry in `firebase.json`
  are written but not deployed, and the default bucket is not created yet
  (both projects). `deleteAccount` already deletes `users/{uid}/` in the
  bucket; the orphaned-guest cleanup must do the same.
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
- The projects are on the Blaze plan. `deleteAccount` is written but not
  deployed: the Architect deploys `functions/` to dev, checks deletion on a
  device (including the "not available" message before the deploy), then
  prod.
- Female body model with the same mesh names: the user supplies it before release.
- `revenueCatWebhook` is written and unit-tested, not deployed or tried
  against RevenueCat. Deploying all of `functions/` needs its secret: an
  interactive `firebase deploy` prompts for a missing one, a
  non-interactive deploy (CI, an agent) fails. Until step 1 is done,
  deploy the others by name (`--only
  functions:deleteAccount,functions:sendAnnouncement`), or do step 1 early
  (with a random value nothing is accepted until RevenueCat has it). Once
  the RevenueCat project exists, per Firebase project (dev first):
  1. Make a random value (`openssl rand -hex 32`) and set the secret to the
     exact header value: `firebase functions:secrets:set
     REVENUECAT_WEBHOOK_AUTHORIZATION --project <id>` (e.g. `Bearer
     <value>`; dev and prod get different values).
  2. Deploy `functions/` (the Architect).
  3. In RevenueCat, Integrations → Webhooks, one webhook per project: URL
     `https://europe-west1-<project-id>.cloudfunctions.net/revenueCatWebhook`
     (2nd gen also has a `run.app` URL; either works), the same
     Authorization header value; dev: Sandbox; prod: both Production and
     Sandbox (App Review and TestFlight buy in the sandbox against prod);
     all apps, all events.
  4. Send the dashboard's test event (answers `test-event`), then a sandbox
     purchase with a debug build on dev: `entitlements/<uid>` appears and a
     premium program's days open; cancel and wait for EXPIRATION.
  Check then whether RevenueCat sends the header verbatim and
  `Content-Type: application/json` (the docs say neither; anything else is
  answered 401/415 and shows in the delivery log).
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
- Lock-screen rest, not built yet: the `RestTimer` widget extension
  target (hand-added to `project.pbxproj`; bundle id
  `com.getworkout.app.RestTimer`, iOS 16.2, embedded before Thin Binary),
  `NSSupportsLiveActivities`, ActivityKit weak-linked in the Runner, and
  `POST_PROMOTED_NOTIFICATIONS` on Android. A device build needs the
  extension's App ID under the team (automatic signing); untestable until
  the Apple Developer account: behaviour on a real device while
  suspended.
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
  presentation without squeezing the labels. An activity started by an older build (`RestActivityAttributes`)
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
- Release blocker: the Terms of Use and Privacy Policy links in
  `lib/app/legal_links.dart` are placeholders; publish the pages and
  replace them (Android picks up `privacyUrl` by itself).
- Release blockers for steps: Health Connect's privacy-policy link opens
  `PrivacyPolicyActivity`, which opens `LegalLinks.privacyUrl` (passed in
  by the build, still a placeholder); Play Console
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
  `revenueCatWebhook` under a placeholder secret, and the rules) and was
  run end to end on the Android emulator: a non-admin is refused, an admin
  send arrives on channel `workout`, the same request id is not sent twice,
  the record reads `sent`, and tapping it from the background opens Today.
  Still open: the admin panel's Announcements page has not been opened in a
  browser (the function was called directly), and prod has none of the
  functions or the newer Firestore rules. iOS push still needs the Apple
  Developer account: the Push Notifications capability (`aps-environment`
  in `Runner.entitlements`, not added yet, as it breaks device signing
  without it) and an APNs key uploaded to both Firebase projects. Until
  then iOS follows no topic.
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
  - `forge_auth`: the user's sign-in methods on `AuthUser`, so account
    deletion asks only a user with a password for it and tells a Google
    or Apple only user to sign in again straight away.
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
