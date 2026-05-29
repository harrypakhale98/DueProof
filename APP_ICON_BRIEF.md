# DueProof App Icon Brief

## Concept

A plain, centered pastel receipt logo on neutral light and dark backgrounds. The icon should feel like a stock Apple utility: simple, useful, private, and trustworthy.

## Layers

- Light background: soft white or pale system-gray field.
- Dark background: near-black or charcoal field.
- Front layer: centered, larger pastel blue-to-mint receipt silhouette with a soft scalloped edge and a few thick cutout-style receipt marks that read clearly at small sizes.

## Color and Material Direction

- Use pastel blue-to-mint as the receipt gradient with restrained contrast.
- Avoid busy shadows, harsh neon colors, and glossy glass decoration.
- Support light and dark icon contexts through asset-catalog appearance variants; review tinted/clear variants separately if the final iOS 26 asset pipeline supports them.

## Avoid

- No text.
- No tiny receipt lines that disappear at small sizes.
- No sharp coupon-style tear edge.
- No cartoon receipt illustration.
- No check badge.
- No money-bag or finance-bro symbols.
- No visual overlap with Notes, Reminders, Wallet, or Files.

## Finishing Notes

The asset catalog contains build-safe 1024px opaque PNG masters at `DueProof/Resources/Assets.xcassets/AppIcon.appiconset/DueProofIcon.png`, `DueProof/Resources/Assets.xcassets/AppIcon.appiconset/DueProofIconDark.png`, and `DueProof/Resources/Assets.xcassets/AppIcon.appiconset/DueProofIconTinted.png`. Before App Store submission, review the icon in Icon Composer or the final Xcode asset workflow for any additional clear or layered variants if supported by the submission toolchain.
