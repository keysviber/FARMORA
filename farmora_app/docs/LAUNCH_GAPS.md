# Launch gaps and validation boundaries

## External setup required

- A selected Firebase project, billing, Auth providers, deployed rules/indexes/functions and native Firebase app configuration.
- App Check registrations/debug tokens and production enforcement verification.
- Permanent application IDs, Android upload signing, Apple signing/APNs and physical Android/iOS testing.
- Server Google Routes key and billing/restrictions; merchant accounts and signed payment webhook adapters if automated payments are required.
- Approved terms/privacy, operator identity, support contact, retention schedule and cancellation/refund policy. Current legal copy is visibly a development draft.
- Admin account claims and controlled hosting; no deployment has been performed.

## Remaining product work (not merely credentials)

- Private business-document verification, avatar uploads and delivery-address book. Google and phone providers require their respective configuration and device tests.
- Chat image attachments, richer product/quote cards, cross-role order conversations and rendered read receipts.
- Failed-delivery retry/reassignment workflow and complete driver earnings views. Private proof uploads, driver acceptance and failed-delivery reporting are implemented; device testing is pending.
- Supplier/customer discovery ranking, featured suppliers, saved suppliers, geographic service-area matching, configurable currencies and category management UI.
- Complete notification coverage for matched requests, saved-product price changes, verification changes, background handling and notification deep links.
- Full application widget/integration coverage for each platform, offline queue behavior, accessibility/visual QA, routing quotas and abuse protections.
- Orphaned image cleanup and settlement/refund edge-case review before production. Account deletion now uses a retryable server job.

The implemented marketplace/search queries are paginated, but text search filters loaded results. It is not a global full-text search engine. Platform document/query limits and retained historical records must be included in production scale testing.

Do not describe source compilation or emulator tests as hosted integration, push delivery, route-provider billing, settlement, physical-device UX or store readiness.

## Dependency audit

The deployed Functions dependency tree passes npm audit --omit=dev after upgrading firebase-admin and firebase-functions. The Firebase CLI/test-tool dependency tree still reports transitive advisories; these development tools are not part of the deployed Functions runtime. Review upstream fixes before CI/production tooling rollout.

