# SwiftDash Driver App Assets

This folder contains all the image assets for the SwiftDash driver application.

## 📁 Folder Structure

```
assets/
├── images/
│   ├── logos/           # App logos and branding
│   ├── icons/           # UI icons and symbols  
│   └── [other images]   # Illustrations, backgrounds, etc.
```

## 🎨 Required Assets

### Logos (`assets/images/logos/`)
- **Swiftdash_Driver.png** - Main SwiftDash Driver app logo (512x512 recommended)
- **swiftdash_logo_white.png** - White version for dark backgrounds  
- **swiftdash_logo_with_text.png** - Logo with company name
- **swiftdash_logo_small.png** - Smaller version for app bars (64x64)

### Icons (`assets/images/icons/`)
- **driver_avatar.png** - Default driver profile picture
- **delivery_box.png** - Package/delivery icon
- **car.png** - Car vehicle icon
- **bike.png** - Motorcycle/bike icon  
- **truck.png** - Truck/van icon
- **online.png** - Online status indicator
- **offline.png** - Offline status indicator
- **delivery.png** - Active delivery status icon

### Illustrations (`assets/images/`)
- **no_deliveries.png** - Empty state when no deliveries available
- **location_permission.png** - Location permission request illustration
- **network_error.png** - Network connection error illustration
- **onboarding_1.png** - First onboarding screen illustration
- **onboarding_2.png** - Second onboarding screen illustration  
- **onboarding_3.png** - Third onboarding screen illustration

## 📐 Image Guidelines

### Logo Requirements:
- **Format**: PNG with transparent background
- **Size**: 512x512px (main logo), 64x64px (small logo)
- **Style**: Clean, professional, recognizable
- **Colors**: Should work on both light and dark backgrounds

### Icon Requirements:
- **Format**: PNG with transparent background
- **Size**: 64x64px or 128x128px
- **Style**: Consistent with Material Design principles
- **Colors**: Use brand colors or neutral tones

### Illustration Requirements:
- **Format**: PNG or SVG
- **Size**: 300x300px minimum
- **Style**: Friendly, modern, consistent with brand
- **Colors**: Match app color scheme

## 🎯 Usage in Code

After adding your images, you can use them in your Flutter code like this:

```dart
import '../core/app_assets.dart';

// Display main logo
Image.asset(AppAssets.logo)

// Display logo based on theme
Image.asset(AppAssets.getLogoForTheme(isDark: isDarkMode))

// Display vehicle icon
Image.asset(AppAssets.getVehicleIcon('car'))

// Display status icon  
Image.asset(AppAssets.getStatusIcon('online'))
```

## 🔄 After Adding Assets

1. **Run `flutter pub get`** to refresh asset references
2. **Hot restart** your app (not just hot reload) to load new assets
3. **Test on both light and dark themes** to ensure logos look good

## 💡 Pro Tips

- **Use vector formats (SVG)** when possible for crisp scaling
- **Optimize file sizes** to keep app bundle small
- **Test on different screen densities** to ensure clarity
- **Consider dark/light theme variations** for better UX
- **Use consistent naming conventions** for easy maintenance

## 🚀 Ready to Use

Once you add your SwiftDash logo and other assets to these folders, the app will automatically pick them up and display them in the appropriate screens!