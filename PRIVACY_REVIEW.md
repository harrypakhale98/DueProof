# DueProof Privacy Review

## Verdict

DueProof remains local-first. The app does not use a DueProof-operated backend, DueProof accounts, analytics, ads, tracking, telemetry, crash-reporting SDKs, Firebase, Supabase, AWS, Google Cloud, or remote push notifications. Optional iCloud Sync uses the user's private CloudKit database when enabled.

DueProof does not upload your data to our servers.

## Local Storage Behavior

- Claim details are stored with SwiftData on device by default.
- Proof photos are copied into DueProof's local app storage.
- SwiftData stores local proof file references; proof file bytes live in protected local app storage and are included in complete user-initiated exports when available.
- Optional iCloud Sync uses the user's private CloudKit database and mirrors proof file bytes for that user's devices when enabled.
- Complete JSON export includes claim details, proof metadata, and locally stored proof file data when available.
- Local notifications are used only for reminders the user enables.
- Calendar export creates a local `.ics` file for native sharing.
- Smart Fill uses on-device text and barcode recognition through Apple Vision.
- When available, Smart Fill can use Apple's on-device Foundation Models framework to suggest claim details.
- Smart Fill falls back to deterministic local parsing when on-device intelligence is unavailable.
- Smart Fill does not save a claim until the user reviews and confirms the suggested fields.

## Known Privacy Limits

- This review does not claim system-level backups are disabled.
- This review does not claim end-to-end encryption.
- This review does not claim Apple cannot access device-level data.
- This review does not claim regulated compliance certifications.
- This review does not claim iCloud Sync is active unless the user enables it.

## Static Search Terms

Release scans should check: URLSession, URLRequest, http, https, Firebase, Supabase, CloudKit, iCloud, AWS, Google, Analytics, Telemetry, Tracking, Amplitude, Mixpanel, Sentry, Crashlytics, Segment, AdMob, Ads.

Expected benign matches are privacy documentation, App Store copy, SwiftData `fetch` calls, CloudKit entitlements, and optional private CloudKit configuration. There should be no app code that performs direct network transmission to DueProof servers or installs tracking SDKs.
