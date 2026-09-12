# Where this is right now

Working notes for whoever picks this up next — a Claude Code session running
locally on C.J.'s Mac, most likely. Read `README.md` for how the app is put
together and `SHIPPING.md` for the route to the App Store. This file is just
the current state.

Last updated: 2026-09-12, after the first successful build.

## Done

- The app builds clean on the iOS Simulator (Xcode 26.6, iPhone 17 Pro). No
  compile errors. The Metastory web app loads and renders.
- Signing team is set to **Megaphone Functional Health, LLC**, bundle ID
  `com.metastoryhealth.app`, automatic signing on.
- Background Modes shows "Audio, AirPlay, and Picture in Picture" ticked,
  confirming `Support/Info.plist` is being read.

## Blocked, and why

**Sign-in doesn't complete.** Not a code bug — two prerequisites are
outstanding, and a third only applies on the Simulator:

1. `AppConfig.googleClientID` is still the placeholder, so the Google button
   deliberately reports "Google sign-in isn't set up in this build yet."
   Fixing it is SHIPPING.md step 4 (create an OAuth *iOS* client in Google
   Cloud — the web client the PWA uses will not work).
2. The Apple provider is not yet enabled in the Firebase console, so
   `signInWithCredential` for Apple returns `auth/operation-not-allowed`.
   That's SHIPPING.md step 3, and it is about two minutes of clicking.
3. On the Simulator specifically, Sign in with Apple also needs an Apple ID
   signed in to the simulated device: Simulator → Settings → "Sign in to
   your iPhone".

Apple is the faster of the two to unblock; do that first.

**Provisioning profile can't be generated.** "Your team has no devices from
which to generate a provisioning profile." Expected — no physical iPhone has
ever been registered to this team. It resolves itself the moment a device is
plugged in. It does not block Simulator builds.

## Not yet verified on hardware

These cannot be tested in the Simulator and are the reason the native shell
exists at all. All of them need a real iPhone:

- Rest-timer notifications firing while the app is backgrounded or closed
- Background audio continuing with the screen locked, and the lock-screen /
  AirPods transport controls
- Haptics
- HealthKit writing a finished workout and reading body mass back

## Quick check that the bridge is alive

Open Settings (gear) in the app and scroll to the bottom. Below the existing
"App" card there should be three cards that only exist in the native build —
**Apple Health**, **Notifications**, **Delete my account** — and a line
reading "Metastory for iPhone 1.0 (1)". If those are there, `window.Metastory`
is injected and the JS-to-Swift bridge is working.

## Still outstanding before submission

- A true 1024×1024 app icon. The one in the asset catalog was upscaled from
  the repo's 512px source and is soft. (SHIPPING.md step 6.)
- A live privacy policy that names HealthKit specifically.
- A demo account for App Review, populated with a few days of logs.
