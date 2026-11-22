import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";

import { firestoreRulesStore, rulesHistory } from "./store";

/** The latest generator rules versions. Admins only. */
export const generatorRulesHistory = onCall((request) =>
  rulesHistory(request.auth, firestoreRulesStore(getFirestore())),
);
