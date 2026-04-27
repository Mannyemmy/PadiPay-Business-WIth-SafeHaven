
// Placeholder text for shimmer
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/my_business/my_business.dart';

class ShimmerText extends StatelessWidget {
  final TextStyle style;

  const ShimmerText({super.key, this.style = const TextStyle()});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: style.fontSize ?? 14,
      width: 120,
      child: ShimmerEffect(child: const SizedBox()),
    );
  }
}

// Shimmer stand card (Stack-based)
class ShimmerStandCard extends StatelessWidget {
  const ShimmerStandCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey[300],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerText(
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ShimmerText(
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Divider(color: Colors.white),
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < 3; i++)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerText(
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ShimmerText(
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
