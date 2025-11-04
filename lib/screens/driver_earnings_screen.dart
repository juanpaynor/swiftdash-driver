import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/driver.dart';
import '../services/driver_earnings_service.dart';
import '../core/colors.dart';
import '../models/cash_remittance.dart';

class DriverEarningsScreen extends StatefulWidget {
  final Driver driver;

  const DriverEarningsScreen({
    Key? key,
    required this.driver,
  }) : super(key:key);

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DriverEarningsService _earningsService = DriverEarningsService();
  
  EarningsSummary? _summary;
  List<DriverEarning> _recentEarnings = [];
  bool _isLoading = true;
  String _selectedPeriod = 'week'; // 'today', 'week', 'month'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadEarningsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEarningsData() async {
    setState(() => _isLoading = true);
    
    try {
      final summary = await _earningsService.getEarningsSummary(widget.driver.id);
      final recent = await _earningsService.getEarningsHistory(
        driverId: widget.driver.id,
        limit: 50,
      );
      
      setState(() {
        _summary = summary;
        _recentEarnings = recent;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading earnings: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwiftDashColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'My Earnings',
          style: TextStyle(
            color: SwiftDashColors.darkBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: SwiftDashColors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: SwiftDashColors.darkBlue),
        bottom: TabBar(
          controller: _tabController,
          labelColor: SwiftDashColors.lightBlue,
          unselectedLabelColor: SwiftDashColors.mediumGray,
          indicatorColor: SwiftDashColors.lightBlue,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'History'),
            Tab(text: 'Insights'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildHistoryTab(),
                _buildInsightsTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    if (_summary == null) {
      return const Center(child: Text('No earnings data available'));
    }

    return RefreshIndicator(
      onRefresh: _loadEarningsData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period selector
            Row(
              children: [
                _buildPeriodButton('Today', 'today'),
                const SizedBox(width: 8),
                _buildPeriodButton('This Week', 'week'),
                const SizedBox(width: 8),
                _buildPeriodButton('This Month', 'month'),
              ],
            ),
            const SizedBox(height: 20),
            
            // Main earnings card
            _buildEarningsCard(),
            const SizedBox(height: 16),
            
            // Quick stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Deliveries',
                    _getDeliveriesForPeriod().toString(),
                    Icons.local_shipping,
                    SwiftDashColors.lightBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Avg/Delivery',
                    '₱${_summary!.averageEarningsPerDelivery.toStringAsFixed(0)}',
                    Icons.trending_up,
                    SwiftDashColors.successGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Earnings breakdown
            _buildEarningsBreakdown(),
            const SizedBox(height: 16),
            
            // Recent transactions preview
            _buildRecentTransactionsPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      onRefresh: _loadEarningsData,
      child: _recentEarnings.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Color(0xFF718096)),
                  SizedBox(height: 16),
                  Text(
                    'No earnings history yet',
                    style: TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Complete deliveries to start earning',
                    style: TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _recentEarnings.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final earning = _recentEarnings[index];
                return _buildEarningHistoryItem(earning);
              },
            ),
    );
  }

  Widget _buildInsightsTab() {
    if (_summary == null || _recentEarnings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insights, size: 64, color: Color(0xFF718096)),
            SizedBox(height: 16),
            Text(
              'Not enough data for insights',
              style: TextStyle(
                color: Color(0xFF718096),
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Complete more deliveries to see insights',
              style: TextStyle(
                color: Color(0xFF718096),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInsightCard(
            'Payment Methods',
            _buildPaymentMethodsBreakdown(),
          ),
          const SizedBox(height: 16),
          _buildInsightCard(
            'Earnings Composition',
            _buildEarningsComposition(),
          ),
          const SizedBox(height: 16),
          _buildInsightCard(
            'Weekly Comparison',
            _buildWeeklyComparison(),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String label, String period) {
    final isSelected = _selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPeriod = period),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? SwiftDashColors.lightBlue : SwiftDashColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? SwiftDashColors.lightBlue : SwiftDashColors.lightGray,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : SwiftDashColors.mediumGray,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEarningsCard() {
    final earnings = _getEarningsForPeriod();
    final previousEarnings = _getPreviousPeriodEarnings();
    final difference = earnings - previousEarnings;
    final percentChange = previousEarnings > 0 ? (difference / previousEarnings * 100) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SwiftDashColors.lightBlue, SwiftDashColors.darkBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: SwiftDashColors.lightBlue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedPeriod == 'today'
                ? 'Today\'s Earnings'
                : _selectedPeriod == 'week'
                    ? 'This Week'
                    : 'This Month',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₱${earnings.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (previousEarnings > 0)
            Row(
              children: [
                Icon(
                  difference >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: difference >= 0 ? SwiftDashColors.successGreen : SwiftDashColors.errorRed,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  '${difference >= 0 ? '+' : ''}₱${difference.toStringAsFixed(2)} (${percentChange.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    color: difference >= 0 ? SwiftDashColors.successGreen : SwiftDashColors.errorRed,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'vs last ${_selectedPeriod == 'today' ? 'day' : _selectedPeriod}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SwiftDashColors.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: SwiftDashColors.mediumGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: SwiftDashColors.darkBlue,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsBreakdown() {
    // Calculate breakdown from recent earnings
    double totalBase = 0;
    double totalDistance = 0;
    double totalSurge = 0;
    double totalTips = 0;
    
    final periodEarnings = _getEarningsForCurrentPeriod();
    for (final earning in periodEarnings) {
      totalBase += earning.baseEarnings;
      totalDistance += earning.distanceEarnings;
      totalSurge += earning.surgeEarnings;
      totalTips += earning.tips;
    }
    
    final total = totalBase + totalDistance + totalSurge + totalTips;
    
    if (total == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SwiftDashColors.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Earnings Breakdown',
            style: TextStyle(
              color: SwiftDashColors.darkBlue,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildBreakdownRow('Base Fare', totalBase, total, SwiftDashColors.lightBlue),
          const SizedBox(height: 12),
          _buildBreakdownRow('Distance', totalDistance, total, SwiftDashColors.accentTeal),
          if (totalSurge > 0) ...[
            const SizedBox(height: 12),
            _buildBreakdownRow('Surge', totalSurge, total, SwiftDashColors.warningOrange),
          ],
          if (totalTips > 0) ...[
            const SizedBox(height: 12),
            _buildBreakdownRow('Tips', totalTips, total, SwiftDashColors.successGreen),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, double amount, double total, Color color) {
    final percentage = total > 0 ? (amount / total * 100) : 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: SwiftDashColors.mediumGray,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Text(
              '₱${amount.toStringAsFixed(2)} (${percentage.toStringAsFixed(0)}%)',
              style: const TextStyle(
                color: SwiftDashColors.darkBlue,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: SwiftDashColors.lightGray,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsPreview() {
    if (_recentEarnings.isEmpty) {
      return const SizedBox.shrink();
    }

    final preview = _recentEarnings.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SwiftDashColors.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Transactions',
                style: TextStyle(
                  color: SwiftDashColors.darkBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () => _tabController.animateTo(1),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...preview.map((earning) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildTransactionRow(earning),
          )),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(DriverEarning earning) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getPaymentMethodColor(earning.paymentMethod).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _getPaymentMethodIcon(earning.paymentMethod),
            color: _getPaymentMethodColor(earning.paymentMethod),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMM dd, yyyy • hh:mm a').format(earning.earningsDate),
                style: const TextStyle(
                  color: SwiftDashColors.darkBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                earning.paymentMethod.displayName,
                style: const TextStyle(
                  color: SwiftDashColors.mediumGray,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₱${earning.totalEarnings.toStringAsFixed(2)}',
              style: const TextStyle(
                color: SwiftDashColors.successGreen,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (earning.tips > 0)
              Text(
                '+₱${earning.tips.toStringAsFixed(2)} tip',
                style: const TextStyle(
                  color: SwiftDashColors.mediumGray,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildEarningHistoryItem(DriverEarning earning) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SwiftDashColors.lightGray),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getPaymentMethodColor(earning.paymentMethod).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getPaymentMethodIcon(earning.paymentMethod),
                  color: _getPaymentMethodColor(earning.paymentMethod),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, MMM dd, yyyy').format(earning.earningsDate),
                      style: const TextStyle(
                        color: SwiftDashColors.darkBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${earning.paymentMethod.displayName} • ${DateFormat('hh:mm a').format(earning.createdAt)}',
                      style: const TextStyle(
                        color: SwiftDashColors.mediumGray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₱${earning.totalEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: SwiftDashColors.successGreen,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Net: ₱${earning.driverNetEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: SwiftDashColors.mediumGray,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: SwiftDashColors.lightGray, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildEarningDetail('Base', earning.baseEarnings),
              _buildEarningDetail('Distance', earning.distanceEarnings),
              if (earning.surgeEarnings > 0)
                _buildEarningDetail('Surge', earning.surgeEarnings),
              if (earning.tips > 0)
                _buildEarningDetail('Tips', earning.tips),
              _buildEarningDetail('Commission', -earning.platformCommission, isNegative: true),
            ],
          ),
          if (earning.isRemittanceRequired) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SwiftDashColors.warningOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber, size: 16, color: SwiftDashColors.warningOrange),
                  const SizedBox(width: 8),
                  Text(
                    'Remittance due: ${earning.remittanceDeadline != null ? DateFormat('MMM dd, hh:mm a').format(earning.remittanceDeadline!) : 'Soon'}',
                    style: const TextStyle(
                      color: SwiftDashColors.warningOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEarningDetail(String label, double amount, {bool isNegative = false}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SwiftDashColors.mediumGray,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${isNegative ? '-' : ''}₱${amount.abs().toStringAsFixed(0)}',
          style: TextStyle(
            color: isNegative ? SwiftDashColors.errorRed : SwiftDashColors.darkBlue,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildInsightCard(String title, Widget content) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SwiftDashColors.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: SwiftDashColors.darkBlue,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsBreakdown() {
    final Map<PaymentMethod, double> breakdown = {};
    
    for (final earning in _recentEarnings) {
      breakdown[earning.paymentMethod] = 
          (breakdown[earning.paymentMethod] ?? 0) + earning.totalEarnings;
    }
    
    if (breakdown.isEmpty) {
      return const Text('No data available');
    }
    
    return Column(
      children: breakdown.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(
                _getPaymentMethodIcon(entry.key),
                color: _getPaymentMethodColor(entry.key),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.key.displayName,
                  style: const TextStyle(
                    color: SwiftDashColors.darkBlue,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '₱${entry.value.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: SwiftDashColors.darkBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEarningsComposition() {
    double totalBase = 0;
    double totalDistance = 0;
    double totalSurge = 0;
    double totalTips = 0;
    
    for (final earning in _recentEarnings) {
      totalBase += earning.baseEarnings;
      totalDistance += earning.distanceEarnings;
      totalSurge += earning.surgeEarnings;
      totalTips += earning.tips;
    }
    
    final total = totalBase + totalDistance + totalSurge + totalTips;
    
    return Column(
      children: [
        _buildCompositionRow('Base Fare', totalBase, total, SwiftDashColors.lightBlue),
        _buildCompositionRow('Distance', totalDistance, total, SwiftDashColors.accentTeal),
        if (totalSurge > 0) _buildCompositionRow('Surge', totalSurge, total, SwiftDashColors.warningOrange),
        if (totalTips > 0) _buildCompositionRow('Tips', totalTips, total, SwiftDashColors.successGreen),
      ],
    );
  }

  Widget _buildCompositionRow(String label, double amount, double total, Color color) {
    final percentage = total > 0 ? (amount / total * 100) : 0.0;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: SwiftDashColors.darkBlue,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: SwiftDashColors.mediumGray,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: SwiftDashColors.darkBlue,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyComparison() {
    if (_summary == null) {
      return const Text('No data available');
    }
    
    final thisWeek = _summary!.weekEarnings;
    final lastWeek = _getPreviousPeriodEarnings(); // This would need proper implementation
    final difference = thisWeek - lastWeek;
    final percentChange = lastWeek > 0 ? (difference / lastWeek * 100) : 0.0;
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'This Week',
              style: TextStyle(
                color: SwiftDashColors.mediumGray,
                fontSize: 14,
              ),
            ),
            Text(
              '₱${thisWeek.toStringAsFixed(2)}',
              style: const TextStyle(
                color: SwiftDashColors.darkBlue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Last Week',
              style: TextStyle(
                color: SwiftDashColors.mediumGray,
                fontSize: 14,
              ),
            ),
            Text(
              '₱${lastWeek.toStringAsFixed(2)}',
              style: const TextStyle(
                color: SwiftDashColors.mediumGray,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: SwiftDashColors.lightGray),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  difference >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: difference >= 0 ? SwiftDashColors.successGreen : SwiftDashColors.errorRed,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Change',
                  style: TextStyle(
                    color: SwiftDashColors.mediumGray,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Text(
              '${difference >= 0 ? '+' : ''}₱${difference.toStringAsFixed(2)} (${percentChange.toStringAsFixed(1)}%)',
              style: TextStyle(
                color: difference >= 0 ? SwiftDashColors.successGreen : SwiftDashColors.errorRed,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Helper methods
  double _getEarningsForPeriod() {
    if (_summary == null) return 0.0;
    
    switch (_selectedPeriod) {
      case 'today':
        return _summary!.todayEarnings;
      case 'week':
        return _summary!.weekEarnings;
      case 'month':
        return _summary!.monthEarnings;
      default:
        return 0.0;
    }
  }

  int _getDeliveriesForPeriod() {
    if (_summary == null) return 0;
    
    switch (_selectedPeriod) {
      case 'today':
        return _summary!.todayDeliveries;
      case 'week':
        return _summary!.weekDeliveries;
      case 'month':
        return _summary!.monthDeliveries;
      default:
        return 0;
    }
  }

  double _getPreviousPeriodEarnings() {
    // This is a simplified version - you'd need to implement proper previous period calculation
    final current = _getEarningsForPeriod();
    return current * 0.8; // Mock: assume 80% of current
  }

  List<DriverEarning> _getEarningsForCurrentPeriod() {
    final now = DateTime.now();
    
    return _recentEarnings.where((earning) {
      switch (_selectedPeriod) {
        case 'today':
          return earning.earningsDate.day == now.day &&
                 earning.earningsDate.month == now.month &&
                 earning.earningsDate.year == now.year;
        case 'week':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return earning.earningsDate.isAfter(weekStart);
        case 'month':
          return earning.earningsDate.month == now.month &&
                 earning.earningsDate.year == now.year;
        default:
          return false;
      }
    }).toList();
  }

  IconData _getPaymentMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.money;
      case PaymentMethod.card:
        return Icons.credit_card;
    }
  }

  Color _getPaymentMethodColor(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return SwiftDashColors.successGreen;
      case PaymentMethod.card:
        return SwiftDashColors.lightBlue;
    }
  }
}
