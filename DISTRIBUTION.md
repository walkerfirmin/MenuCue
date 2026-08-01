# Distribution

MenuCue ships with Hardened Runtime enabled (`ENABLE_HARDENED_RUNTIME`) and App Sandbox **disabled** so Accessibility can read other apps’ menus.

## Release checklist

1. Set a Developer ID Application signing identity in Xcode (or `CODE_SIGN_IDENTITY` / team in `project.yml`).
2. Replace placeholder Sparkle keys in `project.yml`:
   - `INFOPLIST_KEY_SUFeedURL` — HTTPS appcast URL
   - `INFOPLIST_KEY_SUPublicEDKey` — EdDSA public key from `generate_keys`
3. `xcodegen generate && xcodebuild -scheme MenuCue -configuration Release archive`
4. Notarize the archive with `notarytool`, then staple.
5. Publish the Sparkle appcast + signed zip/dmg.

Until step 2 is done, the in-app updater stays inactive (see `UpdateController`).
