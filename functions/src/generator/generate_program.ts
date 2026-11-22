import { onCall } from "firebase-functions/v2/https";

import { generateFor, liveGenerateDeps } from "./generation";

/** A program from the caller's answers. Premium users and admins only. */
export const generateProgram = onCall((request) =>
  generateFor(request.auth, request.data, liveGenerateDeps()),
);
