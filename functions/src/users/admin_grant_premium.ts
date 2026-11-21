import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { liveUsersDeps } from "./directory";
import { grantPremium } from "./users";

/** Grants promotional Premium in RevenueCat. Admins only. */
export const adminGrantPremium = onCall({ secrets: [revenueCatApiKey] }, (request) =>
  grantPremium(request.auth, request.data, liveUsersDeps()),
);
