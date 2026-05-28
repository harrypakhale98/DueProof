# DueProof Privacy

DueProof is designed as a local-first iOS app.

## What DueProof Does Not Use

- No DueProof account.
- No DueProof-operated backend.
- No ads.
- No analytics.
- No tracking.
- No telemetry.
- No remote push notification service.

DueProof does not upload your data to our servers.

## Local Data

Claim details are stored locally on this device with SwiftData by default. Proof files are copied into DueProof's protected app storage and referenced by local file name.

Optional iCloud Sync uses the user's private iCloud database. DueProof does not run its own sync server or receive the user's claim data.

Optional App Lock uses device authentication to hide claim details and proof behind Face ID, Touch ID, or the device passcode when enabled. DueProof does not receive biometric data.

System Spotlight search for claim details is off by default and must be enabled by the user. DueProof clears Spotlight entries and disables the setting while App Lock is enabled so private claim details do not appear outside the app.

Local notifications are used only for reminders the user enables.

Smart Fill uses on-device text recognition, including visible text and machine-readable identifiers such as barcodes when iOS can detect them. When available, DueProof uses Apple's on-device intelligence to suggest claim details. Proof is not uploaded to DueProof servers, and the user reviews suggestions before saving.

## Export and Deletion

The user controls export and deletion. Complete JSON export includes claim details and locally stored proof file data when available.

Do not claim that system-level backups are disabled unless backup exclusion is explicitly implemented and verified.
