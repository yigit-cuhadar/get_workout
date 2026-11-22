import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";

import { firestoreRulesStore, getRules } from "./store";

/** The current generator rules, or one version of them. Admins only. */
export const generatorRulesGet = onCall((request) =>
  getRules(request.auth, request.data, firestoreRulesStore(getFirestore())),
);
