# DueProof Accessibility Audit

## What Was Reviewed

- Dashboard metrics and empty state.
- Claim card readability and VoiceOver summaries.
- Claims list row grouping.
- Claim detail header, proof area, reminder area, and destructive actions.
- Add/Edit claim form validation and keyboard dismissal.
- Settings privacy and data controls.

## Improvements Made

- Added a reusable `ClaimCardView` with combined VoiceOver labels for title, value at risk, due state, status, proof, and reminder.
- Replaced generic overdue copy with specific language such as "Overdue by 2 days."
- Kept status and urgency available as text and SF Symbols, not color alone.
- Improved the empty dashboard state with clearer product framing and local-storage reassurance.
- Added local proof-photo reassurance in Claim Detail.
- Added a keyboard Done control to the Add/Edit form.
- Preserved Dynamic Type-aware layouts for rows and claim cards.

## Remaining Risks

- Full VoiceOver navigation still needs physical-device testing.
- Very long merchant/title combinations should be checked on a small iPhone with accessibility text sizes.
- UI tests do not currently cover VoiceOver, Reduce Motion, or Differentiate Without Color.
- Proof thumbnail labels are meaningful, but custom user-provided proof names are not yet editable.

## Manual Testing Checklist

- Test large text and accessibility text sizes on Dashboard, Claims, Detail, Add/Edit, and Settings.
- Turn on VoiceOver and navigate the main tabs, claim rows, action menus, proof tiles, and destructive dialogs.
- Turn on Increase Contrast and Differentiate Without Color.
- Turn on Reduce Motion and verify no workflow depends on motion.
- Verify every destructive action is announced and confirmed.
- Verify all important tap targets are easy to reach.
