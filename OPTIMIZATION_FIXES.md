# PadiPay Business App — Optimization Fixes Applied

**Date:** April 18, 2026

---

## 1. `late StreamSubscription` CRASH RISK (HIGH)
**File:** `lib/home_pages/home_page.dart` (lines 73-76)
**Problem:** `late StreamSubscription` declarations crash at `dispose()` time if subscriptions were never initialized (e.g., auth failure before streams are set up).
**Fix:** Changed to nullable `StreamSubscription?` types. Updated `dispose()` to use `?.cancel()`.

---

## 2. MISSING onError HANDLERS ON STREAM LISTENERS (HIGH)
**File:** `lib/home_pages/home_page.dart` (lines 95-135)
**Problem:** Transaction and counterparty stream listeners had no `onError` callback. Stream errors were silently dropped, causing stale UI state.
**Fix:** Added `onError` handlers with `debugPrint` logging and graceful state fallback.

---

## 3. TRANSACTION QUERIES WITHOUT .limit() (MEDIUM)
**File:** `lib/home_pages/home_page.dart`, `lib/transactions_history.dart`
**Problem:** Transaction stream queries fetched ALL user transactions (no `.limit()`). Active business accounts with thousands of transactions downloaded everything.
**Fix:** Added `.orderBy('timestamp', descending: true).limit(200)` on home page streams, `.limit(500)` on transaction history page.

---

## 4. MISSING `mounted` CHECKS (MEDIUM)
**File:** `lib/home_pages/home_page.dart`
**Problem:** Stream listener callbacks called `setState()` without checking `mounted`.
**Fix:** Added `if (mounted)` guards.

---

## 5. SEQUENTIAL BILLER FETCH (MEDIUM)
**File:** `lib/bills/pay_bills.dart` — `_fetchBillers()`
**Problem:** Data, television, and electricity biller categories fetched sequentially. Total time ≈ 900ms.
**Fix:** Wrapped all 3 in `Future.wait()`. Total time ≈ 300ms.

---

## 6. `late StreamSubscription` IN transactions_history.dart (HIGH)
**File:** `lib/transactions_history.dart` (lines 692-694)
**Problem:** Same `late` crash risk as #1 above.
**Fix:** Changed to nullable types, updated `dispose()`.

---

## REMAINING RECOMMENDATIONS

### A. Parallel API Calls in cards_page.dart
`_fetchBalanceAndFx()` calls `_fetchBalance()` then `bridgecardGetFxRate` sequentially. These are independent and should use `Future.wait()`.

### B. Profile Image Error Handling
`NetworkImage(profilePhotoUrl!)` in profile_page.dart has no error fallback. Add `onBackgroundImageError` or use a fallback widget.
