import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

import { REGION } from "./config";

initializeApp();
setGlobalOptions({ region: REGION });

// One export per function, each in a file of its own.
export { dashboardNightly } from "./dashboard/dashboard_nightly";
export { dashboardRange } from "./dashboard/dashboard_range";
export { dashboardRefresh } from "./dashboard/dashboard_refresh";
export { deleteAccount } from "./delete_account";
export { revenueCatWebhook } from "./revenuecat_webhook";
export { sendAnnouncement } from "./send_announcement";
export { adminDeleteUser } from "./users/admin_delete_user";
export { adminFindUser } from "./users/admin_find_user";
export { adminGetUser } from "./users/admin_get_user";
export { adminGrantPremium } from "./users/admin_grant_premium";
export { adminListUsers } from "./users/admin_list_users";
export { adminRevokePremium } from "./users/admin_revoke_premium";
export { adminSetAdmin } from "./users/admin_set_admin";
