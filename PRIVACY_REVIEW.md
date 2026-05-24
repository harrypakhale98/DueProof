# DueProof Privacy Review

## Verdict

DueProof remains local-first. The app does not use a backend, accounts, analytics, ads, tracking, telemetry, crash-reporting SDKs, Firebase, Supabase, CloudKit, iCloud storage code, AWS, Google Cloud, or any app-level network dependency.

DueProof does not upload your data to our servers.

## Local Storage Behavior

- Claim details are stored with SwiftData on device.
- Proof photos are copied into DueProof's local app storage.
- SwiftData stores local proof file references; proof file bytes live in protected local app storage and are included in complete user-initiated exports when available.
- Complete JSON export includes claim details, proof metadata, and locally stored proof file data when available.
- Local notifications are used only for reminders the user enables.
- Calendar export creates a local `.ics` file for native sharing.
- Smart Fill uses on-device text recognition through Apple Vision.
- When available, Smart Fill can use Apple's on-device Foundation Models framework to suggest claim details.
- Smart Fill falls back to deterministic local parsing when on-device intelligence is unavailable.
- Smart Fill does not save a claim until the user reviews and confirms the suggested fields.

## Known Privacy Limits

- This review does not claim system-level backups are disabled.
- This review does not claim end-to-end encryption.
- This review does not claim Apple cannot access device-level data.
- This review does not claim regulated compliance certifications.

## Static Search Terms

Release scans should check: URLSession, URLRequest, http, https, Firebase, Supabase, CloudKit, iCloud, AWS, Google, Analytics, Telemetry, Tracking, Amplitude, Mixpanel, Sentry, Crashlytics, Segment, AdMob, Ads.

Expected benign matches are privacy documentation, App Store copy, and SwiftData `fetch` calls. There should be no app code that performs network transmission or installs tracking/cloud SDKs.
