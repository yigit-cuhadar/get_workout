import { getRemoteConfig } from "firebase-admin/remote-config";
import { onCall } from "firebase-functions/v2/https";

import { publishSettings } from "./settings";

/** Publishes the panel's changed keys as a new version. Admins only. */
export const appSettingsPublish = onCall((request) =>
  publishSettings(request.auth, request.data, getRemoteConfig()),
);
