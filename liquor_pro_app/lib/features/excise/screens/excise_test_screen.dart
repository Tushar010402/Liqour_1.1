import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/excise_provider.dart';
import '../services/excise_api_service.dart';
import 'excise_home_screen.dart';

/// Simple test screen to verify excise module works
///
/// This screen demonstrates:
/// - Provider setup
/// - API service initialization
/// - Navigation to excise home
///
/// Usage: Navigate to this screen to test the excise module

class ExciseTestScreen extends StatelessWidget {
  const ExciseTestScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UP Excise Module Test'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_police,
                  size: 64,
                  color: Colors.blue[700],
                ),
              ),

              const SizedBox(height: 32),

              // Title
              const Text(
                'UP Excise Compliance',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                'Complete compliance management solution for liquor shops',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),

              const SizedBox(height: 48),

              // Features List
              _buildFeatureItem(
                icon: Icons.verified_user,
                title: 'License Management',
                color: Colors.blue,
              ),
              _buildFeatureItem(
                icon: Icons.description,
                title: 'Auto-Generate Reports',
                color: Colors.teal,
              ),
              _buildFeatureItem(
                icon: Icons.qr_code_scanner,
                title: 'Security Code Tracking',
                color: Colors.purple,
              ),
              _buildFeatureItem(
                icon: Icons.analytics,
                title: 'Analytics & Insights',
                color: Colors.indigo,
              ),

              const SizedBox(height: 48),

              // Launch Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _launchExciseModule(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Launch Excise Module',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Test with Mock Data Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _launchWithMockData(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Test with Mock Data',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _launchExciseModule(BuildContext context) {
    // Check if provider is available
    try {
      final provider = Provider.of<ExciseProvider>(context, listen: false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ExciseHomeScreen(),
        ),
      );
    } catch (e) {
      // Provider not found, show setup instructions
      _showSetupDialog(context);
    }
  }

  void _launchWithMockData(BuildContext context) {
    // Create a provider with mock data for testing
    final apiService = ExciseApiService(
      baseUrl: 'http://localhost:8093',
      getToken: () async => 'mock-token-for-testing',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (_) => ExciseProvider(apiService),
          child: const ExciseHomeScreen(),
        ),
      ),
    );
  }

  void _showSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Provider Setup Required'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To use the Excise Module, add ExciseProvider to your app:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                '// In your main.dart:\n'
                'MultiProvider(\n'
                '  providers: [\n'
                '    ChangeNotifierProvider(\n'
                '      create: (_) => ExciseProvider(\n'
                '        ExciseApiService(\n'
                '          baseUrl: "http://localhost:8093",\n'
                '          getToken: () => yourToken,\n'
                '        ),\n'
                '      ),\n'
                '    ),\n'
                '  ],\n'
                ')',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Or use "Test with Mock Data" to try it without setup.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _launchWithMockData(context);
            },
            child: const Text('Test with Mock'),
          ),
        ],
      ),
    );
  }
}
