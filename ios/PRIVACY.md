# Privacy policy — draft for review

This is the text to publish at **https://metastoryhealth.com/privacy**, the URL
already wired into `AppConfig.privacyPolicyURL` and the one App Store Connect
will point reviewers at.

It has to exist and be live *before* submission. App Review opens the privacy
policy URL on a health app more or less every time, and a 404 or a generic
policy that never says the word "HealthKit" is a routine rejection under
guideline 5.1.1(i) and 5.1.3.

**Two things below need C.J. to fill in** — the publication date and a postal
address for Megaphone Functional Health, LLC. Both are marked `[FILL IN]`, and
neither can be answered from the code. Everything else is written from what the
code actually does, and was checked against the source rather than assumed.

The lab-order disclosure that used to be a third gap is now written: the
GI-MAP form posts the whole order — name, email, phone, date of birth, mailing
address and the free-text concerns box — to the lab-orders Worker, which emails
it to the practitioner. A real person does receive it, so it is disclosed under
"Who we share it with" rather than left as a question.

---

## Before publishing, read this part

Drafting this turned up one thing that is a product decision, not a wording
decision:

**Weight read from Apple Health can reach Google Gemini.**

The chain is real and worth tracing once:

1. `syncBodyMassFromHealth()` (index.html) reads body mass from HealthKit and
   writes it into `_userProfile` as `profile.weight`.
2. `_dressData()` returns that whole profile object as `p`.
3. The DRESS model prompts post that context to
   `https://metastory-ai.cjbergmen.workers.dev/gemini`, which calls Google
   Gemini.

Apple's guideline 5.1.3 allows HealthKit data to be used for "improving health
management" but not to be disclosed to third parties without consent. Sending a
HealthKit-derived weight to an LLM to generate a plan is arguably squarely
within health management — but it is a disclosure to a third party, so it needs
to be *disclosed in this policy* and it needs to be true that the person agreed
to it. The draft below discloses it plainly.

If C.J. would rather not have that conversation with a reviewer at all, the
alternative is a one-line fix in `_dressData()` — strip `weight` from `p` before
it goes into the AI context, or tag the HealthKit-sourced value so it can be
excluded. That is a decision for him, not a bug I should quietly patch, so it is
written up here and in `STATE.md` rather than changed.

---

## The policy text

> **Metastory Health — Privacy Policy**
>
> Last updated: [FILL IN: publication date]
>
> Metastory Health ("Metastory", "we") is operated by Megaphone Functional
> Health, LLC. This policy covers the Metastory web app at
> app.metastoryhealth.com and the Metastory app for iPhone.
>
> ### The short version
>
> Metastory is a personal health tool. The information you put into it is
> yours. We do not sell it, we do not use it for advertising, and we do not
> share it with anyone except the service providers listed below who are
> needed to make the app work.
>
> ### What we collect
>
> **Information you give us.** Your name and email address when you create an
> account. Your profile — goal, body type, sleep and stress self-ratings. What
> you log: workouts and sets, food, sleep, journal entries, symptom and
> assessment answers, and supplement plans.
>
> **Information from Apple Health (HealthKit), if you turn it on.** Apple
> Health integration is off until you switch it on in Settings and grant
> permission on Apple's own sheet. When it is on:
>
> - **We write to Apple Health:** the workouts you finish in Metastory, and the
>   active energy those workouts burned, so your training appears alongside the
>   rest of your activity and counts toward your rings.
> - **We read from Apple Health:** your most recent body weight, and your step
>   count for the current day. Weight is used to fill in your Metastory profile
>   so you are not retyping a number you have already recorded. Steps are shown
>   to you in the app.
>
> We read nothing else from Apple Health, and we do not request access to
> clinical or medical records. You can revoke Metastory's access at any time in
> the Health app under Sharing → Apps, or turn the connection off in Metastory's
> own Settings.
>
> **Information collected automatically.** Standard technical information
> needed to serve the app, such as your device type and app version. Metastory
> does not use advertising identifiers, does not track you across other
> companies' apps or websites, and contains no advertising or analytics SDKs.
>
> ### How we use it
>
> To run the app: to show you your own logs and history, to generate your plan
> and recommendations, to sync your data between your devices, and to support
> you when you contact us.
>
> We do **not** use your health or fitness information — including anything
> read from Apple Health — for advertising, for marketing, or for data mining.
> We do not sell it or rent it to anyone, and we do not use it for any purpose
> other than helping you manage your own health.
>
> ### Who we share it with
>
> Only the service providers that make the app function, each of which handles
> the data on our behalf:
>
> - **Google Firebase** (Authentication, Cloud Firestore) — stores your account
>   and your logged data so it syncs across your devices.
> - **Google Gemini, via our own Cloudflare Worker** — when Metastory generates
>   personalized guidance, the relevant parts of your profile and recent logs
>   are sent to Google's Gemini model to produce that guidance. **If you have
>   connected Apple Health, the weight read from Health forms part of the
>   profile that may be included.** This is used only to generate your
>   recommendations. It is not used for advertising or for training models on
>   your data.
> - **Cloudflare** — serves the app and runs the workers described above.
>
> - **Your practitioner at Megaphone Functional Health, via our lab-order
>   Worker** — only if you submit a GI-MAP test order. Everything on that form
>   — your name, email address, phone number, date of birth, mailing address,
>   and whatever you write in the health-concerns box — is saved to Firestore
>   and posted to a Cloudflare Worker, which emails it to the practitioner so
>   the order can be placed. A real person reads it; that is the point of the
>   form. The practitioner then enters the order with **Evexia Diagnostics**,
>   the laboratory that bills you, ships the collection kit and processes your
>   sample. Evexia handles your payment and your results under its own privacy
>   policy, not this one. Nothing on that form leaves your device unless you
>   submit it, and the confirmation screen has a "Delete my submitted data"
>   link that removes the order again.
>
> We do not share information with anyone else unless you ask us to, or unless
> we are legally required to.
>
> ### Sign in with Apple
>
> If you sign in with Apple, you may choose to hide your email address, in
> which case we receive only Apple's private relay address and can email you
> only through it. Apple sends us your name only the first time you authorize;
> we save it to your profile then, because there is no second chance to ask.
>
> ### Deleting your account
>
> Settings → Delete my account erases your profile, plan, and all of your logs
> from our database, deletes your sign-in account, and — if you signed in with
> Apple — revokes Metastory's Sign in with Apple token. This is immediate and
> cannot be undone.
>
> Deleting your Metastory account does **not** delete data Metastory previously
> wrote into Apple Health, because that data belongs to you and lives on your
> device, not on our servers. You can remove it in the Health app under
> Browse → Workouts, or via Sharing → Apps → Metastory → Delete All Data.
>
> ### Where your data lives, and for how long
>
> Your data is stored by Google Firebase in the United States, and is kept for
> as long as your account exists. Data read from Apple Health is held only as
> part of your Metastory profile and is removed when you delete your account.
>
> ### Children
>
> Metastory is not directed to children under 13 and we do not knowingly
> collect information from them.
>
> ### Medical disclaimer
>
> Metastory is a wellness and education tool. It is not a medical device, it
> does not diagnose or treat any condition, and nothing in it is a substitute
> for advice from a qualified clinician.
>
> ### Changes
>
> If this policy changes materially we will update the date at the top and
> note the change in the app.
>
> ### Contact
>
> support@metastoryhealth.com
> [FILL IN: mailing address for Megaphone Functional Health, LLC — several
> privacy frameworks expect a postal address, and it is cheap to include.]

---

## Cross-check against the privacy manifest

`Support/PrivacyInfo.xcprivacy` declares Health, Fitness, Email, Name and UserID
as collected-and-linked, none for tracking, all for app functionality. That
matches the policy above and matches the code. The App Store Connect privacy
questionnaire should be answered the same way — the three have to agree, and a
reviewer who spots a mismatch will ask about it.

One gap to close in App Store Connect, not in the manifest: the questionnaire
asks about **third-party data sharing**, and the Gemini path above is a "yes"
for Health and Fitness data. Answer it honestly; the policy text supports it.
