import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { revenueCatApiKey } from "./revenuecat_metrics";
import { liveDeps, refreshDashboard } from "./run";
import { TIME_ZONE } from "./warehouse";

/** Every morning, after the night's Analytics export. */
export const dashboardNightly = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: TIME_ZONE,
    secrets: [revenueCatApiKey],
    timeoutSeconds: 540,
  },
  async () => {
    const status = await refreshDashboard(liveDeps());
    logger.info("dashboard refreshed", status);
  },
);
