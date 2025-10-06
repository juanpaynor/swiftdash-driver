import 'package:flutter/material.dart';
import '../core/supabase_config.dart';
import '../services/auth_service.dart';
import '../services/vehicle_type_service.dart';
import '../models/vehicle_type.dart';
import '../screens/debug_vehicle_types_screen.dart';

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
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
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
      await _authService.signUpDriver(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
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
        // No need to manually navigate since the user is now authenticated
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
      backgroundColor: SwiftDashColors.backgroundGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: SwiftDashColors.darkBlue),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Join SwiftDash',
          style: TextStyle(
            color: SwiftDashColors.darkBlue,
            fontWeight: FontWeight.bold,
          ),
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
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SwiftDashColors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: SwiftDashColors.darkBlue.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [SwiftDashColors.darkBlue, SwiftDashColors.lightBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.person_add,
                          color: SwiftDashColors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Become a Driver',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: SwiftDashColors.darkBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start earning with flexible deliveries',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SwiftDashColors.textGrey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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
                
                // Vehicle Information Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: SwiftDashColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: SwiftDashColors.darkBlue.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            color: SwiftDashColors.lightBlue,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Vehicle Information',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: SwiftDashColors.darkBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Optional - You can complete this later in your profile',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SwiftDashColors.textGrey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Vehicle Type Dropdown
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: SwiftDashColors.backgroundGrey,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: SwiftDashColors.lightBlue.withOpacity(0.2),
                              ),
                            ),
                            child: _isLoadingVehicleTypes
                                ? Container(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Icon(Icons.directions_car_outlined, color: SwiftDashColors.lightBlue),
                                        const SizedBox(width: 12),
                                        const Text('Loading vehicle types...'),
                                        const Spacer(),
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ],
                                    ),
                                  )
                                : _vehicleTypesError != null
                                    ? Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: SwiftDashColors.dangerRed.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: SwiftDashColors.dangerRed.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.error_outline, color: SwiftDashColors.dangerRed),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Failed to load vehicle types',
                                                    style: TextStyle(
                                                      color: SwiftDashColors.dangerRed,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _vehicleTypesError!,
                                              style: TextStyle(
                                                color: SwiftDashColors.dangerRed,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ElevatedButton.icon(
                                              onPressed: _loadVehicleTypes,
                                              icon: const Icon(Icons.refresh, size: 16),
                                              label: const Text('Retry'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: SwiftDashColors.dangerRed,
                                                foregroundColor: SwiftDashColors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : DropdownButtonFormField<VehicleType>(
                                        value: _selectedVehicleType,
                                        decoration: InputDecoration(
                                          labelText: 'Vehicle Type (Optional)',
                                          prefixIcon: Icon(Icons.directions_car_outlined, color: SwiftDashColors.lightBlue),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: SwiftDashColors.backgroundGrey,
                                          contentPadding: const EdgeInsets.all(16),
                                        ),
                                        items: _vehicleTypes.isEmpty
                                            ? [
                                                DropdownMenuItem<VehicleType>(
                                                  value: null,
                                                  child: Text(
                                                    'No vehicle types available',
                                                    style: TextStyle(
                                                      color: SwiftDashColors.textGrey,
                                                      fontStyle: FontStyle.italic,
                                                    ),
                                                  ),
                                                ),
                                              ]
                                            : _vehicleTypes.map((VehicleType vehicleType) {
                                                return DropdownMenuItem<VehicleType>(
                                                  value: vehicleType,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        vehicleType.name,
                                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                                      ),
                                                      Text(
                                                        'Max: ${vehicleType.formattedMaxWeight} • ${vehicleType.formattedPricePerKm}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: SwiftDashColors.textGrey,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                        onChanged: _vehicleTypes.isEmpty
                                            ? null
                                            : (VehicleType? newValue) {
                                                setState(() {
                                                  _selectedVehicleType = newValue;
                                                });
                                              },
                                        isExpanded: true,
                                        hint: _vehicleTypes.isEmpty
                                            ? Text(
                                                'No vehicle types available',
                                                style: TextStyle(color: SwiftDashColors.textGrey),
                                              )
                                            : Text(
                                                'Select your vehicle type',
                                                style: TextStyle(color: SwiftDashColors.textGrey),
                                              ),
                                      ),
                          ),
                          
                          // Debug button (only in development)
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const DebugVehicleTypesScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.bug_report, size: 16),
                            label: const Text('Debug Vehicle Types'),
                            style: TextButton.styleFrom(
                              foregroundColor: SwiftDashColors.textGrey,
                            ),
                          ),
                        ],
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