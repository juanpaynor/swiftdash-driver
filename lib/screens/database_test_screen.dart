import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../services/database_test_service.dart';

class DatabaseTestScreen extends StatefulWidget {
  const DatabaseTestScreen({super.key});

  @override
  State<DatabaseTestScreen> createState() => _DatabaseTestScreenState();
}

class _DatabaseTestScreenState extends State<DatabaseTestScreen> {
  final _testService = DatabaseTestService();
  Map<String, dynamic>? _testResults;
  bool _isLoading = false;

  Future<void> _runConnectionTest() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _testService.testDatabaseConnection();
      setState(() {
        _testResults = results;
      });
    } catch (e) {
      setState(() {
        _testResults = {'error': e.toString()};
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runTableAccessTest() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _testService.testTableAccess();
      setState(() {
        _testResults = results;
      });
    } catch (e) {
      setState(() {
        _testResults = {'error': e.toString()};
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('Database Connection Test'),
        backgroundColor: SwiftDashColors.darkBlue,
        foregroundColor: SwiftDashColors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supabase Configuration',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('URL', SupabaseConfig.supabaseUrl),
                    const SizedBox(height: 8),
                    _buildInfoRow('Anon Key', '${SupabaseConfig.supabaseAnonKey.substring(0, 20)}...'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Test Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _runConnectionTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SwiftDashColors.lightBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Test Connection'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _runTableAccessTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SwiftDashColors.darkBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Test Tables'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Loading Indicator
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: SwiftDashColors.darkBlue,
                ),
              ),
            
            // Test Results
            if (_testResults != null && !_isLoading)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.assessment,
                            color: SwiftDashColors.darkBlue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Test Results',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: SwiftDashColors.darkBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ..._testResults!.entries.map((entry) => _buildResultRow(
                        entry.key,
                        entry.value.toString(),
                      )).toList(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: SwiftDashColors.textGrey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(String test, String result) {
    final isSuccess = result.toLowerCase().contains('success') || 
                     result.toLowerCase().contains('accessible') ||
                     result.toLowerCase().contains('connected');
    final isError = result.toLowerCase().contains('error');
    
    Color color = SwiftDashColors.textGrey;
    IconData icon = Icons.info;
    
    if (isSuccess) {
      color = SwiftDashColors.successGreen;
      icon = Icons.check_circle;
    } else if (isError) {
      color = SwiftDashColors.dangerRed;
      icon = Icons.error;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  test.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: SwiftDashColors.darkBlue,
                    fontSize: 12,
                  ),
                ),
                Text(
                  result,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}