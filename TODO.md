# Project TODOs (consolidated)

> This file consolidates all TODO / FIXME / XXX notes found across the repository (code, controllers, services, webhooks, payments, and tests). Items include the original hint location (file), a short description, suggested next steps, and a priority.

---

## How to use
- Read item descriptions and attach to an issue or PR. Prefer small, testable changes.
- Label priorities: **P0** (critical/security/regressions), **P1** (important), **P2** (nice-to-have/cleanup).
- If you implement a TODO, remove the in-code TODO and update this file. There is also issues on Github regarding each TODO. Please ensure to leave a comment on the issue linking to your PR/Commit for auditing

---

## High-priority / Security (P0)

- **Enforce Host header & wildcard subdomains**
  - Files: `lib/security.rb`
  - Description: Implement support for wildcard subdomains in `ALLOWED_HOSTS` and require a Host header for all requests in production.
  - Next steps: add validation middleware, tests for host header behavior, document deploy-time configuration.

- **Webhook signature verification & verification improvements (partial)**
  - Files: `lib/webhooks/paypal_webhook_handler.rb`, `lib/webhooks/stripe/payment_event_handler.rb`
  - Description: PayPal webhook verification implemented using the `verify-webhook-signature` API, plus simple replay protection (file-backed transmission id storage). Stripe catalog sync still outstanding.
  - Next steps: add unit/integration tests and e2e webhook tests, enhance replay protection (use DB), add signature validation reporting and implement Stripe product/price catalog sync.

- **Audit logging for license actions**
  - Files: `lib/license_generator.rb` (note: TODO at line implementing proper separate audit logging mechanism)
  - Description: Implement separate, tamper-resistant audit logs for license generation/changes.
  - Next steps: evaluate logging backend, add structured audit events and tests.

---

## Payments (P0/P1)

- **Remove debug puts and centralize payment logging**
  - Files: `lib/payments/base_payment_processor.rb`
  - Description: Remove `puts` debug lines and implement a consistent logging approach per processor.
  - Next steps: replace `puts` with structured logger, add tests.

- **Refactor PayPal integration to use webhooks & add missing features (in progress)**
  - Files: `lib/payments/paypal_processor.rb`, `lib/webhooks/paypal_webhook_handler.rb`
  - Description: Webhook-first processing and signature verification implemented; subscription creation/cancel flow improved; added idempotency headers and structured logging. Remaining work: comprehensive tests, retry/backoff, rate limiting, PayPal Vault support, PCI compliance and documentation.
  - Next steps: add unit & e2e webhook tests, implement retry strategies, store webhook events and processed ids in DB, and finalize PCI scope documentation.

- **Stripe improvements**
  - Files: `lib/payments/stripe_processor.rb`, `lib/webhooks/stripe/payment_event_handler.rb`
  - Description: Add logging for actions, webhook abstraction layer, support for 3DS, Apple/Google Pay, and payment method tokenization if needed.
  - Next steps: implement webhook abstraction, add integration tests and simulate 3DS flows.

---

## Webhooks & Catalog (P1)

- **Product/price catalog sync with provider**
  - Files: `lib/webhooks/stripe/payment_event_handler.rb` (TODO about reading products at launch)
  - Description: maintain a catalog of Stripe prices and products either at launch or when updated, to avoid relying solely on event payloads.
  - Next steps: implement sync job and caching, add tests.

- **PayPal signature verification (implemented, tests required)**
  - Files: `lib/webhooks/paypal_webhook_handler.rb`
  - Description: Server now verifies signatures using PayPal `/v1/notifications/verify-webhook-signature` API and includes simple replay protection; add tests for invalid signatures, replay attacks, and monitoring/reporting.

---

## Licensing & Generator (P1)

- **Audit & logging around license generation**
  - Files: `lib/license_generator.rb`
  - Description: Improve audit trail for license creation, rotations, and revocation. Consider storing cryptographic hashes of key events.
  - Next steps: add tests, add separate audit logger, document retention policy.

- **License format documentation & validation**
  - Files: `lib/license_generator.rb` (commented formats)
  - Description: Clarify supported license formats and make format selection explicit via configuration/parameter validation.

---

## Sessions & Security Signals (P1)

- **Geolocation & threat-intel integration for sessions**
  - Files: `lib/auth/session_manager.rb`
  - Description: Replace TODOs referencing MaxMind and threat intel with configurable integrations; add tests and fallbacks.
  - Next steps: add configuration, use an interface for geolocation provider and feed ingestion, mock in tests.

---

## Logging, Error Handling & Observability (P1)

- **Centralize and improve error logging**
  - Files: `lib/payments/*`, `lib/webhooks/*`, `lib/services/*`
  - Description: Replace ad-hoc logging and `puts` statements with structured, centralized logging and correlation IDs for requests and webhook events.

- **Implement retry/backoff & idempotency where appropriate**
  - Files: `lib/payments/*`, external API calls
  - Description: Add retry strategies and idempotency keys to avoid duplicate operations on retries.

---

## Tests & CI (P0/P1)

- **Add tests for payment processors & webhooks**
  - Files: `lib/payments/*`, `lib/webhooks/*`, tests under `test/`
  - Description: Many TODOs mention missing unit and integration tests (PayPal, Stripe). Add scoped tests that simulate provider events and error conditions.

- **Add e2e webhook replay and signature tests**
  - Files: `test/webhook_test.rb` and new test helpers
  - Description: Verify behavior on replayed events, invalid signatures, and partial payloads.

---

## Documentation & Developer Experience (P2)

- **Document methods and public classes**
  - Files: `lib/payments/paypal_processor.rb` and others
  - Description: Add missing documentation, usage examples, and clarify expected behavior and return types.

- **CDN for static assets**
  - Files: `lib/helpers/template_helpers.rb` (TODO: use a CDN)
  - Description: Add configuration to serve static assets via CDN and tests for template helpers.

---

## SDKs, Vendor Code & Cleanups (P2)

- **Remove or isolate venv/vendor TODOs from SDKs**
  - Files: `SL_SDKS/*`, `source_license_sdk/venv/*`
  - Description: many vendor files contain TODO/FIXME (pip/setuptools/etc.). These are third-party and not actionable here; ensure SDKs are updated rather than editing vendored dependencies. Remove vendored virtualenv from repository if not needed.
  - Next steps: audit `SL_SDKS` for unnecessary vendored packages and add .gitignore entries / packaging instructions.

---

## Miscellaneous / Housekeeping (P2)

- **Implement production checks for secure license service**
  - Files: `lib/services/secure_license_service.rb` (TODO about refusing fallback in prod)
  - Description: Ensure service fails loudly in production rather than silently falling back.

- **Add rate limiting, advanced fraud protection, localization notes**
  - Files: `lib/payments/paypal_processor.rb`, `lib/payments/stripe_processor.rb`
  - Description: Several TODOs mention rate limiting, fraud protection, currency/localization and 3DS.

- **Add code comments & remove leftover debug statements**
  - Files: `deploy.sh` (some debug logs), `lib/payments/*`
  - Description: Clean up noisy logging and ensure debug logs gated behind flags.

---

## Appendix: Exact TODO sources (abridged)
- `lib/auth/session_manager.rb`: geolocation, threat intel (TODOs)
- `lib/helpers/template_helpers.rb`: use a CDN (TODO)
- `lib/payments/base_payment_processor.rb`: debug logging `puts` (TODO)
- `lib/payments/paypal_processor.rb`: many TODOs (refactor to webhooks, add subscriptions, tests, error handling, idempotency, PCI)
- `lib/payments/stripe_processor.rb`: logging, 3DS, Apple/Google Pay, webhook abstraction
- `lib/services/secure_license_service.rb`: production fallback behavior
- `lib/webhooks/stripe/payment_event_handler.rb`: product/price catalog sync
- `lib/webhooks/paypal_webhook_handler.rb`: signature verification
- `lib/license_generator.rb`: audit logging
- `lib/security.rb`: wildcard subdomain & host header

---

## Issue Links

- Enforce Host header & wildcard subdomains — https://github.com/LyrinoxTechnologies/Source-License/issues/62 (P0)
- Webhook signature verification and replay protection (PayPal & Stripe) — https://github.com/LyrinoxTechnologies/Source-License/issues/63 (P0)
- Implement tamper-resistant audit logging for license operations — https://github.com/LyrinoxTechnologies/Source-License/issues/64 (P0)
- Add unit & integration tests for payment processors and webhooks — https://github.com/LyrinoxTechnologies/Source-License/issues/65 (P0)
- Remove debug 'puts' and centralize payment logging — https://github.com/LyrinoxTechnologies/Source-License/issues/66 (P1)
- Refactor PayPal integration to webhook-driven flow & add subscription management — https://github.com/LyrinoxTechnologies/Source-License/issues/67 (P1)
- Stripe: logging, webhook abstraction, and 3DS/Wallet support — https://github.com/LyrinoxTechnologies/Source-License/issues/68 (P1)
- Product/price catalog sync with Stripe — https://github.com/LyrinoxTechnologies/Source-License/issues/69 (P1)
- PayPal: implement proper signature verification & tests — https://github.com/LyrinoxTechnologies/Source-License/issues/70 (P1)
- License format documentation & validation — https://github.com/LyrinoxTechnologies/Source-License/issues/71 (P1)
- Add geolocation & threat-intel integration for session management — https://github.com/LyrinoxTechnologies/Source-License/issues/72 (P1)
- Centralize error logging and add correlation IDs — https://github.com/LyrinoxTechnologies/Source-License/issues/73 (P1)
- Implement retry/backoff and idempotency for external API calls — https://github.com/LyrinoxTechnologies/Source-License/issues/74 (P1)
- Add e2e webhook replay and signature tests — https://github.com/LyrinoxTechnologies/Source-License/issues/75 (P1)

_Last updated: 24 Dec 2025._
