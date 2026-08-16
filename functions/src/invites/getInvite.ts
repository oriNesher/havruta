import {onCall} from "firebase-functions/v2/https";
import {lookupInvite} from "./lookup";

interface GetInviteRequest {
  linkId: string;
}

// Deliberately does not require request.auth — this is the one callable a
// signed-out recipient hits, so they can see who invited them and to what
// challenge before being asked to log in or register.
export const getInvite = onCall<GetInviteRequest>(
  {maxInstances: 5},
  async (request) => {
    const linkId = request.data?.linkId;
    if (!linkId || typeof linkId !== "string") {
      return {valid: false, reason: "not_found"};
    }

    return lookupInvite(linkId);
  }
);
