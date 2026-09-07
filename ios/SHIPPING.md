# Shipping Metastory Health to the App Store

Written for where you are now: enrolled in the Apple Developer Program,
nothing else set up yet. Work top to bottom. Steps 1–6 get the app running
on your own phone; 7–11 get it in front of review.

Three things in the repo are deliberately unfinished because only you can
finish them. They're marked **YOU** below, and nothing will build or pass
review until they're done:

- **YOU** the signing team (step 1)
- **YOU** the Google OAuth iOS client ID (step 4)
- **YOU** a real 1024×1024 app icon (step 6)

---

## 1. Open it and set your team

```
open ios/MetastoryHealth.xcodeproj
```

Select the **MetastoryHealth** target → **Signing & Capabilities** →
set **Team** to your developer account. Leave "Automatically manage
signing" ticked.

The bundle identifier is `com.metastoryhealth.app`. Change it here if you
want something else — it has to match everywhere below, and it can never be
changed after the app is on sale.

You should now see three capabilities already listed, because they're in
`MetastoryHealth/Support/MetastoryHealth.entitlements`:

- HealthKit
- Sign in with Apple
- Time Sensitive Notifications

Xcode registers the App ID for you the first time you build to a device.

> If Xcode shows a signing error mentioning HealthKit or Sign in with
> Apple, it usually just needs one click on **Try Again** after the App ID
> is created.

## 2. Build to your own phone

Plug in an iPhone, pick it as the run destination, press ⌘R.

The simulator will run the app, but **the three things worth testing don't
work there**: background audio needs real hardware, haptics don't exist,
and HealthKit has no data. Use a real device from the start.

## 3. Turn on Sign in with Apple in Firebase

Firebase console → your `cj-fitness-fb5a0` project → **Authentication** →
**Sign-in method** → **Apple** → Enable.

For the native iOS flow, enabling the provider is enough — the Services ID
and private key fields are only needed for web and Android sign-in, which
Metastory doesn't use for Apple. Leave them blank.

Then **Authentication → Settings → Authorized domains**: confirm
`app.metastoryhealth.com` is listed. It should already be.

## 4. Create the Google OAuth iOS client — **YOU**

Google won't run OAuth inside an embedded web view, so the app does it
through Safari, and that needs an *iOS* OAuth client. The web client the
PWA uses will not work.

1. [Google Cloud console](https://console.cloud.google.com/apis/credentials)
   → make sure the project selected is the one behind Firebase
   (`cj-fitness-fb5a0`).
2. **Create credentials → OAuth client ID → Application type: iOS**.
3. Bundle ID: `com.metastoryhealth.app`
4. Copy the client ID it gives you. It looks like
   `980408905992-xxxxxxxxxxxx.apps.googleusercontent.com`.
5. Paste it into `ios/MetastoryHealth/App/AppConfig.swift`:

   ```swift
   static let googleClientID = "980408905992-xxxxxxxxxxxx.apps.googleusercontent.com"
   ```

The redirect scheme is derived from the client ID automatically, so there
is nothing else to fill in.

Until you do this, the Google button reports "Google sign-in isn't set up
in this build yet" instead of opening a broken sheet. **Sign in with Apple
works without this step**, so you can test everything else first.

## 5. Test on a device

Work through this on real hardware. Each line is something a reviewer can
also try.

**Timers** — start a rest timer, lock the phone, wait. The bell should ring
on the lock screen. Tap it: the app opens with the timer already caught up.
Then turn on a Focus mode and repeat — it should still come through, because
the notification is marked time-sensitive.

**Audio** — play a track from *Safe Inside*, lock the phone. Sound keeps
going. The lock screen shows the track and the app icon as artwork.
Play/pause and skip work from there and from AirPods. Pull the headphones
out mid-track: it pauses rather than blaring out loud.

**Haptics** — log a set, mark an exercise done, finish a workout. Each
should feel different.

**Health** — Settings → Connect Apple Health → allow. Finish a workout, then
open the Health app: it should be there under Workouts. If your weight is in
Health and your Metastory profile has none, it fills itself in.

**Sign-in** — sign out, then in with Apple. Your logs come back. Sign out and
in again: Apple won't re-send your name the second time, and the app should
still show it, because it was saved on the first authorization.

**Deletion** — Settings → Delete my account. It should ask twice, ask you to
sign in again, then erase everything and reload to a signed-out app. Confirm
in the Firebase console that the user and their documents are gone.
*Do this on a throwaway account.*

**Offline** — turn on airplane mode and launch. On a first-ever launch you
get the retry screen; after that the service worker serves the cached page.

**Links out** — tap through to Fullscript or a lab portal. It should open in
a Safari sheet you can swipe away, not strand you in the app.

## 6. Replace the app icon — **YOU**

`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` was generated by
upscaling the existing 512px `icon-512.png`, because that's the largest
source in the repo. It's the right size and format (1024×1024, no alpha,
which is what the App Store requires) but it is genuinely soft when scaled
up. Export a real 1024 from whatever the icon was originally drawn in and
drop it in over the top, same filename.

## 7. Fill in the App Store Connect record

[App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** →
**New App**.

| Field | Value |
|---|---|
| Platform | iOS |
| Name | Metastory Health |
| Primary language | English (U.S.) |
| Bundle ID | `com.metastoryhealth.app` |
| SKU | `metastory-health-ios` |
| Category | Health & Fitness |
| Secondary category | Medical, or leave blank |

**Age rating**: answer the questionnaire honestly. Health and wellness
content that isn't clinical usually lands at 12+.

**Privacy policy URL** is required, and the page must be live before you
submit. It has to say specifically what happens to HealthKit data — Apple
checks for this on health apps and rejects for its absence. At minimum:
what's read, what's written, that it is never used for advertising or sold,
and how someone deletes it.

**Support URL** is also required. A page with an email address is fine.

## 8. App privacy — the nutrition labels

App Store Connect → your app → **App Privacy**. Answer it to match
`Support/PrivacyInfo.xcprivacy`, which is already in the build:

| Data | Collected | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| Health | Yes | Yes | No | App Functionality |
| Fitness | Yes | Yes | No | App Functionality |
| Email address | Yes | Yes | No | App Functionality |
| Name | Yes | Yes | No | App Functionality |
| User ID | Yes | Yes | No | App Functionality |

Say **No** to tracking across apps and websites. Metastory doesn't do it,
and there's no ad SDK in the build.

## 9. Archive and upload

1. Set the run destination to **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. In the Organizer: **Distribute App → App Store Connect → Upload**.

Export compliance is already answered in `Info.plist`
(`ITSAppUsesNonExemptEncryption` is `false`, which is correct — the app
uses nothing beyond standard HTTPS), so that question won't come up.

To ship an update later, bump `MARKETING_VERSION` (the version people see)
and `CURRENT_PROJECT_VERSION` (the build number, which must go up on every
single upload) in the target's build settings.

## 10. Review notes — write these, they matter

Paste something close to this into **App Review Information → Notes**. The
first paragraph is the important one: a web-view-based app draws guideline
4.2 scrutiny, and the fix is to point at what the app does that a website
can't.

> Metastory Health is a functional-health companion. Its interface is
> rendered from our web platform, and the app adds native capabilities the
> web cannot provide on iOS:
>
> • Rest timers are delivered as time-sensitive local notifications, so
>   they fire on the lock screen while the app is closed.
> • The Safe Inside audio programme continues with the screen locked, with
>   full lock-screen and AirPods transport controls.
> • Completed workouts are written to Apple Health, and body weight and
>   step count are read back into the app.
> • Haptic feedback throughout set logging and timers.
> • Sign in with Apple, implemented natively.
>
> To review: sign in with Apple or Google, complete the short setup, then
> open the Workouts tab. Tapping a set logs it and starts a rest timer —
> locking the device will demonstrate the background notification. The
> Listening tab plays the audio programme; locking the device will
> demonstrate background playback and the lock-screen controls.
>
> Account deletion: Settings (gear, top right) → "Delete my account". This
> deletes the account and all associated data.
>
> Apple Health is optional and off until enabled in Settings → Connect
> Apple Health. Health data is used only to display the user's own
> information in the app. It is never used for advertising and is never
> sold or shared.
>
> The app links out to Fullscript and to diagnostic-lab portals for
> physical products and laboratory services. These are physical goods and
> real-world services purchased outside the app, and open in Safari.
>
> Metastory Health supports personal health habits. It does not diagnose,
> treat, or provide medical advice, and it is not a medical device.

**Provide a demo account.** A reviewer who can't get past sign-in will
reject the app. Create a real account, populate it with a few days of
logs, and put the credentials in the demo account fields. If you give them
a Google account, make sure it has no 2FA prompt they can't complete.

## 11. Screenshots

Required: 6.9" (iPhone 17 Pro Max or similar). Everything else is
optional now — App Store Connect scales the 6.9" set down.

Take them on a device with real-looking data, not an empty account. The
tabs worth showing: Today, a workout mid-session with a rest timer
running, the Listening player, and the Health Detective.

---

## Things that will get you rejected, in order of likelihood

**Guideline 4.2, minimum functionality.** The single biggest risk for any
app built around a web view. What defends against it is that the native
features are real, work, and are demonstrable in the first minute — which
is why the review notes above tell the reviewer exactly where to tap. If it
is rejected under 4.2 anyway, reply in Resolution Center pointing at the
background notification and background audio specifically; don't resubmit
unchanged.

**No demo account, or one that doesn't work.** Automatic rejection.

**Privacy policy that doesn't mention HealthKit.** Health apps get checked
for this specifically.

**Account deletion that a reviewer can't find.** It's in Settings; the
review notes say so. Keep it there.

**HealthKit permission strings that don't say why.** The two in
`Info.plist` do. Don't shorten them.

## Known gaps

- The app icon is upscaled until you replace it (step 6).
- Google sign-in is inert until the client ID is filled in (step 4). Apple
  sign-in works without it.
- Existing users signed in with Google on the web will be signed out the
  first time they use the app, because the app is a separate storage
  origin. Signing in again pulls everything back from Firestore. Worth a
  line in the App Store description or a first-launch note.
- Apple token revocation on account deletion is called only when the
  Firebase SDK exposes `revokeAccessToken`. It's guarded, so deletion still
  succeeds either way, but confirm it fires on the SDK version you ship.
