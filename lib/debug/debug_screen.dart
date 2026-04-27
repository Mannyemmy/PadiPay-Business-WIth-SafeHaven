import 'package:flutter/material.dart';
import 'package:padi_pay_business/utils/mock_super_agent_seeder.dart';

/// Debug screen for testing and seeding mock data
/// Only enable this in development/debug builds
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  bool _isLoading = false;
  String _status = '';

  Future<void> _seedSuperAgent() async {
    setState(() {
      _isLoading = true;
      _status = 'Seeding mock super agent data...';
    });

    await seedMockSuperAgentData(
      email: 'justefe99@gmail.com',
      businessName: 'Jeste Super Agent Business',
    );

    setState(() {
      _isLoading = false;
      _status = '✅ Mock data seeded! You can now log in with justefe99@gmail.com and see the Super Agent Hub.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Screen'),
        backgroundColor: Colors.red.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ DEBUG MODE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This screen should only be available in development builds. Use it to seed mock data for testing.',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Super Agent Mock Data',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Email: justefe99@gmail.com', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text(
                    'Mock Data Includes:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  const Text('• Referral Code: PADI-SA-XXXXX', style: TextStyle(fontSize: 12)),
                  const Text('• Stars: 4/5', style: TextStyle(fontSize: 12)),
                  const Text('• Total Earnings: ₦1,250,000', style: TextStyle(fontSize: 12)),
                  const Text('• Available Earnings: ₦500,000', style: TextStyle(fontSize: 12)),
                  const Text('• 5 mock referred businesses', style: TextStyle(fontSize: 12)),
                  const Text('• 10 mock commission records', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _seedSuperAgent,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(_isLoading ? 'Seeding...' : 'Seed Mock Data'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _status.startsWith('✅') ? Colors.green.shade50 : Colors.blue.shade50,
                  border: Border.all(
                    color: _status.startsWith('✅') ? Colors.green : Colors.blue,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _status.startsWith('✅') ? Colors.green.shade700 : Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
