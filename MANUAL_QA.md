# DueProof Manual QA

Run this checklist on a clean simulator and again on a physical device before release.

## Core Checklist

- [ ] Launch app with no data.
- [ ] Add a return claim.
- [ ] Add a gift card claim.
- [ ] Add a warranty claim with $0 value.
- [ ] Add a claim with no deadline.
- [ ] Add proof photo.
- [ ] Relaunch app and verify data persists.
- [ ] Edit title/value/deadline.
- [ ] Schedule reminder.
- [ ] Change reminder date.
- [ ] Complete claim by marking it recovered.
- [ ] Complete claim by marking it used.
- [ ] Mark claim as expired.
- [ ] Delete a claim.
- [ ] Confirm dashboard metrics update.
- [ ] Export JSON.
- [ ] Import JSON.
- [ ] Try malformed JSON.
- [ ] Export calendar file.
- [ ] Test light mode.
- [ ] Test dark mode.
- [ ] Test large text.
- [ ] Test VoiceOver basics.
- [ ] Test small iPhone layout.
- [ ] Test large iPhone layout.

## Privacy and Reliability Checks

- [ ] Confirm notification permission is requested only when saving or adding a reminder.
- [ ] Confirm deleting a claim removes any associated proof photo files.
- [ ] Confirm proof thumbnails do not crash if the local file is missing.
- [ ] Confirm complete export copy says proof files are included and should be reviewed before sharing.
- [ ] Confirm Privacy screen states no account, no cloud backend, no ads, no analytics, no tracking, local proof photos, user-controlled export/deletion, and local notifications.
