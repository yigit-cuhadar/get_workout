import { onCall } from "firebase-functions/v2/https";

import { liveGenerateDeps } from "./generation";
import { checkRules } from "./store";

/** The problems of unpublished rules and what they generate. Admins only. */
export const generatorRulesCheck = onCall((request) =>
  checkRules(request.auth, request.data, liveGenerateDeps()),
);
