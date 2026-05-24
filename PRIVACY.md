# DueProof Privacy

DueProof is designed as a local-first iOS app.

## What DueProof Does Not Use

- No account.
- No backend.
- No ads.
- No analytics.
- No tracking.
- No telemetry.
- No remote push notification service.

DueProof does not upload your data to our servers.

## Local Data

Claim details are stored locally on this device with SwiftData. Proof files are copied into DueProof's local app storage and referenced by local file name.

Local notifications are used only for reminders the user enables.

Smart Fill uses on-device text recognition. When available, DueProof uses Apple's on-device intelligence to suggest claim details. Proof is not uploaded to DueProof servers, and the user reviews suggestions before saving.

## Export and Deletion

The user controls export and deletion. Complete JSON export includes claim details and locally stored proof file data when available.

Do not claim that system-level backups are disabled unless backup exclusion is explicitly implemented and verified.
