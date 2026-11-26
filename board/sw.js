// The CTF board, offline. A scanned link must open in a hall with no signal,
// so the page and its icons are served from the cache first, and refreshed
// from the network behind the scenes when there is one. publish_updates.ps1
// stamps the version, so each release starts a fresh cache.
var CACHE = "dc35-ctf-board-1.0.56";
var SHELL = ["./", "manifest.webmanifest", "icon-180.png", "icon-192.png", "icon-512.png"];
var FONTS = /^https:\/\/fonts\.(googleapis|gstatic)\.com\//;

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) { return c.addAll(SHELL); }));
  self.skipWaiting();
});

self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) {
      return k.indexOf("dc35-ctf-board-") === 0 && k !== CACHE;
    }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  var same = url.origin === self.location.origin;
  if (!same && !FONTS.test(req.url)) return;
  // Every visit to the page is the page, whatever came after the '#' or '?'.
  var key = req.mode === "navigate" ? "./" : req;
  e.respondWith(caches.open(CACHE).then(function (c) {
    return c.match(key).then(function (hit) {
      var net = fetch(req).then(function (res) {
        if (res && (res.ok || res.type === "opaque")) c.put(key, res.clone());
        return res;
      }).catch(function () { return hit; });
      if (hit) { e.waitUntil(net); return hit; }
      return net;
    });
  }));
});
