# DueProof Manual QA

Run this checklist on a clean simulator and again on a physical device before release.

## Core Checklist

- [ ] Launch app with no data.
- [ ] Add a return claim.
- [ ] Add a gift card claim.
- [ ] Add a warranty claim with $0 value.
- [ ] Add a claim with no deadline.
- [ ] Add proof photo.
- [ ] Add a large camera photo and confirm DueProof stays responsive while creating the proof.
- [ ] Try importing an oversized proof file and confirm DueProof rejects it without adding a claim or proof.
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
- [ ] Export CSV with a claim title beginning with `=` and confirm the report opens as text, not a spreadsheet formula.
- [ ] Share a photo or PDF into DueProof from another app and confirm one claim is created with the expected proof.
- [ ] Try sharing an oversized photo or PDF into DueProof and confirm it is rejected without leaving an empty pending import.
- [ ] Try malformed JSON.
- [ ] Try entering `inf`, `nan`, and an extremely long action link in Add/Edit and confirm they cannot save invalid data.
- [ ] Export calendar file.
- [ ] Export a calendar file from a long claim title with punctuation/newlines/non-ASCII text and confirm it imports as one event.
- [ ] Test light mode.
- [ ] Test dark mode.
- [ ] Test large text.
- [ ] Test VoiceOver basics.
- [ ] Test small iPhone layout.
- [ ] Test large iPhone layout.
- [ ] Turn Spotlight search on, confirm expected claim results appear, then turn App Lock on and confirm Spotlight results are cleared.

## Privacy and Reliability Checks

- [ ] Confirm notification permission is requested only when saving or adding a reminder.
- [ ] Confirm deleting a claim removes any associated proof photo files.
- [ ] Confirm proof thumbnails do not crash if the local file is missing.
- [ ] Simulate a failed save if possible and confirm the edited claim/proof state is restored instead of showing unsaved changes.
- [ ] Confirm complete export copy says proof files are included and should be reviewed before sharing.
- [ ] Cancel or fail a share-extension import, relaunch DueProof, and confirm no empty claim or stale pending import appears.
- [ ] Open a malformed shared-import URL and confirm it does not import unrelated pending shared items.
- [ ] Confirm Privacy screen states no DueProof account, no DueProof-operated backend, optional private iCloud sync, no ads, no analytics, no tracking, local proof photos, user-controlled export/deletion, and local notifications.
- [ ] Confirm Clear All Data removes pending share-extension imports, generated export files, and any external private surfaces such as Spotlight and widgets.
- [ ] With App Lock enabled, confirm the widget stays locked/empty after timeline refresh.
