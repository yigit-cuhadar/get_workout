import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

import { REGION } from "./config";

initializeApp();
setGlobalOptions({ region: REGION });

// One export per function, each in a file of its own.
export { appSettingsGet } from "./app_settings/app_settings_get";
export { appSettingsHistory } from "./app_settings/app_settings_history";
export { appSettingsPublish } from "./app_settings/app_settings_publish";
export { cancelAnnouncement } from "./cancel_announcement";
export { dashboardNightly } from "./dashboard/dashboard_nightly";
export { dashboardRange } from "./dashboard/dashboard_range";
export { dashboardRefresh } from "./dashboard/dashboard_refresh";
export { deleteAccount } from "./delete_account";
export { generateProgram } from "./generator/generate_program";
export { generatorRulesCheck } from "./generator/generator_rules_check";
export { generatorRulesGet } from "./generator/generator_rules_get";
export { generatorRulesHistory } from "./generator/generator_rules_history";
export { generatorRulesPublish } from "./generator/generator_rules_publish";
export { guestCleanupNightly } from "./guest_cleanup";
export { revenueCatWebhook } from "./revenuecat_webhook";
export { sendAnnouncement } from "./send_announcement";
export { sendScheduledAnnouncement } from "./send_scheduled_announcement";
export { sendSupportReply } from "./send_support_reply";
export { adminDeleteUser } from "./users/admin_delete_user";
export { adminFindUser } from "./users/admin_find_user";
export { adminGetUser } from "./users/admin_get_user";
export { adminGrantPremium } from "./users/admin_grant_premium";
export { adminListUsers } from "./users/admin_list_users";
export { adminRevokePremium } from "./users/admin_revoke_premium";
export { adminSetAdmin } from "./users/admin_set_admin";
