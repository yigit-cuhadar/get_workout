import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";

import { firestoreRulesStore, publishRules } from "./store";

/** Publishes the panel's rules as the next version. Admins only. */
export const generatorRulesPublish = onCall((request) =>
  publishRules(request.auth, request.data, firestoreRulesStore(getFirestore())),
);
