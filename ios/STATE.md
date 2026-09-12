# Where this is right now

Working notes for whoever picks this up next — a Claude Code session running
locally on C.J.'s Mac, most likely. Read `README.md` for how the app is put
together, `SHIPPING.md` for the route to the App Store, `PRIVACY.md` for the
privacy policy that still needs publishing, and `APP-REVIEW.md` for the demo
account and reviewer notes.

Last updated: 2026-09-12, after a code review from a cloud session that could
read everything and compile nothing.

## Done

- The app builds clean on the iOS Simulator (Xcode 26.6, iPhone 17 Pro). No
  compile errors. The Metastory web app loads and renders.
- Signing team was set to **Megaphone Functional Health, LLC** in Xcode,
  bundle ID `com.metastoryhealth.app`, automatic signing on. **See the warning
  under "Traps" — that setting is not in the repo.**
- Background Modes shows "Audio, AirPlay, and Picture in Picture" ticked,
  confirming `Support/Info.plist` is being read.
- A full read of the Swift, the bridge, and the web-side glue. Findings below;
  four fixes are already applied and need compiling.

## Start here, in this order

1. **Build.** Four fixes went in without a compiler (see "Applied but not
   compiled"). One touches method visibility across files, which is exactly the
   kind of thing that fails to build. Do this before anything else, and fix it
   if it is broken rather than reverting — the changes are each a few lines and
   the reasoning is written down.
2. **Enable Apple in Firebase.** `SHIPPING.md` step 3, about two minutes of
   clicking. Unblocks sign-in on device.
3. **Get on hardware.** Plug in an iPhone; the provisioning problem below
   resolves itself the moment you do. Everything that matters is untestable
   until then.
4. **Work the device-test list** further down.
5. **Google OAuth iOS client**, `SHIPPING.md` step 4, when you want the Google
   button live. Apple sign-in works without it.

## Traps

**`DEVELOPMENT_TEAM` is empty in the committed project file.** It reads
`DEVELOPMENT_TEAM = ""` in `project.pbxproj`, even though the team was set in
the Xcode UI during the last session — that change was never committed. A fresh
clone will open with no team and fail to sign. Either set it again in Signing &
Capabilities, or commit the team ID so it survives the next clone. Worth
committing; it is the kind of thing that costs twenty confused minutes.

**Provisioning profile can't be generated.** "Your team has no devices from
which to generate a provisioning profile." Expected — no physical iPhone has
ever been registered to this team. Resolves itself when a device is plugged in.
Does not block Simulator builds.

**Sign-in on the Simulator** also needs an Apple ID signed in to the simulated
device: Simulator → Settings → "Sign in to your iPhone".

## Applied but not compiled

Four changes made from a Linux session. Each is small and the reasoning is in
the comments, but **none has seen a compiler**.

1. **`index.html` — Apple token revocation on account deletion actually works
   now.** This was a real bug. `deleteAccount()` was calling
   `fbAuth.revokeAccessToken()` with `_appleAuthCode` — the authorization code
   saved at *first sign-in*, possibly weeks earlier. Apple's authorization
   codes are single-use and expire in five minutes, so that call always failed,
   and it was wrapped in a bare `catch{}` so it failed silently. The token was
   never revoked. It now prefers `res.authorizationCode` from the
   re-authorization that deletion performs seconds earlier, which is fresh.
   Apple requires this revocation of any app offering Sign in with Apple, so it
   is also a submission risk, not only a correctness one. **Verify end to end
   on a throwaway Apple ID.**

2. **`WebViewController.swift` — blank screen after a web content process
   crash.** `webViewWebContentProcessDidTerminate` called `webView.reload()`.
   If the process died before the first page ever committed, the web view has
   no URL, `reload()` is a no-op, and the app sits on a blank view forever —
   the exact thing that handler exists to prevent. Now calls our own `reload()`,
   which falls back to a fresh `load()`.

3. **`WebViewController.swift` — `openExternally` no longer fails silently.**
   It called `present(safari,…)` unconditionally. Presenting while something
   else is modal fails silently and the link does nothing. It now dismisses
   first. Also changed from `fileprivate` to internal so the bridge can reach
   it — **this is the cross-file visibility change most likely to break the
   build.**

4. **`NativeBridge.swift` — `app.openExternal` was handing arbitrary URL
   schemes straight to the system.** It called `UIApplication.shared.open(url)`
   with whatever the page passed, which both bypassed the in-app Safari sheet
   that tapped links get, and let any script running in the page open any
   scheme. Now allowlisted to http/https/mailto/tel/sms and routed through
   `openExternally` so JS links behave like tapped ones.

## Found and deliberately not changed

**Weight from Apple Health can reach Google Gemini.** `syncBodyMassFromHealth()`
writes the HealthKit body mass into `_userProfile.weight`; `_dressData()` hands
the whole profile to the DRESS prompts; those post to the Gemini worker. Apple's
guideline 5.1.3 permits HealthKit data to be used for health management but not
disclosed to third parties without consent, so this needs to be either
disclosed in the privacy policy or severed. The draft in `PRIVACY.md` discloses
it. Severing it is a one-line change in `_dressData()`. **C.J.'s call, not a
quiet patch** — it changes what the product tells the model.

**A wedged sign-in needs an app restart.** `AuthModule.pendingReply` is set when
a flow starts and cleared only by a delegate callback. If a flow ever ends
without one — the sheet being torn down in an unusual way — every later attempt
returns "A sign-in is already in progress." until the app is killed. There is no
timeout and no reset. In practice `ASAuthorizationController` always calls back,
so this is a latent trap rather than a live bug; the fix (clear `pendingReply`
when the scene goes inactive with no sheet up) needs a judgement call about
where to hook it, so it is left for someone who can test it.

**iPad is in the shipping configuration.** `TARGETED_DEVICE_FAMILY = "1,2"`, so
the app goes to iPad too — where HealthKit is unavailable, the layout is a
single phone-width column, and App Review will test it. Nothing here is built
or tested for iPad. Setting it to `"1"` removes a whole review surface for one
character. Worth doing unless C.J. wants iPad.

**Modulo bias in `AuthModule.randomURLSafeString`.** `alphabet[Int(byte) % 66]`
over a 256-value byte favours the first 58 characters slightly. It feeds the
Apple nonce and the PKCE verifier. At 32 and 64 characters the entropy loss is
nowhere near exploitable, so this is tidiness, not a vulnerability — but
rejection sampling is three lines if someone is in there anyway.

## Checked and fine

Worth recording so nobody re-derives it:

- `UNUserNotificationCenter.delegate` **is** set, in `AppDelegate`, before
  launch finishes — so a notification that launches the app is delivered. This
  was the most likely candidate for "lock-screen taps don't sync the page" and
  it is wired correctly.
- The app icon is a genuine 1024×1024 with no alpha channel, which is what the
  App Store requires. It is soft from upscaling — a quality problem, not a
  rejection one. (`SHIPPING.md` step 6.)
- `ASWebAuthenticationSession` does not need the redirect scheme registered in
  `CFBundleURLTypes`; it intercepts the callback itself. The absence is correct,
  not an oversight.
- `googleRedirectScheme` correctly produces the reversed client ID, and
  `:/oauth2redirect` with a single slash matches Google's convention.
- The entitlements file covers HealthKit (without health-records), Sign in with
  Apple, and time-sensitive notifications — which is what the code uses, and
  nothing more.
- `PrivacyInfo.xcprivacy` matches what the app actually collects.

## Not yet verified on hardware

These cannot be tested in the Simulator and are the reason the native shell
exists at all. All of them need a real iPhone:

- Rest-timer notifications firing while the app is backgrounded or closed,
  including through a Focus mode
- Background audio continuing with the screen locked, and the lock-screen /
  AirPods transport controls
- Headphones unplugged mid-track pausing rather than playing out loud
- Haptics
- HealthKit writing a finished workout and reading body mass back
- Sign in with Apple, including the name arriving only on first authorization
- **Account deletion, including the Apple token revoke that has never once
  worked** — see fix 1

## Quick check that the bridge is alive

Open Settings (gear) in the app and scroll to the bottom. Below the existing
"App" card there should be three cards that only exist in the native build —
**Apple Health**, **Notifications**, **Delete my account** — and a line reading
"Metastory for iPhone 1.0 (1)". If those are there, `window.Metastory` is
injected and the JS-to-Swift bridge is working.

## Still outstanding before submission

- A true 1024×1024 app icon, drawn rather than upscaled. (`SHIPPING.md` step 6.)
- The privacy policy live at metastoryhealth.com/privacy. Draft ready in
  `PRIVACY.md`, with two `[FILL IN]` gaps and one decision for C.J.
- A demo account for App Review with a week of data in it, and the reviewer
  notes. Both planned out in `APP-REVIEW.md` — note the wrinkle that Apple and
  Google are the only sign-in methods, which needs deciding before submission.
- Screenshots at 6.9" and 6.5", taken from the demo account.
