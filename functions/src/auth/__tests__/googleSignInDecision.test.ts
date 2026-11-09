import * as assert from "node:assert/strict";
import {test} from "node:test";
import {decideGoogleSignIn} from "../googleSignInDecision";

const SUB = "google-sub-1";

test("no existing account: plain Google sign-in", () => {
  assert.deepEqual(decideGoogleSignIn(null, SUB), {action: "proceed"});
});

test("unverified password account: must link instead of sign in", () => {
  assert.deepEqual(
    decideGoogleSignIn(
      {emailVerified: false, providers: [{providerId: "password", uid: "a"}]},
      SUB
    ),
    {action: "linkRequired", methods: ["password"]}
  );
});

test("unverified Facebook account: must link so Facebook isn't dropped", () => {
  assert.deepEqual(
    decideGoogleSignIn(
      {
        emailVerified: false,
        providers: [{providerId: "facebook.com", uid: "fb-1"}],
      },
      SUB
    ),
    {action: "linkRequired", methods: ["facebook.com"]}
  );
});

test("verified email: Firebase links and keeps the password", () => {
  assert.deepEqual(
    decideGoogleSignIn(
      {emailVerified: true, providers: [{providerId: "password", uid: "a"}]},
      SUB
    ),
    {action: "proceed"}
  );
});

test("this Google account already linked: plain sign-in", () => {
  assert.deepEqual(
    decideGoogleSignIn(
      {
        emailVerified: false,
        providers: [
          {providerId: "password", uid: "a"},
          {providerId: "google.com", uid: SUB},
        ],
      },
      SUB
    ),
    {action: "proceed"}
  );
});

test("another Google account on the email isn't offered as a method", () => {
  assert.deepEqual(
    decideGoogleSignIn(
      {
        emailVerified: false,
        providers: [
          {providerId: "password", uid: "a"},
          {providerId: "google.com", uid: "other-sub"},
        ],
      },
      SUB
    ),
    {action: "linkRequired", methods: ["password"]}
  );
});

test("account with no sign-in methods: nothing to lose", () => {
  assert.deepEqual(
    decideGoogleSignIn({emailVerified: false, providers: []}, SUB),
    {action: "proceed"}
  );
});
