Steps to generate keystore, get SHA-1/SHA-256, and sign the release

1) Generate the keystore (run in repo root or any path; this example assumes you run from the project root):

Windows (cmd):
keytool -genkeypair -v -keystore "android/app/padi_pay_business.jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias padi_pay_business_key -storepass 4191023225 -keypass 4191023225 -dname "CN=Emmanuel Ekundayo, OU=Programming, O=All Good Technologies, L=Benin, ST=Edo, C=NG"

Notes:
- This produces the keystore file at `android/app/padi_pay_business.jks`.
- Password: 4191023225
- Alias: padi_pay_business_key

2) Verify the keystore and get the SHA-1 / SHA-256:

Windows (cmd):
keytool -list -v -keystore "android/app/padi_pay_business.jks" -alias padi_pay_business_key -storepass 4191023225

Look for the lines:
  SHA1:  <your SHA1 fingerprint>
  SHA256:  <your SHA256 fingerprint>

(You can filter output with `| findstr "SHA1 SHA256"` on Windows.)

3) What we changed in the project (already implemented):
- `android/key.properties` created (not committed — added to `.gitignore`) with the store path and passwords.
- `android/app/build.gradle.kts` updated to load `android/key.properties` and configure a `release` signing config that uses the keystore information.
- `.gitignore` updated to ignore `android/key.properties` and the keystore file.

4) Build the release artifacts (after generating the keystore locally):
- Android App Bundle: `flutter build appbundle --release`
- APK: `flutter build apk --release`

5) Upload the SHA-1/SHA-256 where required (Firebase, Google Cloud APIs, etc.).

Security tip: keep the `android/key.properties` and the keystore file out of source control; consider storing them securely (password manager or private secure storage) or use environment variables in CI.
