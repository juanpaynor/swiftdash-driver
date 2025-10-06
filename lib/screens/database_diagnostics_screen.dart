import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/database_diagnostic_service.dart';
import '../services/database_test_service.dart';
import '../core/supabase_config.dart';

class DatabaseDiagnosticsScreen extends StatefulWidget {
  const DatabaseDiagnosticsScreen({super.key});

  @override
  State<DatabaseDiagnosticsScreen> createState() => _DatabaseDiagnosticsScreenState();
}

class _DatabaseDiagnosticsScreenState extends State<DatabaseDiagnosticsScreen> {
  final DatabaseDiagnosticService _diagnosticService = DatabaseDiagnosticService();
  final _testService = DatabaseTestService();
  
  Map<String, dynamic>? _lastDiagnostic;
  Map<String, dynamic>? _lastStatusTest;
  Map<String, dynamic>? _lastLocationTest;
  Map<String, dynamic>? _currentDriverStatus;
  Map<String, dynamic>? _connectionTestResults;
  Map<String, dynamic>? _userTypeCheck;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _runInitialDiagnostics();
  }

  Future<void> _runInitialDiagnostics() async {
    setState(() => _isLoading = true);
    
    try {
      final diagnostic = await _diagnosticService.runDatabaseDiagnostics();
      final driverStatus = await _diagnosticService.getDriverStatus();
      final connectionResults = await _testService.testDatabaseConnection();
      final userTypeCheck = await _diagnosticService.checkCurrentUserType();
      
      setState(() {
        _lastDiagnostic = diagnostic;
        _currentDriverStatus = driverStatus;
        _connectionTestResults = connectionResults;
        _userTypeCheck = userTypeCheck;
      });
    } catch (e) {
      _showError('Initial diagnostics failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runDatabaseDiagnostics() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await _diagnosticService.runDatabaseDiagnostics();
      setState(() => _lastDiagnostic = result);
      _showSuccess('Database diagnostics completed');
    } catch (e) {
      _showError('Diagnostics failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testStatusUpdate() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await _diagnosticService.testDriverStatusUpdate();
      setState(() => _lastStatusTest = result);
      
      if (result['success'] == true) {
        _showSuccess('Status update test completed successfully');
      } else {
        _showError('Status update test failed');
      }
    } catch (e) {
      _showError('Status test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testLocationUpdate() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await _diagnosticService.testLocationUpdate();
      setState(() => _lastLocationTest = result);
      
      if (result['success'] == true) {
        _showSuccess('Location update test completed successfully');
      } else {
        _showError('Location update test failed');
      }
    } catch (e) {
      _showError('Location test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeDriverStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await _diagnosticService.initializeDriverCurrentStatus();
      
      if (result['success'] == true) {
        _showSuccess(result['message'] ?? 'Driver status initialized');
        // Refresh diagnostics
        await _runDatabaseDiagnostics();
      } else {
        _showError('Initialization failed');
      }
    } catch (e) {
      _showError('Initialization failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkUserType() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await _diagnosticService.checkCurrentUserType();
      setState(() => _userTypeCheck = result);
      
      if (result['is_driver'] == true) {
        _showSuccess('✅ Valid driver account detected');
      } else {
        _showError(result['message'] ?? 'User type check failed');
      }
    } catch (e) {
      _showError('User type check failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshDriverStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final status = await _diagnosticService.getDriverStatus();
      setState(() => _currentDriverStatus = status);
      _showSuccess('Driver status refreshed');
    } catch (e) {
      _showError('Refresh failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccess('Copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Diagnostics'),
        backgroundColor: SwiftDashColors.darkBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _runInitialDiagnostics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action Buttons
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Driver Status Tests',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: SwiftDashColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _checkUserType,
                                icon: const Icon(Icons.person_search),
                                label: const Text('Check User Type'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SwiftDashColors.warningOrange,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _runDatabaseDiagnostics,
                                icon: const Icon(Icons.storage),
                                label: const Text('Run Diagnostics'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SwiftDashColors.lightBlue,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _testStatusUpdate,
                                icon: const Icon(Icons.toggle_on),
                                label: const Text('Test Status Update'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SwiftDashColors.warningOrange,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _testLocationUpdate,
                                icon: const Icon(Icons.location_on),
                                label: const Text('Test Location Update'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SwiftDashColors.successGreen,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _initializeDriverStatus,
                                icon: const Icon(Icons.add),
                                label: const Text('Initialize Status'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SwiftDashColors.darkBlue,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _refreshDriverStatus,
                                icon: const Icon(Icons.person),
                                label: const Text('Refresh Driver Status'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // User Type Check Results
                  if (_userTypeCheck != null) ...[
                    _buildSection(
                      'User Type Check',
                      _userTypeCheck!,
                      _userTypeCheck!['is_driver'] == true ? SwiftDashColors.successGreen : SwiftDashColors.dangerRed,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Current Driver Status
                  if (_currentDriverStatus != null) ...[
                    _buildSection(
                      'Current Driver Status',
                      _currentDriverStatus!,
                      SwiftDashColors.lightBlue,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Database Diagnostics
                  if (_lastDiagnostic != null) ...[
                    _buildSection(
                      'Database Diagnostics',
                      _lastDiagnostic!,
                      SwiftDashColors.successGreen,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Connection Test Results
                  if (_connectionTestResults != null) ...[
                    _buildSection(
                      'Connection Test Results',
                      _connectionTestResults!,
                      SwiftDashColors.darkBlue,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Status Test Results
                  if (_lastStatusTest != null) ...[
                    _buildSection(
                      'Status Update Test Results',
                      _lastStatusTest!,
                      _lastStatusTest!['success'] == true ? SwiftDashColors.successGreen : SwiftDashColors.dangerRed,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Location Test Results
                  if (_lastLocationTest != null) ...[
                    _buildSection(
                      'Location Update Test Results',
                      _lastLocationTest!,
                      _lastLocationTest!['success'] == true ? SwiftDashColors.successGreen : SwiftDashColors.dangerRed,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Instructions Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Database Schema Setup Required',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: SwiftDashColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'If you see errors, you may need to run the optimized realtime migration SQL:',
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
                              '''Run optimized_realtime_migration.sql in your Supabase SQL Editor to create:
- driver_current_status table
- driver_location_history table  
- Enhanced RLS policies
- Proper indexes and triggers''',
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

  Widget _buildSection(String title, Map<String, dynamic> data, Color color) {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    
    return Card(
      elevation: 4,
      child: ExpansionTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary
                if (data.containsKey('connection_status')) ...[
                  _buildStatusChip('Connection', data['connection_status'].toString()),
                  const SizedBox(height: 8),
                ],
                
                if (data.containsKey('success')) ...[
                  _buildStatusChip('Success', data['success'].toString()),
                  const SizedBox(height: 8),
                ],
                
                if (data.containsKey('errors') && data['errors'] is List && (data['errors'] as List).isNotEmpty) ...[
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...(data['errors'] as List).map((error) => Text('• $error', style: const TextStyle(color: Colors.red))),
                  const SizedBox(height: 16),
                ],
                
                // Raw JSON Data
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Raw Data:', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: () => _copyToClipboard(jsonString),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      jsonString,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    Color color;
    if (value == 'connected' || value == 'true' || value == 'found') {
      color = SwiftDashColors.successGreen;
    } else if (value == 'unknown' || value == 'not_found') {
      color = SwiftDashColors.warningOrange;
    } else {
      color = SwiftDashColors.dangerRed;
    }
    
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
    );
  }
}