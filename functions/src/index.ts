import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

import { REGION } from "./config";

initializeApp();
setGlobalOptions({ region: REGION });

// One export per function, each in a file of its own.
export { deleteAccount } from "./delete_account";
export { revenueCatWebhook } from "./revenuecat_webhook";
export { sendAnnouncement } from "./send_announcement";
