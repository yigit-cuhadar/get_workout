import { onCall } from "firebase-functions/v2/https";

import { revenueCatApiKey } from "./revenuecat_metrics";
import { liveDeps, refreshDashboard, requireAdmin } from "./run";

/** The nightly refresh on an admin's demand; answers with its status. */
export const dashboardRefresh = onCall(
  { secrets: [revenueCatApiKey], timeoutSeconds: 540 },
  async (request) => {
    requireAdmin(request.auth);
    return refreshDashboard(liveDeps());
  },
);
