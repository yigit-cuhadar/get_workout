import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "../dashboard/revenuecat_metrics";
import { liveUsersDeps } from "./directory";
import { deleteUser } from "./users";

/** Deletes an account and all of its data. Admins only. */
export const adminDeleteUser = onCall({ secrets: [revenueCatApiKey] }, (request) =>
  deleteUser(request.auth, request.data, liveUsersDeps()),
);
