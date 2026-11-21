import { getRemoteConfig } from "firebase-admin/remote-config";
import { onCall } from "firebase-functions/v2/https";

import { loadHistory } from "./settings";

/** The latest Remote Config versions and what each changed. Admins only. */
export const appSettingsHistory = onCall((request) =>
  loadHistory(request.auth, getRemoteConfig()),
);
