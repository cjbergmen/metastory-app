# App Review — demo account and reviewer notes

Everything App Review needs that isn't the binary. Two jobs: a demo account
that actually has data in it, and the notes that stop a reviewer guessing.

The single biggest cause of a rejection on an app like this is a reviewer
opening it, hitting a sign-in wall, signing in to an empty account, seeing a
blank week, and rejecting for "incomplete content" or "we were unable to review
the features described." A populated demo account fixes that, and it takes
about twenty minutes.

---

## 1. The demo account

### Which sign-in method

Metastory offers Apple and Google only — there is no email/password path. That
is a problem for App Review, because **the reviewer cannot use Sign in with
Apple with an account they do not control, and Apple explicitly asks you not to
hand them a personal Apple ID.**

Pick one of these, in order of preference:

1. **Add a hidden email/password path for review.** Firebase Auth already
   supports it; the UI does not expose it. A "demo" entry point behind a long
   press or a build-flag-gated row is the least friction and is what most
   health apps do. Cost: a small amount of code, and it must be genuinely
   reachable by the reviewer.
2. **Create a dedicated Google account** (e.g. `review@metastoryhealth.com` or
   a plain Gmail) and give App Review its credentials. This works today with no
   code change. Turn off 2FA on it, or the reviewer will be locked out — this
   is the usual failure. Google may also challenge a sign-in from Apple's
   review network; that risk is real but usually survivable.
3. Ask for an exemption on the grounds that both providers are third-party.
   Weakest option, don't lead with it.

**Recommendation: option 2 for the first submission**, because it needs no code
and no new build. If review bounces on it, fall back to option 1.

### What to put in it

The account has to look like someone has been using it for a week or so.
Seed it by signing in as the demo user on a device and using the app normally
— it is faster than writing a seeding script, and it exercises the same code
paths a reviewer will.

Aim for, across the last 7 days:

- **Profile completed** — run the onboarding wizard fully. Name "Review User",
  a goal, body type, sleep and stress. A completed profile is what unlocks the
  plan views; an empty one shows setup prompts everywhere.
- **4–5 workouts logged**, with real sets and weights, on non-consecutive days,
  and at least one marked finished (that is what writes to Health).
- **A few days of food logs** — enough that the day view isn't empty.
- **2–3 sleep entries** and a couple of `dayMisc` markers (stress, rest).
- **One or two journal entries.** Keep them bland; a reviewer reads these.
- **At least one completed assessment** (gut, NS or amino acid) so the DRESS
  model has something to render instead of an empty state.

Those map to the five collections the app actually stores per user —
`foodLogs`, `workoutLogs`, `sleepLogs`, `dayMisc`, `journal` — plus the profile.

> **Do not use this account to test "Delete my account".** Test deletion on a
> separate throwaway, and re-verify the demo account still has its data the day
> you submit. It is an easy thing to wipe by accident and not notice.

---

## 2. Reviewer notes

Paste into **App Store Connect → the version → App Review Information → Notes**.
Keep it to what a reviewer needs to reproduce the features; long notes get
skimmed.

> Metastory Health is a personal wellness tracker: workouts, food, sleep,
> journaling, and a guided supplement/nutrition plan. The iPhone app is a
> native container around our web app, with native rest-timer notifications,
> background audio, haptics, Apple Health, and native sign-in.
>
> **Demo account**
> Sign in with Google using:
> Email: [FILL IN]
> Password: [FILL IN]
> Two-factor authentication is disabled on this account. It is pre-populated
> with about a week of workouts, food, sleep and journal entries.
>
> **Sign in with Apple** is offered alongside Google as required by 4.8, and
> works on a real device with any Apple ID.
>
> **Apple Health (HealthKit)** is optional and off by default. To enable:
> Settings (gear, top right) → scroll to "Apple Health" → Connect Apple Health.
> - Metastory *writes* finished workouts and their active energy.
> - Metastory *reads* the most recent body weight and today's step count, so
>   the profile does not ask for numbers already recorded elsewhere.
> To see a workout written: start any workout from the Train tab, log a set,
> then finish it. It appears in the Health app under Browse → Workouts.
> Our privacy policy at https://metastoryhealth.com/privacy describes the
> HealthKit use specifically.
>
> **Rest-timer notifications** are local notifications, marked time-sensitive
> so they arrive during Focus. Log a set to start a rest timer, then lock the
> phone; the alert fires on the lock screen and tapping it returns to the app
> with the timer caught up.
>
> **Background audio** is the "Safe Inside" album included with the app. Start a
> track and lock the phone; playback continues and the lock screen shows
> transport controls.
>
> **Account deletion** is in Settings → Delete my account. It asks twice, then
> re-authenticates, then permanently erases the account and all of its data,
> and revokes the Sign in with Apple token. Please use a throwaway account if
> you exercise it — the demo account above will not come back.
>
> **Medical claims:** Metastory is a wellness and education tool. It does not
> diagnose or treat, and the app states this. It is not a medical device.

---

## 3. Things a reviewer will probably poke, and the honest answer

**"This is just a website in a wrapper" (guideline 4.2, minimum
functionality).** The real answer is the four native capabilities the web app
demonstrably cannot do: local notifications that survive suspension, background
audio with lock-screen transport, HealthKit read/write, and haptics. All four
are listed in the notes above with reproduction steps, which is what turns 4.2
from a rejection into a non-issue. Make sure every one of them actually works
on device before submitting — a native claim that fails when the reviewer tries
it is worse than not claiming it.

**Supplement and protocol content.** The app issues practitioner protocol codes
and recommends supplements. Expect questions about whether this constitutes
medical advice. The medical disclaimer needs to be visible in the app, not only
in the policy. [FILL IN: confirm where the in-app disclaimer appears, and note
it here so it can be pointed to.]

**Lab ordering.** `LAB_CONFIG` posts lab orders to a Worker. If a reviewer finds
a path to order labs, that raises questions about regulated services and about
who receives the order. Know in advance whether that flow is reachable by a
fresh account, and if it is, be ready to explain it.

**Sign in with Apple and account deletion.** Apple checks that an app offering
Sign in with Apple also offers in-app account deletion, and that deletion
revokes the Apple token. Metastory does both. Note that the revoke had a real
bug until now — it was passing the authorization code saved at first sign-in,
which is single-use and expires in five minutes, so it always silently failed.
It now uses the fresh code from the re-authorization that deletion performs.
**Verify this end to end on a throwaway Apple ID before submitting**, and
confirm in the Firebase console that the user is gone: this is the one thing in
the deletion flow that has never actually worked.

---

## 4. Store listing bits still to write

- **Screenshots** — 6.9" and 6.5" iPhone are the required sizes. Take them from
  the demo account so they show real content.
- **Description, keywords, support URL, marketing URL.**
- **Age rating** — expect to declare medical/treatment information; that alone
  does not push it above 12+.
- **App Privacy questionnaire** — must agree with `PrivacyInfo.xcprivacy` and
  with the published policy. See the cross-check note at the end of
  `PRIVACY.md`, including the third-party-sharing answer for the Gemini path.
