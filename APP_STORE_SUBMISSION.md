# DueProof App Store Submission Notes

This file is the owner-facing submission packet. Keep it aligned with the app code before each upload.

## Current Release Position

DueProof is local-first and does not use a DueProof account, DueProof-operated backend, ads, analytics, tracking, telemetry, crash-reporting SDK, Firebase, Supabase, AWS, Google Cloud, or remote push notification service.

Before App Store review, run:

```sh
Scripts/app_store_preflight.sh --all
```

The command must finish with `0 failure(s)`. Warnings are owner/account/device gates, not code proof.

## Suggested App Store Metadata

Name: DueProof

Subtitle: Receipt & Claim Tracker

Promotional text: Keep proof, deadlines, and claim details organized privately on your iPhone.

Description:

DueProof helps you track returns, warranties, gift cards, reimbursements, rebates, renewals, subscriptions, and other claim deadlines.

Keep proof photos, receipts, reference numbers, action links, notes, and reminders together so you can act before a deadline slips by.

Privacy is built into the product:

- No DueProof account.
- No DueProof-operated backend.
- No ads.
- No analytics.
- No tracking.
- Local storage by default.
- Optional private iCloud sync controlled by you.
- Optional Face ID, Touch ID, or passcode app lock.

Smart Fill uses on-device text recognition to suggest claim details from proof photos. You review suggestions before saving.

DueProof does not file claims for you, guarantee reimbursement, or replace merchant, employer, insurer, government, or legal deadlines. Always verify important deadlines and requirements before acting.

Keywords:

receipt, returns, warranty, gift card, reimbursement, rebate, renewal, subscription, reminder, deadline, proof, tracker

Category:

Productivity

## Suggested Review Notes

DueProof does not require an account. The app opens directly to the local dashboard.

Core review path:

1. Add a claim from the dashboard.
2. Add a proof photo with the camera or photo picker.
3. Review Smart Fill suggestions before saving.
4. Schedule a local reminder.
5. Open Settings to review privacy, export, iCloud sync, App Lock, and clear-data controls.

Optional iCloud Sync uses the user's private CloudKit database and applies after relaunch. App Lock requires Face ID, Touch ID, or device passcode. Notifications are local reminders only.

## Privacy Answers Draft

Tracking: No.

Data used to track the user: None.

Data linked to the user by DueProof: None.

Data collected by DueProof: None.

Third-party advertising: None.

Analytics: None.

Crash reporting SDK: None.

Account creation: None.

Developer-operated server storage: None.

Optional iCloud Sync: The app can store claim data and proof files in the user's private iCloud database when the user enables iCloud Sync. DueProof does not operate that backend and does not receive the data.

Owner must verify the final App Store Connect privacy questionnaire against the current App Store Connect wording before submission.

## Required Public URLs

These cannot be satisfied by local files. The owner must host and enter:

- Privacy Policy URL.
- Support URL.

The hosted privacy policy should be based on `PRIVACY.md` and must not claim system-level backups, end-to-end encryption, regulated compliance, or guaranteed reimbursement.

## Owner Gates

- Apple Developer agreements, tax, and banking are complete.
- App ID has App Groups and iCloud container capabilities configured.
- Bundle IDs match `com.hardik.dueproof`, `com.hardik.dueproof.widget`, and `com.hardik.dueproof.share`.
- App Group `group.com.hardik.dueproof` exists for all relevant targets.
- iCloud container `iCloud.com.hardik.dueproof` exists and is attached to the app.
- Full Xcode is installed and selected.
- Clean build, tests, archive, and validation pass.
- Physical-device QA passes for camera, Photos picker, Face ID/passcode, notifications, iCloud sync, widget, share extension, import/export, and clear data.
- Screenshots and optional app preview are captured from the final build.
- Age rating, export compliance, pricing, availability, copyright, and contact info are final.
