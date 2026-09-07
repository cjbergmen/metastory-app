// window.Metastory — the web app's view of the native container.
//
// Injected at document start by WebViewController, so the page's own scripts
// can check for it synchronously. Everything here is a thin wrapper over one
// message handler; the real work happens in NativeBridge.swift.
//
// Nothing in the web app may *depend* on this object existing — the same
// index.html is served to browsers, where `window.Metastory` is undefined and
// the PWA code paths take over.
(function () {
  'use strict';

  if (window.Metastory) { return; }

  var handler = window.webkit
    && window.webkit.messageHandlers
    && window.webkit.messageHandlers.metastory;

  if (!handler) { return; }

  var listeners = Object.create(null);

  function call(module, action, payload) {
    try {
      return handler.postMessage({
        module: module,
        action: action,
        payload: payload || {}
      });
    } catch (e) {
      return Promise.reject(e);
    }
  }

  // Fire-and-forget: haptics and now-playing updates are called from hot paths
  // (every logged set, every timeupdate) and a rejected promise nobody catches
  // would spam the console.
  function post(module, action, payload) {
    call(module, action, payload).catch(function () {});
  }

  var Metastory = {
    isNative: true,
    platform: 'ios',
    version: '__APP_VERSION__',
    build: '__APP_BUILD__',

    call: call,

    // ── events from native ────────────────────────────────────────────────
    // Also dispatched on window as `metastory:<event>` for code that prefers
    // addEventListener.
    on: function (event, fn) {
      (listeners[event] || (listeners[event] = [])).push(fn);
      return function () { Metastory.off(event, fn); };
    },

    off: function (event, fn) {
      var list = listeners[event];
      if (!list) { return; }
      var i = list.indexOf(fn);
      if (i >= 0) { list.splice(i, 1); }
    },

    _emit: function (event, payload) {
      var list = listeners[event] || [];
      for (var i = 0; i < list.length; i++) {
        try { list[i](payload); } catch (e) {}
      }
      try {
        window.dispatchEvent(new CustomEvent('metastory:' + event, { detail: payload }));
      } catch (e) {}
    },

    // ── haptics ───────────────────────────────────────────────────────────
    haptics: {
      // style: 'light' | 'medium' | 'heavy' | 'soft' | 'rigid'
      impact: function (style) { post('haptics', 'impact', { style: style || 'medium' }); },
      selection: function () { post('haptics', 'selection', {}); },
      // type: 'success' | 'warning' | 'error'
      notify: function (type) { post('haptics', 'notification', { type: type || 'success' }); }
    },

    // ── rest-timer notifications ──────────────────────────────────────────
    // These are real local notifications, so they fire on the lock screen with
    // sound even after iOS has suspended the web view.
    timers: {
      requestPermission: function () { return call('timers', 'requestPermission', {}); },
      permission: function () { return call('timers', 'permission', {}); },
      // seconds from now; `id` lets several timers coexist.
      schedule: function (options) {
        return call('timers', 'schedule', {
          id: (options && options.id) || 'rest',
          seconds: (options && options.seconds) || 0,
          title: (options && options.title) || 'Rest Over',
          body: (options && options.body) || 'Time to get back to it.'
        });
      },
      cancel: function (id) { return call('timers', 'cancel', { id: id || 'rest' }); },
      cancelAll: function () { return call('timers', 'cancelAll', {}); }
    },

    // ── lock-screen / AirPods transport ───────────────────────────────────
    // The page keeps playing the audio itself; this only mirrors what's
    // playing into the Now Playing panel and routes the hardware buttons back.
    // Listen for `metastory:remote-command` with detail {command, position}.
    nowPlaying: {
      set: function (info) { post('audio', 'setNowPlaying', info || {}); },
      state: function (isPlaying, position, duration) {
        post('audio', 'setPlaybackState', {
          playing: !!isPlaying,
          position: position || 0,
          duration: duration || 0
        });
      },
      clear: function () { post('audio', 'clearNowPlaying', {}); }
    },

    audio: {
      // Take the audio session so playback survives the screen locking.
      activate: function () { return call('audio', 'activateSession', {}); },
      release: function () { return call('audio', 'deactivateSession', {}); }
    },

    // ── Apple Health ──────────────────────────────────────────────────────
    health: {
      isAvailable: function () { return call('health', 'isAvailable', {}); },
      requestAuthorization: function () { return call('health', 'requestAuthorization', {}); },
      status: function () { return call('health', 'status', {}); },
      // { start: ms, end: ms, activity: 'traditionalStrengthTraining'|..., calories: kcal }
      saveWorkout: function (workout) { return call('health', 'saveWorkout', workout || {}); },
      latestBodyMass: function () { return call('health', 'latestBodyMass', {}); },
      stepsToday: function () { return call('health', 'stepsToday', {}); }
    },

    // ── sign-in ───────────────────────────────────────────────────────────
    // Resolves with the credential the page hands to Firebase. Google's OAuth
    // pages refuse to load in an embedded web view, so both providers run
    // natively and the token comes back here.
    auth: {
      apple: function () { return call('auth', 'signInWithApple', {}); },
      google: function () { return call('auth', 'signInWithGoogle', {}); },
      isGoogleConfigured: function () { return call('auth', 'isGoogleConfigured', {}); }
    },

    // ── misc ──────────────────────────────────────────────────────────────
    app: {
      openSettings: function () { return call('app', 'openSettings', {}); },
      openExternal: function (url) { return call('app', 'openExternal', { url: url }); }
    }
  };

  window.Metastory = Metastory;
})();
