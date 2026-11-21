import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { liveUsersDeps } from "./directory";
import { revokePremium } from "./users";

/** Ends promotional Premium in RevenueCat. Admins only. */
export const adminRevokePremium = onCall({ secrets: [revenueCatApiKey] }, (request) =>
  revokePremium(request.auth, request.data, liveUsersDeps()),
);
