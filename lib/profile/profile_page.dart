import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:padi_pay_business/cards_page.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/kyc/user_upgrade_manager.dart';
import 'package:padi_pay_business/legal_and_regulatory.dart';
import 'package:padi_pay_business/my_business/my_business.dart';
import 'package:padi_pay_business/notification_settings.dart';
import 'package:padi_pay_business/kyb/business_upgrade_manager.dart';
import 'package:padi_pay_business/profile/edit_profile_page.dart';
import 'package:padi_pay_business/promos.dart';
import 'package:padi_pay_business/referrals.dart';
import 'package:padi_pay_business/sign_in.dart';
import 'package:padi_pay_business/super_agent/super_agent_hub.dart';
import 'package:padi_pay_business/padi_book/padi_book_page.dart';
import 'package:padi_pay_business/transactions_history.dart';
import 'package:padi_pay_business/ui/bottom_nav_bar.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _selectedIndex = 4;
  String? firstName;
  String? lastName;
  String? phone;
  String? email;
  String? dob;
  String? address1;
  String? state;
  String? country;
  String? profilePhotoUrl;
  String? tier;
  bool isTouchOrFace = false;
  bool isBusinessUser = false;
  bool isSuperAgent = false;
  bool isLoggedInStandUser = false;
  bool _bvnMatch = false;

  bool _detectionCompleteProfile = false;
  StreamSubscription<DocumentSnapshot>? _userDocSub;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isMockSuperAgent =
        (user.email ?? '').trim().toLowerCase() == 'justefe99@gmail.com';
    // Reset detection flags to avoid stale UI state
    setState(() {
      isLoggedInStandUser = false;
      _detectionCompleteProfile = false;
    });
    DocumentSnapshot userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (userSnap.exists) {
      var data = userSnap.data() as Map<String, dynamic>;
      setState(() {
        firstName = data['firstName'];
        lastName = data['lastName'];
        phone = data['phone'];
        email = data['email'];
        dob = data['dateOfBirth'];
        address1 = data['address']?['street'];
        state = data['address']?['state'];
        country = data['address']?['country'];
        profilePhotoUrl = data['profilePhotoUrl'];
        tier = (getWalletTier(data) ?? "0").toString();
      });
    }

    // Check if this auth user is a stand user and, if so, fetch parent business tier
    try {
      DocumentSnapshot standSnap = await FirebaseFirestore.instance
          .collection('standUsers')
          .doc(user.uid)
          .get();
      if (standSnap.exists) {
        final sdata = standSnap.data() as Map<String, dynamic>?;
        final parentBusinessId = sdata?['parentBusinessId'] as String?;
        if (parentBusinessId != null) {
          // mark stand user, but update UI after we've finished detection
          String? parentTier;
          try {
            // fetch parent user document to get tier (stand users should inherit tier from parent USER)
            final parentUserSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(parentBusinessId)
                .get();
            if (parentUserSnap.exists) {
              final pdata = parentUserSnap.data() as Map<String, dynamic>;
              parentTier = getWalletTier(pdata);
            }
          } catch (e) {
            debugPrint('Error fetching parent user in profile: $e');
          }
          setState(() {
            isLoggedInStandUser = true;
            tier = parentTier ?? tier ?? "0";
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking stand user in profile: $e');
    } finally {
      // mark detection complete so build can enable/disable actions deterministically
      if (mounted) {
        setState(() {
          _detectionCompleteProfile = true;
        });
      }
    }

    DocumentSnapshot businessSnap = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();
    final businessData = businessSnap.data() as Map<String, dynamic>?;
    setState(() {
      isBusinessUser = businessSnap.exists;
      isSuperAgent = isMockSuperAgent || businessData?['isSuperAgent'] == true;
    });
  }

  void _listenForBvnMatch() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data() ?? <String, dynamic>{};
            final qore = data['qoreIdData'] as Map<String, dynamic>?;
            final verification = qore?['verification'] as Map<String, dynamic>?;
            final metadata = verification?['metadata'] as Map<String, dynamic>?;
            final match = metadata?['match'];
            if (!mounted) return;
            setState(() {
              _bvnMatch = match == true;
            });
          },
          onError: (e) {
            print('BVN match listener error: $e');
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        navigateTo(context, HomePage(), type: NavigationType.clearStack);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SizedBox.expand(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: 100),
                    CircleAvatar(
                      radius: 60,
                      backgroundImage:
                          profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                          ? NetworkImage(profilePhotoUrl!)
                          : const AssetImage("assets/profile_placeholder.png"),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "${firstName ?? ""} ${lastName ?? ""}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      email ?? "",
                      style: TextStyle(
                        fontWeight: FontWeight.w300,
                        fontSize: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    SizedBox(height: 15),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: tier == "0"
                              ? Colors.grey.withValues(alpha: 0.2)
                              : Colors.green.withValues(alpha: 0.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.task_alt,
                              color: tier == "0" ? Colors.grey : Colors.green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              // only append a tier number if there's an actual
                              // banking tier assigned; BVN match alone is not a
                              // real tier.
                              _bvnMatch && tier == "0"
                                  ? "Identity Verified"
                                  : tier == "0"
                                  ? "KYC Not Verified"
                                  : "KYC Verified Tier $tier",
                              style: TextStyle(
                                color: tier == "0" ? Colors.grey : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(0.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/profile.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Edit Profile',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        navigateTo(context, EditProfilePage());
                                      }
                                    : null,
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/proicons_gift.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Upgrade Account',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        if (isBusinessUser) {
                                          navigateTo(
                                            context,
                                            BusinessUpgradeManager(),
                                          );
                                        } else {
                                          if (int.parse(tier ?? "0") >= 2) {
                                            return;
                                          }
                                          navigateTo(
                                            context,
                                            UserUpgradeManager(
                                              tier: tier ?? "0",
                                            ),
                                          );
                                        }
                                      }
                                    : null,
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/proicons_gift.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Promos & Offers',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        navigateTo(context, PromosScreen());
                                      }
                                    : null,
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/formkit_people.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Referrals',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        navigateTo(context, ReferralsScreen());
                                      }
                                    : null,
                              );
                            },
                          ),
                          if (isSuperAgent)
                            Builder(
                              builder: (context) {
                                final actionsEnabled = _detectionCompleteProfile
                                    ? !isLoggedInStandUser
                                    : false;
                                return ListTile(
                                  title: Opacity(
                                    opacity: actionsEnabled ? 1.0 : 0.5,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.workspace_premium_outlined,
                                              size: 20,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          SizedBox(width: 20),
                                          Text(
                                            'Super Agent Hub',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          Spacer(),
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            size: 15,
                                            color: Colors.grey.shade600,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  onTap: actionsEnabled
                                      ? () {
                                          navigateTo(
                                            context,
                                            const SuperAgentHubPage(),
                                          );
                                        }
                                      : null,
                                );
                              },
                            ),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/hugeicons_notification-square.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Notification Settings',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        navigateTo(
                                          context,
                                          NotificationSettings(),
                                        );
                                      }
                                    : null,
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/solar_lock-password-broken.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Change Passcode',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        navigateTo(context, EditProfilePage());
                                      }
                                    : null,
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/solar_login-outline.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Login with Touch ID/Face ID',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        IgnorePointer(
                                          ignoring: !actionsEnabled,
                                          child: FlutterSwitch(
                                            width: 50,
                                            height: 25,
                                            toggleSize: 20,
                                            borderRadius: 20,
                                            padding: 3,
                                            value: isTouchOrFace,
                                            activeColor: primaryColor,
                                            inactiveColor: Colors.grey.shade300,
                                            onToggle: (val) => setState(
                                              () => isTouchOrFace = val,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        navigateTo(context, EditProfilePage());
                                      }
                                    : null,
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final actionsEnabled = _detectionCompleteProfile
                                  ? !isLoggedInStandUser
                                  : false;
                              return ListTile(
                                title: Opacity(
                                  opacity: actionsEnabled ? 1.0 : 0.5,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: SvgPicture.asset(
                                            'assets/octicon_law-24.svg',
                                            width: 20,
                                            height: 20,
                                          ),
                                        ),
                                        SizedBox(width: 20),
                                        Text(
                                          'Legal',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Spacer(),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: actionsEnabled
                                    ? () {
                                        navigateTo(
                                          context,
                                          LegalAndRegulatory(),
                                        );
                                      }
                                    : null,
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              return ListTile(
                                title: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          shape: BoxShape.circle,
                                        ),
                                        child: SvgPicture.asset(
                                          'assets/dashicons_admin-site-alt3.svg',
                                          width: 20,
                                          height: 20,
                                        ),
                                      ),
                                      SizedBox(width: 20),
                                      Text(
                                        'Visit Our Website',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      Spacer(),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 15,
                                        color: Colors.grey.shade600,
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: () {
                                  launchUrl(
                                    Uri.parse('https://padipay.co'),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                              );
                            },
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.logout,
                                      color: Colors.grey.shade600,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Log Out',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () async {
                              await FirebaseAuth.instance.signOut();
                              navigateTo(context, SignIn());
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 150),
                  ],
                ),
              ),
              Positioned(
                bottom: 25,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: BottomNavBar(
                    currentIndex: _selectedIndex,
                    onTap: (index) {
                      if (index == 0) {
                        navigateTo(
                          context,
                          HomePage(),
                          type: NavigationType.push,
                        );
                      }
                      if (index == 1) {
                        navigateTo(
                          context,
                          CardsPage(),
                          type: NavigationType.push,
                        );
                      }
                      if (index == 2) {
                        navigateTo(
                          context,
                          MyBusiness(),
                          type: NavigationType.push,
                        );
                      }
                      if (index == 3) {
                        navigateTo(
                          context,
                          TransactionsHistory(),
                          type: NavigationType.push,
                        );
                      }
                      if (index == 5) {
                        navigateTo(
                          context,
                          const PadiBookPage(),
                          type: NavigationType.push,
                        );
                      } else {
                        setState(() => _selectedIndex = index);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
