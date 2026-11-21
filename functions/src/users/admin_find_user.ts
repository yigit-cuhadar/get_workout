import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { liveUsersDeps } from "./directory";
import { findUser } from "./users";

/** The uid of the user with an email or uid. Admins only. */
export const adminFindUser = onCall({ secrets: [revenueCatApiKey] }, (request) =>
  findUser(request.auth, request.data, liveUsersDeps()),
);
