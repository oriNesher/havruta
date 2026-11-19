import {test} from "node:test";
import * as assert from "node:assert/strict";
import {publicProfileFor} from "../publicProfile";

test("exposes only uid and username, never email or tokens", () => {
  assert.deepEqual(
    publicProfileFor("u1", {
      username: "Dana",
      email: "dana@example.com",
      emailLower: "dana@example.com",
      fcmTokens: ["t"],
      respectBalance: 4,
    }),
    {uid: "u1", username: "Dana", usernameLower: "dana"}
  );
});

test("a users doc without a username isn't findable yet", () => {
  assert.equal(publicProfileFor("u1", {fcmTokens: ["t"]}), null);
  assert.equal(publicProfileFor("u1", {username: "   "}), null);
  assert.equal(publicProfileFor("u1", undefined), null);
});

test("the username is trimmed before it's mirrored", () => {
  assert.deepEqual(publicProfileFor("u1", {username: " Dana "}), {
    uid: "u1",
    username: "Dana",
    usernameLower: "dana",
  });
});
