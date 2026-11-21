import { getRemoteConfig } from "firebase-admin/remote-config";
import { onCall } from "firebase-functions/v2/https";

import { loadSettings } from "./settings";

/** The app's Remote Config keys as the panel edits them. Admins only. */
export const appSettingsGet = onCall((request) =>
  loadSettings(request.auth, getRemoteConfig()),
);
