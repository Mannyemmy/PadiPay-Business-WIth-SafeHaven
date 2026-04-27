import 'package:flutter/material.dart';
import 'package:padi_pay_business/transfer/bank_transfer_page.dart';
import 'package:padi_pay_business/transfer/withdraw_for_customer.dart';

class ChooseTransferFundsType extends StatelessWidget {
  const ChooseTransferFundsType({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(0.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: const Text(
                'Transfer Funds',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                child: Icon(Icons.account_balance, color: Colors.grey),
              ),
              title: const Text(
                'Send via bank transfer',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle:  Text(
                'Use bank transfer to send money to a previous or new recipient',
                style: TextStyle(fontWeight: FontWeight.w500,color: Colors.grey.shade600),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BankTransferPage(),
                  ),
                );
              },
            ),
            const Divider(color: Colors.grey, thickness: 0.1),

            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                child: Icon(Icons.account_balance, color: Colors.grey),
              ),
              title: const Text(
                'Withdraw for Customer',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle:  Text(
                'Help PadiPay users withdraw cash securely using their PadiTag or account number, no ATM card needed.',
               style: TextStyle(fontWeight: FontWeight.w500,color: Colors.grey.shade600),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WithdrawForCustomerPage(),
                  ),
                );
              },
            ),
            const Divider(color: Colors.grey, thickness: 0.1),

            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                child: Icon(Icons.account_balance, color: Colors.grey),
              ),
              title: const Text(
                'Ghost Mode',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle:  Text(
                'Send money anonymously',
               style: TextStyle(fontWeight: FontWeight.w500,color: Colors.grey.shade600),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BankTransferPage(initialGhostMode: true),
                  ),
                );
              },
            ),
            // const Divider(color: Colors.grey, thickness: 0.1),
            // ListTile(
            //   leading: CircleAvatar(
            //     backgroundColor: Colors.grey.shade200,
            //     child: Icon(Icons.currency_bitcoin, color: Colors.grey),
            //   ),
            //   title: const Text(
            //     'Send via Crypto',
            //     style: TextStyle(fontWeight: FontWeight.w500),
            //   ),
            //   subtitle: const Text(
            //     'Send crypto through different networks to any wallet',
            //     style: TextStyle(fontWeight: FontWeight.w300),
            //   ),
            //   onTap: () {
            //     // Navigator.push(
            //     //   context,
            //     //   MaterialPageRoute(
            //     //     builder: (context) => const CryptoTransferPage(),
            //     //   ),
            //     // );
            //   },
            // ),
          
          ],
        ),
      ),
    );
  }
}
