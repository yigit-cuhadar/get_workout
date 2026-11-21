import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { liveUsersDeps } from "./directory";
import { setAdmin } from "./users";

/** Grants or revokes the `admin` claim. Admins only. */
export const adminSetAdmin = onCall({ secrets: [revenueCatApiKey] }, (request) =>
  setAdmin(request.auth, request.data, liveUsersDeps()),
);
