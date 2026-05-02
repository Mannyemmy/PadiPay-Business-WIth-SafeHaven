# Task: Align business upgrade_tier.dart with user app + Fix KYB manager "Fix Now" when BVN verified

## Current Status
- [x] Analyzed files: profile/upgrade_tier.dart, kyb/business_upgrade_manager.dart, kyb/identity_verification.dart
- [x] Confirmed plan with user

## Steps to Complete

1. **Fix business_upgrade_manager.dart _loadFlags()** 
   - Enhance idVerified detection for user app BVN: if userData['bvn'] exists AND (userData['sudoData']?['tier'] >=1 OR qoreData['verification']?['verified']==true OR customerCreation exists)
   - Ensure shows "Fixed" (green) when BVN verified from user app

2. **Align profile/upgrade_tier.dart UI like user app**
   - Add prominent persistent green checkmark banner at top when _bvnVerified==true || _isBvnVerifiedLocked
   - Add lock icon to suffix of BVN field when verified
   - Ensure ALL fields (name, DOB, address, etc.) fully disabled/readOnly with visual indicators when verified
   - Strengthen _isBvnVerifiedLocked logic

3. **Test verification flow**
   - Verify checkmark shows persistently
   - Confirm no editing allowed when verified
   - Check manager shows "Fixed" after verification (user app or business)

4. **Completion**
   - Update TODO.md with [x]
   - attempt_completion

## Priority
High: manager "Fix Now" bug blocking KYB
