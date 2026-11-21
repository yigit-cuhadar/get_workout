import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { liveUsersDeps } from "./directory";
import { listUsers } from "./users";

/** A page of the latest sign-ups, newest first. Admins only. */
export const adminListUsers = onCall({ secrets: [revenueCatApiKey] }, (request) =>
  listUsers(request.auth, request.data, liveUsersDeps()),
);
