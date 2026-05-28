# DueProof Release Checklist

## Engineering

- [ ] Build passes.
- [ ] Tests pass.
- [ ] No DueProof-operated backend or remote push dependency.
- [ ] No DueProof account system.
- [ ] Optional private iCloud sync verified on/off after relaunch.
- [ ] Spotlight search is off by default, opt-in only, and cleared while App Lock is enabled.
- [ ] No ads, analytics, tracking, telemetry, or crash-reporting SDK.
- [ ] SwiftData persistence verified after relaunch.
- [ ] Proof photo add/remove/delete behavior verified.
- [ ] Oversized proof photo/PDF imports are rejected without stale local files.
- [ ] Large proof photos are downsampled before storage and OCR.
- [ ] Share-extension photo/PDF imports use bounded file intake and reject oversized files without empty queued imports.
- [ ] Pasted/imported action links and money values are bounded and reject invalid or non-finite input.
- [ ] Local notification scheduling, rescheduling, and cancellation verified.
- [ ] JSON export/import verified.
- [ ] Share-extension photo/PDF import verified, including failed-import cleanup.
- [ ] Malformed deep links do not trigger broad shared-import or oversized search state.
- [ ] CSV report export verified, including formula-style cell neutralization.
- [ ] Calendar export verified, including long escaped Unicode titles importing as one event.

## Product Quality

- [ ] Empty state polished.
- [ ] Dashboard metrics verified.
- [ ] Claims list search/filter/sort verified.
- [ ] Add/Edit form validation verified.
- [ ] Claim detail actions verified.
- [ ] Failed edit/status/proof saves do not leave visible unsaved in-memory changes.
- [ ] All destructive actions confirmed.
- [ ] Clear All Data removes claims, proof files, reminders, generated export files, Spotlight entries, widget snapshots, and pending share-extension imports.
- [ ] Widget shows locked/empty state when App Lock is enabled, even if stale shared snapshots exist.
- [ ] Light mode reviewed.
- [ ] Dark mode reviewed.
- [ ] Large Dynamic Type reviewed.
- [ ] VoiceOver basics reviewed.
- [ ] Small iPhone layout reviewed.
- [ ] Large iPhone layout reviewed.

## App Store

- [ ] App icon present.
- [ ] iOS 26 layered icon assets reviewed, if supported by final asset pipeline.
- [ ] Launch screen acceptable.
- [ ] Privacy copy reviewed.
- [ ] App Store privacy answers prepared.
- [ ] Screenshots prepared.
- [ ] App Store metadata reviewed.
- [ ] TestFlight build ready.

## Suggested Metadata

App name: DueProof

Subtitle: Receipt & Claim Tracker

Tagline: Keep proof. Beat deadlines.

Short description: DueProof helps you track returns, warranties, gift cards, reimbursements, renewals, and other claim deadlines privately on your device.

Privacy summary: DueProof does not use a DueProof account, ads, analytics, tracking, or a DueProof-operated backend. Claim details and proof photos are stored locally by default, with optional private iCloud sync controlled by the user.
