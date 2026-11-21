import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

import { REGION } from "./config";

initializeApp();
setGlobalOptions({ region: REGION });

// One export per function, each in a file of its own.
export { appSettingsGet } from "./app_settings/app_settings_get";
export { appSettingsHistory } from "./app_settings/app_settings_history";
export { appSettingsPublish } from "./app_settings/app_settings_publish";
export { dashboardNightly } from "./dashboard/dashboard_nightly";
export { dashboardRange } from "./dashboard/dashboard_range";
export { dashboardRefresh } from "./dashboard/dashboard_refresh";
export { deleteAccount } from "./delete_account";
export { revenueCatWebhook } from "./revenuecat_webhook";
export { sendAnnouncement } from "./send_announcement";
