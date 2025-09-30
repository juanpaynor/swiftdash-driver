import 'package:flutter/material.dart';
import '../services/database_test_service.dart';
import '../core/supabase_config.dart';

class DatabaseDiagnosticsScreen extends StatefulWidget {
  const DatabaseDiagnosticsScreen({super.key});

  @override
  State<DatabaseDiagnosticsScreen> createState() => _DatabaseDiagnosticsScreenState();
}

class _DatabaseDiagnosticsScreenState extends State<DatabaseDiagnosticsScreen> {
  final _testService = DatabaseTestService();
  Map<String, dynamic>? _testResults;
  bool _isLoading = false;

  Future<void> _runDiagnostics() async {
    setState(() {
      _isLoading = true;
      _testResults = null;
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

  Future<void> _testSignup() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _testService.testSignupProcess(
        email: 'test+${DateTime.now().millisecondsSinceEpoch}@example.com',
        password: 'test123456',
        firstName: 'Test',
        lastName: 'Driver',
        phoneNumber: '+1234567890',
      );
      
      setState(() {
        _testResults = results;
      });
    } catch (e) {
      setState(() {
        _testResults = {'signup_test_error': e.toString()};
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
      appBar: AppBar(
        title: const Text('Database Diagnostics'),
        backgroundColor: SwiftDashColors.darkBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Database Connection Tests',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _runDiagnostics,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SwiftDashColors.lightBlue,
                            ),
                            child: const Text('Test Connection'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _testSignup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SwiftDashColors.warningOrange,
                            ),
                            child: const Text('Test Signup'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_testResults != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Results',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: SwiftDashColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _testResults!.entries.map((entry) {
                                final isError = entry.value.toString().toLowerCase().contains('error');
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        isError ? Icons.error : Icons.check_circle,
                                        color: isError ? SwiftDashColors.dangerRed : SwiftDashColors.successGreen,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.key,
                                              style: const TextStyle(fontWeight: FontWeight.w500),
                                            ),
                                            Text(
                                              entry.value.toString(),
                                              style: TextStyle(
                                                color: isError ? SwiftDashColors.dangerRed : SwiftDashColors.textGrey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            // Instructions Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RLS Policy Fix',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SwiftDashColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'If you see RLS policy errors, run this SQL in your Supabase SQL Editor:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SwiftDashColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SwiftDashColors.backgroundGrey,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SwiftDashColors.textGrey.withOpacity(0.3)),
                      ),
                      child: const Text(
                        '''-- Enable RLS on user_profiles
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert their own profile
CREATE POLICY "Users can insert own profile" ON user_profiles
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = id);

-- Allow users to read their own profile
CREATE POLICY "Users can read own profile" ON user_profiles
FOR SELECT TO authenticated
USING (auth.uid() = id);

-- Allow users to update their own profile
CREATE POLICY "Users can update own profile" ON user_profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);''',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: SwiftDashColors.darkBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}