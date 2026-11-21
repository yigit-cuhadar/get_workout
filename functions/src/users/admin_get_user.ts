import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { liveUsersDeps } from "./directory";
import { getUser } from "./users";

/** Everything a user's page shows. Admins only. */
export const adminGetUser = onCall({ secrets: [revenueCatApiKey] }, (request) =>
  getUser(request.auth, request.data, liveUsersDeps()),
);
