# DueProof

DueProof helps you track returns, warranties, gift cards, reimbursements, renewals, and other claim deadlines privately on your device.

Suggested App Store subtitle: Receipt & Claim Tracker

Suggested tagline: Keep proof. Beat deadlines.

Version placeholder: 1.0

## Privacy Summary

DueProof does not use a DueProof account, ads, analytics, tracking, or a DueProof-operated backend. Claim details and proof photos are stored locally by default, with optional private iCloud sync controlled by the user.

DueProof does not upload your data to our servers. Claim data is stored with SwiftData, proof photos are copied into the app's protected storage, optional iCloud sync uses the user's private CloudKit database, and reminders use local notifications only when the user enables them.

## Local-First Architecture

- SwiftUI app lifecycle.
- SwiftData for claim and proof metadata persistence.
- Local file storage for proof photos.
- Optional private CloudKit sync through the user's iCloud account.
- UserNotifications for local reminders.
- ShareLink and local file generation for JSON and calendar exports.
- No Firebase, Supabase, AWS, Google Cloud, DueProof-hosted database, analytics SDK, ad SDK, crash-reporting SDK, remote push notification service, or DueProof account system.

## Run Instructions

Open the project in Xcode:

```sh
open DueProof.xcodeproj
```

Build from Terminal:

```sh
xcodebuild -project DueProof.xcodeproj -scheme DueProof -destination 'generic/platform=iOS Simulator' build
```

Run tests:

```sh
xcodebuild test -project DueProof.xcodeproj -scheme DueProof -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Import and Export

JSON export includes claim details, dates, status, values, notes, proof metadata, and locally stored proof file data when available.

Export includes claim details and proof data. Import skips missing local proof-file references so restored claims do not point at unavailable photos.

## Known Limitations

- Optional iCloud sync applies after the next app launch and depends on the user's iCloud availability.
- Extremely large proof archives may be rejected during import to protect app responsiveness.
- Notification delivery depends on iOS notification settings, Focus, and system scheduling behavior.
- Calendar export requires a claim deadline.
- The current app icon uses 1024px light and dark receipt-logo assets with neutral backgrounds and a larger pastel blue/mint receipt; final iOS 26 layered variants should be designer-reviewed before App Store submission if the release pipeline supports them.
- App Store metadata, screenshots, privacy nutrition labels, and final legal text still need owner review before submission.

## Manual QA

Use [MANUAL_QA.md](MANUAL_QA.md) before TestFlight or App Store submission.

Also review [PRIVACY.md](PRIVACY.md) and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

For award-readiness and editorial preparation, review [DESIGN_THESIS.md](DESIGN_THESIS.md), [ACCESSIBILITY_AUDIT.md](ACCESSIBILITY_AUDIT.md), [PRIVACY_REVIEW.md](PRIVACY_REVIEW.md), [APP_STORE_AWARD_PACKAGE.md](APP_STORE_AWARD_PACKAGE.md), [AWARD_QA_SCORECARD.md](AWARD_QA_SCORECARD.md), and [USER_TESTING_SCRIPT.md](USER_TESTING_SCRIPT.md).
