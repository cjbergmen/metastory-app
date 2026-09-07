# Metastory Health for iOS

A native shell around the Metastory web app. The web app is still the
product — this repo's `index.html` — and it still ships by pushing to
`main`. The shell exists to provide the four things a browser can't do on
iOS, and to put Metastory on the App Store.

**To ship it, follow [SHIPPING.md](SHIPPING.md).** This file is the
map of how it works.

## Opening it

```
open ios/MetastoryHealth.xcodeproj
```

Xcode 16 or newer, iOS 16.0 and up. No CocoaPods, no Swift Package
Manager, no `pod install` — every framework it uses ships with iOS.

Set your team in **Signing & Capabilities** before the first build; the
project leaves `DEVELOPMENT_TEAM` blank on purpose so it isn't tied to one
account.

## How it fits together

```
app.metastoryhealth.com  ──loads into──▶  WKWebView
        ▲                                     │
        │                            window.Metastory
        │                                     │
        └──── the web app calls ──────────────┘
                                              │
                             ┌────────────────┼────────────────┐
                             ▼                ▼                ▼
                        timers            audio            health
                        haptics           auth
```

The shell loads the live site rather than bundling a copy, so content
updates reach people the moment you push — no App Store review in the
loop. The persistent `WKWebsiteDataStore` means the Firebase session and
every local log survive between launches, exactly as they do in the PWA.

`bridge.js` is injected at document start and defines `window.Metastory`.
Everything goes through a single message handler that returns real
promises, so the page can `await` a Health query or a sign-in.

| File | What it does |
|---|---|
| `App/AppConfig.swift` | Every configurable value: the URL, the hosts that stay in-app, the Google client ID |
| `App/WebViewController.swift` | The web view, offline state, external links, JS dialogs |
| `Bridge/NativeBridge.swift` | Routes `window.Metastory` calls to the modules |
| `Resources/bridge.js` | The JavaScript side of that contract |
| `Modules/NotificationsModule.swift` | Rest timers as local notifications |
| `Modules/AudioModule.swift` | Audio session, lock screen, AirPods |
| `Modules/HapticsModule.swift` | Impact, selection and notification feedback |
| `Modules/HealthKitModule.swift` | Workouts out, weight and steps in |
| `Modules/AuthModule.swift` | Sign in with Apple, and Google via `ASWebAuthenticationSession` |

The web side lives in one block at the end of `index.html`, marked
`NATIVE iOS ADAPTER`. It returns immediately when `window.Metastory` is
undefined, which is every browser and every home-screen PWA install.

## Why sign-in is native

Google refuses to serve its OAuth pages inside an embedded web view — you
get `disallowed_useragent` — so `signInWithPopup` and `signInWithRedirect`
both dead-end in a wrapped app. `ASWebAuthenticationSession` runs the flow
in a real Safari context, which Google does allow. The native side hands a
token back to the page, and the Firebase SDK already loaded there turns it
into a session. No Firebase dependency is linked natively.

Sign in with Apple is there for the same practical reason and one policy
one: App Review guideline 4.8 requires it wherever Google sign-in is
offered.

## Why the page still owns audio playback

The player in `index.html` does a crossfade, a Web Audio prosody filter and
listening-time logging. Reimplementing that natively would be a rewrite
with nothing to show for it. What the page genuinely can't do is keep sound
coming once iOS suspends the web view, or put controls on the lock screen.
So `AudioModule` owns the audio session and the Now Playing centre, and
routes the hardware buttons back into the page's own `musToggle`, `musNext`
and `musPrev`.

## Changing the web app

Nothing in `ios/` needs to change. Edit `index.html`, bump `APP_BUILD` and
the matching `VERSION` in `sw.js`, push. People see it on next launch.

You only need a new App Store build when something in `ios/` changes.
