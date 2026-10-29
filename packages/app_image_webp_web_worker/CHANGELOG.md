## 0.1.0

- Initial version: `WebpWorker` (WebP encoding of tekartik_app_image_webp in
  a web worker, an isolate on io, main thread fallback when the worker
  script is missing), `webpWorker` (the default one, used by
  tekartik_app_image_web on Safari), `setupWebpWorker` and
  `dart run tekartik_app_image_webp_web_worker:setup` building
  `web/webp_worker.js` (with tekartik_web_worker_build: rebuilt only when the
  Dart SDK or a package of the worker changed).
