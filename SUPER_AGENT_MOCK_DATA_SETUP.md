# Super Agent Mock Data Setup

## Quick Start

This guide will help you set up mock super agent data for testing the Super Agent Hub feature.

### What Gets Created

When you run the seeder for `justefe99@gmail.com`:

```
✅ Account Status: Super Agent (isSuperAgent = true)
✅ Referral Code: PADI-SA-XXXXX (unique per user)
✅ Stars Rating: 4/5
✅ Total Earnings: ₦1,250,000
✅ Available Earnings: ₦500,000
✅ Mock Referrals: 5 businesses
✅ Mock Commissions: 10 records with various types
```

### Commission Types in Mock Data

1. **NIP Transfer Commission** (₦5 per transfer)
   - 7 mock records showing transaction commissions

2. **Business Verification Bonus** (₦5,000 per verified business)
   - 3 mock records showing verification bonuses

### How to Use

#### Option 1: Use the Debug Screen (Recommended)

1. **Open the debug screen** by running this in your terminal:
   ```
   flutter run --dart-define=FLUTTER_ENV=debug
   ```

2. Or navigate to the debug screen directly in your app:
   ```dart
   // In your main.dart or navigation
   Navigator.push(
     context,
     MaterialPageRoute(builder: (_) => const DebugScreen()),
   );
   ```

3. **Tap "Seed Mock Data"** button
   - This will populate all mock data to Firestore
   - You'll see a success message when complete

#### Option 2: Call the Seeder Directly

```dart
import 'package:padi_pay_business/utils/mock_super_agent_seeder.dart';

// Call this anywhere in your app (e.g., on app startup if debug mode)
await seedMockSuperAgentData(
  email: 'justefe99@gmail.com',
  businessName: 'Jeste Super Agent Business',
);
```

### Testing the Super Agent Hub

1. **Log in** with `justefe99@gmail.com`
2. Navigate to **Profile** → **Super Agent Hub**
3. You should see:
   - ✅ Referral code with copy/share buttons
   - ✅ Stars: 4/5
   - ✅ Total Earned: ₦1,250,000
   - ✅ Available: ₦500,000
   - ✅ Program Rewards showing commission rates
   - ✅ 10 recent commission records
   - ✅ 5 referred businesses with performance

### Mock Data Structure

**Business Document** (`businesses/{userId}`):
```json
{
  "isSuperAgent": true,
  "superAgentReferralCode": "PADI-SA-XXXXX",
  "superAgentStars": 4,
  "superAgentTotalEarnings": 1250000,
  "superAgentAvailableEarnings": 500000,
  "businessName": "Jeste Super Agent Business",
  "email": "justefe99@gmail.com"
}
```

**Commission Documents** (`superAgentCommissions/{id}`):
```json
{
  "superAgentBusinessId": "userId",
  "businessId": "bus_001_demo",
  "amount": 5.0,
  "type": "nip_transfer",
  "status": "credited",
  "createdAt": "timestamp",
  "referralCode": "PADI-SA-XXXXX"
}
```

### Clearing Mock Data

To remove mock data and start fresh:

```dart
// Delete all mock commissions for this user
final commissions = await FirebaseFirestore.instance
    .collection('superAgentCommissions')
    .where('superAgentBusinessId', isEqualTo: userId)
    .get();

for (final doc in commissions.docs) {
  await doc.reference.delete();
}

// Update business to remove super agent flag
await FirebaseFirestore.instance
    .collection('businesses')
    .doc(userId)
    .update({
      'isSuperAgent': false,
      'superAgentReferralCode': FieldValue.delete(),
    });
```

### Troubleshooting

**"User not found"**
- Make sure `justefe99@gmail.com` exists in your Firestore `users` collection
- Or modify the seeder to use your test user email

**No data showing in Super Agent Hub**
- Verify the `isSuperAgent` flag is `true` in the business doc
- Check that commissions are in `superAgentCommissions` collection
- Try pull-to-refresh in the Super Agent Hub screen

**Want Different Mock Data?**
- Edit `lib/utils/mock_super_agent_seeder.dart` to customize amounts, referral counts, etc.
- Change the mock commission objects in the `mockCommissions` list

---

**Note**: The debug screen and seeder are development tools. Remove them or gate them behind a debug flag before production deployment.
