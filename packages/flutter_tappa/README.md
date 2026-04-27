# Flutter Tappa

A Flutter plugin that integrates with the Tappa NFC payment SDK for Android.

## Features

- NFC payment transactions
- EMV QR code scanning and processing
- Terminal initialization and configuration
- Standard and Insured Loyalty Card support
- SafeHaven MFB transaction support (Onboarding Guide)
- Robust error handling and callback interface

## Getting Started

### Prerequisites

- Android device with NFC capabilities

### Installation

Add `flutter_tappa` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_tappa: ^0.0.2
```

### Android AccessSetup

Ensure your Android project has the required access to access sdk:

```groovy

For older Gradle (pre-7):
In android/build.gradle:

allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://sdk.sudo.africa/repository/maven-releases/")
            credentials {
                username = project.findProperty("maven.repo.username") ?: ""
                password = project.findProperty("maven.repo.password") ?: ""
            }
        }
    }
}

For Gradle 7+ (Flutter 3.7+):
In android/settings.gradle:

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://sdk.sudo.africa/repository/maven-releases/")
            credentials {
                username = project.findProperty("maven.repo.username") ?: ""
                password = project.findProperty("maven.repo.password") ?: ""
            }
        }
    }
}

```-

### Usage

Import the package:

```dart
import 'package:flutter_tappa/flutter_tappa.dart';
```

Initialize the Tappa SDK:

```dart
final FlutterTappa tappa = FlutterTappa();

await tappa.initialize(
  errorCallback: (errorCode, errorMessage) {
    print('Tappa error: $errorCode - $errorMessage');
  }
);
```

Initialize the terminal:

```dart
await tappa.initTerminal(
  terminalId: 'TERM001',
  uniqueId: 'UID123456',
  clientId: 'CLIENT001',
  merchantLocation: 'Main Street Store'
);
```

Start a transaction:

```dart
await tappa.transact(
  amount: '1000', // 10.00 in minor units
  accountType: '10', // Savings account
  rrn: 'RRN12345678'
);
```

Read a loyalty card:

```dart
await tappa.startReadingLoyaltyCard();
```

Process EMV QR:

```dart
await tappa.processQrAndTransact('EMVQR_DATA_STRING');

Or, to inspect EMV QR content without transacting:

final result = await tappa.processQrForResult('EMVQR_DATA_STRING');

```

SafeHaven Transactions
Enable special processing for SafeHaven merchant transactions via EMV QR or NFC.

👉 Complete SafeHaven Onboarding Guide [https://safehavenmfb.com/contact]

## Error Codes

- 0: Success
- 30-39: PIN-related errors
- 50: APDU transceive error
- 100-104: Loyalty card errors

## Example

See the 'example' folder for a complete sample Flutter application that demonstrates how to use this plugin.

## License

MIT License