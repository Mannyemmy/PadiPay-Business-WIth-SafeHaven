import 'package:flutter/material.dart';
import 'package:padi_pay_business/onboarding_1.dart';
import 'package:padi_pay_business/sign_in.dart';
import 'package:padi_pay_business/utils.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: Stack(
          children: [
            SizedBox.expand(
              child: Image.asset(
                "assets/welcome_background.png",
                fit: BoxFit.fill,
                height: MediaQuery.of(context).size.height,
                width: MediaQuery.of(context).size.width,
              ),
            ),
            Positioned(
              bottom: 15,
              top: 0,
              left: 15,
              right: 15,
              child: Align(
                alignment: AlignmentGeometry.bottomCenter,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.57,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        SizedBox(height: 50),
                        Row(
                          children: [
                            Text(
                              "The Business",
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w800,
                                fontSize: 30,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              "Advantage",
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w800,
                                fontSize: 30,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Image.asset("assets/you_button.png", width: 70),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              "Need",
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w800,
                                fontSize: 30,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Accept payments, manage POS stands and grow your business - all from one app",
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 40),
                        GestureDetector(
                          onTap: () {
                            navigateTo(context, Onboarding1());
                          },
                          child: Container(
                            alignment: AlignmentGeometry.center,
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            width: MediaQuery.of(context).size.width,
                            child: Text(
                              "Get Started",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 30),
                        InkWell(
                          onTap: (){
                            navigateTo(context, SignIn());
                          },
                          child: RichText(
                            text: TextSpan(
                              text: "Already have an account? ",
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                              children: [
                                TextSpan(
                                  text: " Login",
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
