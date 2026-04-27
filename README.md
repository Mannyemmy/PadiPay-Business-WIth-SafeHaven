# padi_pay_business

## QoreID Integration 🔧

- Added dependency: `qoreidsdk: ^1.1.3`
- Android: added QoreID Maven repo `https://repo.qoreid.com/repository/maven-releases/` and `https://jitpack.io` to `android/build.gradle.kts` (JitPack resolves `com.github.fingerprintjs:fingerprint-android` required by QoreID SDK)
- **Min SDK**: set `minSdk = 28` in `android/app/build.gradle.kts` (required by QoreID SDK)
- **Permissions**: Added `<uses-permission android:name="android.permission.CAMERA"/>` to `android/app/src/main/AndroidManifest.xml`
- **ProGuard/R8**: added targeted keep rules to `android/app/proguard-rules.pro`:
  - `-keep class com.qoreid.sdk.** { *; }`
- **Initialization**: QoreID plugin initialized in `MainActivity.kt`:
  - `QoreidsdkPlugin.initialize(this)` in `onCreate`
- **Firestore**: QoreID verification state is persisted under `users/{uid}.qoreIdData.verification`

### Testing

Manual test steps:
1. Run app on device with camera.
2. Start ID verification flow, grant camera permission.
3. Expect a log line like: `result: {data: {productCode: bvn_basic, customerReference: ..., flowId: 1593, verification: {id: 26019, state: In_Progress}}, message: Verification In Progress, event: SUCCESS_RESULT}`
4. Confirm Firestore `users/{uid}.qoreIdData.verification` is updated accordingly.

Automated tests:
- Added unit tests for parsing QoreID SDK result payloads: `test/kyb/identity_verification_test.dart`

### CI / Release checklist ✅
- Ensure `proguard-rules.pro` is present and referenced by the `release` build (`proguardFiles(...)`).
- When enabling R8/minification in CI, run a release build (`flutter build apk --release`) with minification enabled and smoke-test the QoreID flow on device to ensure no runtime crashes.
- Avoid global `-dontobfuscate`/`-dontshrink`. Prefer targeted `-keep` rules only for QoreID SDK classes.

A new Flutter project.
