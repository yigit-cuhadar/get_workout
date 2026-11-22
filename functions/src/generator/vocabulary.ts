// The codes the generator works with (SPEC.md, "Vocabulary"). A Dart test
// (`test/tool/generator_vocabulary_test.dart`) holds each list equal to the
// app's `vocabulary.dart`.

export const GOALS = [
  "build_muscle",
  "get_stronger",
  "lose_fat",
  "general_fitness",
] as const;

export const LEVELS = ["beginner", "intermediate", "advanced"] as const;

export const MUSCLES = [
  "pec",
  "lat",
  "trap",
  "front_delt",
  "mid_delt",
  "rear_delt",
  "biceps",
  "triceps",
  "forearm",
  "abdominal",
  "oblique",
  "erector",
  "glute",
  "abductor",
  "adductor",
  "quads",
  "hamstring",
  "calf",
] as const;

export const EQUIPMENT = [
  "barbell",
  "ez_bar",
  "trap_bar",
  "dumbbell",
  "kettlebell",
  "plate",
  "cable",
  "machine",
  "smith_machine",
  "bench",
  "box",
  "back_extension_bench",
  "pull_up_bar",
  "dip_station",
  "resistance_band",
  "suspension_trainer",
  "rings",
  "medicine_ball",
  "stability_ball",
  "ab_wheel",
  "landmine",
  "sled",
  "jump_rope",
  "bodyweight",
  "other",
] as const;

export const MOVEMENT_PATTERNS = [
  "squat",
  "hinge",
  "lunge",
  "horizontal_push",
  "vertical_push",
  "horizontal_pull",
  "vertical_pull",
  "carry",
  "core_flexion",
  "core_stability",
  "rotation",
  "explosive",
  "isolation",
  "mobility",
] as const;

export const MECHANICS = ["compound", "isolation"] as const;

export const GENERATOR_TIERS = [
  "staple",
  "standard",
  "fallback",
  "never",
] as const;

export const SENSITIVE_AREAS = [
  "shoulders",
  "elbows_wrists",
  "lower_back",
  "hips",
  "knees",
] as const;

export const FOCUS_AREAS = [
  "chest",
  "back",
  "shoulders",
  "arms",
  "core",
  "glutes",
  "legs",
] as const;

export const EQUIPMENT_STYLES = ["any", "machines", "free_weights"] as const;

/**
 * The app's equipment presets (`EquipmentProfile`), by code. Like the app's,
 * they never list bodyweight, which every user has.
 */
export const EQUIPMENT_PRESETS: { [preset: string]: readonly string[] } = {
  full_gym: [
    "barbell",
    "ez_bar",
    "trap_bar",
    "dumbbell",
    "kettlebell",
    "plate",
    "cable",
    "machine",
    "smith_machine",
    "bench",
    "box",
    "back_extension_bench",
    "pull_up_bar",
    "dip_station",
    "resistance_band",
    "suspension_trainer",
    "rings",
    "medicine_ball",
    "stability_ball",
    "ab_wheel",
    "landmine",
    "sled",
    "jump_rope",
    "other",
  ],
  home_gym: ["barbell", "plate", "dumbbell", "bench", "pull_up_bar"],
  dumbbells: ["dumbbell", "bench"],
  bodyweight: ["pull_up_bar", "dip_station"],
  bands: ["resistance_band"],
};

export const SLOT_ROLES = ["primary", "secondary", "accessory", "core"] as const;

/** Logging types whose sets are held for a time. */
export const TIMED_LOGGING_TYPES = ["duration", "weight_duration"] as const;

/** Logging types whose sets have no load to make low reps heavy. */
export const UNLOADED_LOGGING_TYPES = ["reps"] as const;

export type Goal = (typeof GOALS)[number];
export type Level = (typeof LEVELS)[number];
export type SlotRole = (typeof SLOT_ROLES)[number];
export type EquipmentStyle = (typeof EQUIPMENT_STYLES)[number];

/** The days per week onboarding offers (`ProfileLimits`). */
export const MIN_DAYS = 2;
export const MAX_DAYS = 6;
