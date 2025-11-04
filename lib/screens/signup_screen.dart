import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../services/auth_service.dart';
import '../services/vehicle_type_service.dart';
import '../services/otp_service.dart';
import '../screens/otp_verification_screen.dart';

import '../models/vehicle_type.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _authService = AuthService();
  final _vehicleTypeService = VehicleTypeService();
  
  // Local state variables
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // State variables for vehicle types and form
  bool _acceptTerms = false;
  List<VehicleType> _vehicleTypes = [];
  VehicleType? _selectedVehicleType;
  bool _isLoadingVehicleTypes = false;
  String? _vehicleTypesError;

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _licenseNumberController.dispose();
    _vehicleModelController.dispose();
    super.dispose();
  }

  IconData _getVehicleIcon(String vehicleTypeName) {
    final name = vehicleTypeName.toLowerCase();
    if (name.contains('motorcycle') || name.contains('bike')) {
      return Icons.two_wheeler;
    } else if (name.contains('van')) {
      return Icons.airport_shuttle;
    } else if (name.contains('truck')) {
      return Icons.local_shipping;
    } else if (name.contains('car')) {
      return Icons.directions_car;
    } else {
      return Icons.local_shipping_outlined;
    }
  }

  Future<void> _loadVehicleTypes() async {
    setState(() {
      _isLoadingVehicleTypes = true;
      _vehicleTypesError = null;
    });
    
    try {
      print('Loading vehicle types...');
      final vehicleTypes = await _vehicleTypeService.getActiveVehicleTypes();
      print('Loaded ${vehicleTypes.length} vehicle types');
      
      setState(() {
        _vehicleTypes = vehicleTypes;
        _isLoadingVehicleTypes = false;
      });
      
      if (vehicleTypes.isEmpty) {
        setState(() {
          _vehicleTypesError = 'No vehicle types available. Please contact support.';
        });
      }
    } catch (e) {
      print('Error loading vehicle types: $e');
      setState(() {
        _vehicleTypesError = 'Failed to load vehicle types: $e';
        _isLoadingVehicleTypes = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load vehicle types: $e'),
            backgroundColor: SwiftDashColors.dangerRed,
            action: SnackBarAction(
              label: 'Retry',
              textColor: SwiftDashColors.white,
              onPressed: _loadVehicleTypes,
            ),
          ),
        );
      }
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedVehicleType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a vehicle type'),
          backgroundColor: SwiftDashColors.warningOrange,
        ),
      );
      return;
    }

    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Terms and Conditions'),
          backgroundColor: SwiftDashColors.warningOrange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Step 1: Validate phone number format
      final otpService = OTPService();
      final phoneNumber = _phoneController.text.trim();
      
      if (!otpService.isValidPhoneNumber(phoneNumber)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid phone number format. Please use Philippine mobile number (e.g., 09171234567)'),
              backgroundColor: SwiftDashColors.dangerRed,
            ),
          );
        }
        return;
      }

      // Step 2: Send OTP to phone number via Supabase Auth
      final sendResult = await otpService.sendOTP(phoneNumber: phoneNumber);
      
      if (!sendResult.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send OTP: ${sendResult.message}'),
              backgroundColor: SwiftDashColors.dangerRed,
            ),
          );
        }
        return;
      }

      // Step 3: Navigate to OTP verification screen
      if (mounted) {
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (context) => OTPVerificationScreen(
              phoneNumber: phoneNumber,
              registrationData: {
                'email': _emailController.text.trim(),
                'firstName': _firstNameController.text.trim(),
                'lastName': _lastNameController.text.trim(),
                'phoneNumber': phoneNumber,
                'vehicleTypeId': _selectedVehicleType?.id,
                'licenseNumber': _licenseNumberController.text.trim().isNotEmpty 
                    ? _licenseNumberController.text.trim() 
                    : null,
                'vehicleModel': _vehicleModelController.text.trim().isNotEmpty 
                    ? _vehicleModelController.text.trim() 
                    : null,
              },
            ),
          ),
        );

        // Step 4: If OTP verified, create driver profile
        // User is already authenticated via OTP, just need to create profiles
        if (result != null && result['verified'] == true && result['userId'] != null) {
          await _authService.createDriverProfileForOTPUser(
            userId: result['userId'],
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            phoneNumber: phoneNumber,
            email: _emailController.text.trim().isNotEmpty 
                ? _emailController.text.trim() 
                : null,
            vehicleTypeId: _selectedVehicleType?.id,
            licenseNumber: _licenseNumberController.text.trim().isNotEmpty 
                ? _licenseNumberController.text.trim() 
                : null,
            vehicleModel: _vehicleModelController.text.trim().isNotEmpty 
                ? _vehicleModelController.text.trim() 
                : null,
          );

          if (mounted) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account created successfully! Welcome to SwiftDash!'),
                backgroundColor: SwiftDashColors.successGreen,
                duration: Duration(seconds: 3),
              ),
            );

            // AuthWrapper will automatically detect the logged-in user and navigate to dashboard
          }
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign up failed: ${error.toString()}'),
            backgroundColor: SwiftDashColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwiftDashColors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back, color: SwiftDashColors.white, size: 20),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: SwiftDashColors.lightBlue.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/logos/Swiftdash_Driver.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.person_add_rounded,
                              color: SwiftDashColors.white,
                              size: 40,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Title
                Text(
                  'Become a Driver',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    foreground: Paint()
                      ..shader = LinearGradient(
                        colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                      ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Start earning with flexible deliveries',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: SwiftDashColors.textGrey,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Name Fields Row
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _firstNameController,
                        label: 'First Name',
                        icon: Icons.person_outlined,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _lastNameController,
                        label: 'Last Name',
                        icon: Icons.person_outlined,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Email Field
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Phone Field
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (value.length < 10) {
                      return 'Please enter a valid phone number';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Password Field
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  icon: Icons.lock_outlined,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: SwiftDashColors.textGrey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Confirm Password Field
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  icon: Icons.lock_outlined,
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: SwiftDashColors.textGrey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 24),
                
                // Vehicle Type Section Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.local_shipping_outlined,
                        color: SwiftDashColors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Vehicle Type',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            foreground: Paint()
                              ..shader = LinearGradient(
                                colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                              ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                          ),
                        ),
                        Text(
                          'Required - Choose your vehicle',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SwiftDashColors.dangerRed,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Vehicle Type List
                if (_isLoadingVehicleTypes)
                  Container(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.lightBlue),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading vehicle types...',
                            style: TextStyle(color: SwiftDashColors.textGrey),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_vehicleTypesError != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: SwiftDashColors.dangerRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: SwiftDashColors.dangerRed.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.error_outline, color: SwiftDashColors.dangerRed, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load vehicle types',
                          style: TextStyle(
                            color: SwiftDashColors.dangerRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _vehicleTypesError!,
                          style: TextStyle(
                            color: SwiftDashColors.dangerRed,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadVehicleTypes,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SwiftDashColors.dangerRed,
                            foregroundColor: SwiftDashColors.white,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_vehicleTypes.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: SwiftDashColors.warningOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: SwiftDashColors.warningOrange.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, color: SwiftDashColors.warningOrange, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'No vehicle types available',
                          style: TextStyle(
                            color: SwiftDashColors.warningOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please contact support',
                          style: TextStyle(
                            color: SwiftDashColors.textGrey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _vehicleTypes.length,
                    itemBuilder: (context, index) {
                      final vehicleType = _vehicleTypes[index];
                      final isSelected = _selectedVehicleType?.id == vehicleType.id;
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedVehicleType = vehicleType;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? SwiftDashColors.lightBlue.withOpacity(0.1)
                                : SwiftDashColors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected 
                                  ? SwiftDashColors.lightBlue
                                  : SwiftDashColors.backgroundGrey,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: SwiftDashColors.lightBlue.withOpacity(0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: SwiftDashColors.darkBlue.withOpacity(0.05),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Row(
                            children: [
                              // Vehicle Icon
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? LinearGradient(
                                          colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                                        )
                                      : null,
                                  color: isSelected ? null : SwiftDashColors.backgroundGrey,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getVehicleIcon(vehicleType.name),
                                  size: 30,
                                  color: isSelected 
                                      ? SwiftDashColors.white 
                                      : SwiftDashColors.textGrey,
                                ),
                              ),
                              const SizedBox(width: 16),
                              
                              // Vehicle Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vehicleType.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected 
                                            ? SwiftDashColors.darkBlue 
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Max Weight: ${vehicleType.formattedMaxWeight}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: SwiftDashColors.textGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${vehicleType.formattedPricePerKm}/km',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: SwiftDashColors.successGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Selection Indicator
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: isSelected
                                      ? LinearGradient(
                                          colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                                        )
                                      : null,
                                  border: Border.all(
                                    color: isSelected 
                                        ? Colors.transparent 
                                        : SwiftDashColors.backgroundGrey,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: SwiftDashColors.white,
                                        size: 18,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                
                const SizedBox(height: 24),
                
                // Additional Vehicle Information Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: SwiftDashColors.backgroundGrey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: SwiftDashColors.lightBlue.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Additional Vehicle Details',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: SwiftDashColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Optional - Complete later in profile',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SwiftDashColors.textGrey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // License Number and Vehicle Model Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _licenseNumberController,
                              label: 'License Number',
                              icon: Icons.badge_outlined,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _vehicleModelController,
                              label: 'Vehicle Model',
                              icon: Icons.directions_car,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Terms and Conditions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acceptTerms,
                      onChanged: (value) {
                        setState(() {
                          _acceptTerms = value ?? false;
                        });
                      },
                      activeColor: SwiftDashColors.lightBlue,
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'I agree to the ',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SwiftDashColors.textGrey,
                          ),
                          children: [
                            TextSpan(
                              text: 'Terms and Conditions',
                              style: TextStyle(
                                color: SwiftDashColors.lightBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(
                                color: SwiftDashColors.lightBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Sign Up Button
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: SwiftDashColors.darkBlue.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(SwiftDashColors.white),
                            ),
                          )
                        : Text(
                            'Create Account',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: SwiftDashColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Already have account
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SwiftDashColors.textGrey,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          color: SwiftDashColors.lightBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: SwiftDashColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: SwiftDashColors.darkBlue.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: SwiftDashColors.lightBlue),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: SwiftDashColors.white,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}