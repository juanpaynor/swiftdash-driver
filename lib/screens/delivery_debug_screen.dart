import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class DeliveryDebugScreen extends StatefulWidget {
  const DeliveryDebugScreen({super.key});

  @override
  State<DeliveryDebugScreen> createState() => _DeliveryDebugScreenState();
}

class _DeliveryDebugScreenState extends State<DeliveryDebugScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<dynamic> _deliveries = [];
  String _debugInfo = 'Ready to test...';
  bool _isLoading = false;

  Future<void> _testBasicQuery() async {
    setState(() {
      _isLoading = true;
      _debugInfo = 'Testing basic query...';
    });

    try {
      // Test 1: Basic query
      final response = await _supabase
          .from('deliveries')
          .select('*')
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(5);

      setState(() {
        _deliveries = response;
        _debugInfo = 'SUCCESS: Found ${response.length} pending deliveries';
      });
      
    } catch (e) {
      setState(() {
        _debugInfo = 'ERROR: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testRealtimeConnection() async {
    setState(() {
      _debugInfo = 'Testing realtime connection...';
    });

    try {
      final channel = _supabase
          .channel('test-channel')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'deliveries',
            callback: (payload) {
              setState(() {
                _debugInfo = 'REALTIME SUCCESS: Received insert event\n${payload.newRecord}';
              });
            },
          );

      await channel.subscribe();
      
      setState(() {
        _debugInfo = 'Realtime channel subscribed. Waiting for events...';
      });

    } catch (e) {
      setState(() {
        _debugInfo = 'REALTIME ERROR: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Debug'),
        backgroundColor: SwiftDashColors.darkBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Debug Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Debug Info:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _debugInfo,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Test Buttons
            ElevatedButton(
              onPressed: _isLoading ? null : _testBasicQuery,
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Test Basic Query'),
            ),
            
            const SizedBox(height: 8),
            
            ElevatedButton(
              onPressed: _testRealtimeConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: SwiftDashColors.lightBlue,
              ),
              child: const Text('Test Realtime Connection'),
            ),
            
            const SizedBox(height: 16),
            
            // Deliveries List
            if (_deliveries.isNotEmpty) ...[
              Text(
                'Found Deliveries:',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _deliveries.length,
                  itemBuilder: (context, index) {
                    final delivery = _deliveries[index];
                    return Card(
                      child: ListTile(
                        title: Text(delivery['pickup_address'] ?? 'N/A'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Status: ${delivery['status']}'),
                            Text('Price: ₱${delivery['total_price']}'),
                            Text('Created: ${delivery['created_at']}'),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}