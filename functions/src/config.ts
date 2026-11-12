/**
 * The one region every function is deployed to, next to Firestore's `eur3`.
 * The app calls callables in the same region
 * (`functionsRegion`, `lib/app/functions_region.dart`).
 */
export const REGION = "europe-west1";
