import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  bool hideCardsAndBusiness = false;
  bool _detectionComplete = false;

  @override
  void initState() {
    super.initState();
    _detectIfStandUser();
  }

  Future<void> _detectIfStandUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final uid = user.uid;
      final doc = await FirebaseFirestore.instance.collection('standUsers').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['parentBusinessId'] != null && data['standId'] != null) {
          if (!mounted) return;
          setState(() {
            hideCardsAndBusiness = true;
            _detectionComplete = true;
          });
          return;
        }
      }
      // default: not a stand user
      if (!mounted) return;
      setState(() {
        hideCardsAndBusiness = false;
        _detectionComplete = true;
      });
    } catch (e) {
      // On any error, default to showing items
      if (!mounted) return;
      setState(() {
        hideCardsAndBusiness = false;
        _detectionComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      elevation: 1,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: 80,
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          // Use spaceEvenly so the visible items are centered when some are hidden
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // If detection hasn't completed yet, render a safe minimal set
            // (treat as stand user) to avoid briefly showing all items.
            for (final item in (!_detectionComplete ? [
                  {'index': 0, 'icon': FontAwesomeIcons.house, 'label': 'Home'},
                  {'index': 3, 'icon': Icons.history, 'label': 'History'},
                  {'index': 5, 'icon': Icons.book_outlined, 'label': 'PadiBook'},
                  {'index': 4, 'icon': Icons.settings, 'label': 'Settings'},
                ] : hideCardsAndBusiness
                ? [
                    {'index': 0, 'icon': FontAwesomeIcons.house, 'label': 'Home'},
                    {'index': 3, 'icon': Icons.history, 'label': 'History'},
                    {'index': 5, 'icon': Icons.book_outlined, 'label': 'PadiBook'},
                    {'index': 4, 'icon': Icons.settings, 'label': 'Settings'},
                  ]
                : [
                    {'index': 0, 'icon': FontAwesomeIcons.house, 'label': 'Home'},
                    {'index': 2, 'icon': Icons.business_center_outlined, 'label': 'Business'},
                    {'index': 3, 'icon': Icons.history, 'label': 'History'},
                    {'index': 5, 'icon': Icons.book_outlined, 'label': 'PadiBook'},
                    {'index': 4, 'icon': Icons.settings, 'label': 'Settings'},
                  ]))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: _buildNavItem(
                  item['index'] as int,
                  item['icon'] as IconData,
                  item['label'] as String,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = index == widget.currentIndex;
    return InkWell(
      onTap: () => widget.onTap(index),
      child: Stack(
        children: [
          Align(
            alignment: AlignmentGeometry.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isSelected ? primaryColor : Colors.grey,
                    size: 20,
                  ),
                  SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? primaryColor : Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}