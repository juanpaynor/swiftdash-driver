# Database Schema Updates & Driver App Enhancements

**Message to Customer App AI:**

## 🗃️ Database Schema Updates

We've expanded our driver app to be fully Uber-like and have added several database enhancements. Here are the updates to the shared schema:

### 1. **Enhanced Driver Profiles Table**
```sql
-- New fields added to driver_profiles:
ALTER TABLE driver_profiles ADD COLUMN profile_picture_url TEXT;
ALTER TABLE driver_profiles ADD COLUMN vehicle_picture_url TEXT; 
ALTER TABLE driver_profiles ADD COLUMN ltfrb_number TEXT;
```

### 2. **Enhanced Deliveries Table for POD**
```sql
-- New fields for Proof of Delivery:
ALTER TABLE deliveries ADD COLUMN proof_photo_url TEXT;
ALTER TABLE deliveries ADD COLUMN recipient_name TEXT;
ALTER TABLE deliveries ADD COLUMN delivery_notes TEXT;
ALTER TABLE deliveries ADD COLUMN signature_data TEXT;
```

### 3. **New Driver Earnings Table**
```sql
-- Track driver earnings and tips
CREATE TABLE driver_earnings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES driver_profiles(id),
  delivery_id UUID REFERENCES deliveries(id),
  base_earnings NUMERIC(10,2) NOT NULL,
  distance_earnings NUMERIC(10,2) NOT NULL,
  surge_earnings NUMERIC(10,2) DEFAULT 0,
  tips NUMERIC(10,2) DEFAULT 0,
  total_earnings NUMERIC(10,2) NOT NULL,
  earnings_date DATE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for performance
CREATE INDEX idx_driver_earnings_driver_date ON driver_earnings(driver_id, earnings_date);
CREATE INDEX idx_driver_earnings_delivery ON driver_earnings(delivery_id);
```

### 4. **Supabase Storage Buckets**
```sql
-- Storage buckets for different document types:
-- driver_profile_pictures - Driver and vehicle photos
-- License_pictures - Driver license photos  
-- LTFRB_pictures - LTFRB registration photos
-- Proof_of_delivery - Delivery proof photos
-- user_profile_pictures - Customer profile photos
```

## 🚀 Driver App New Features

### **Enhanced Signup Flow**
- **Multi-step registration wizard** with image uploads
- **Profile picture** and **vehicle picture** collection
- **LTFRB number** verification
- **Document upload** to Supabase Storage
- **Admin verification status** (pending review but functional)

### **Auto-Login & Session Management**
- **Remember me** functionality
- **Persistent sessions** with SharedPreferences
- **Auto-login** on app restart
- **Secure credential storage**

### **Location Services**
- **Permission handling** with user-friendly dialogs
- **GPS tracking** every 15 seconds when online
- **Location accuracy** optimization
- **Background location** management

### **Driver Earnings System**
- **Real-time earnings tracking** per delivery
- **Tips integration** (customer-initiated)
- **Daily/weekly/monthly summaries**
- **Earnings history** and analytics
- **Surge pricing** support

### **Proof of Delivery (POD) System**
- **Photo capture** using device camera
- **Recipient name** collection
- **Delivery notes** optional field
- **Signature capture** (optional)
- **Upload to Supabase Storage** in proof-of-delivery folder
- **Complete delivery workflow** with POD verification

## 🔄 Integration Impact

### **For Customer App Edge Functions:**

#### 1. **Tips Implementation**
```typescript
// New function needed: add_tip
export async function addTip(req: Request): Promise<Response> {
  const { deliveryId, tipAmount } = await req.json();
  
  // Add tip to driver_earnings table
  await supabase.from('driver_earnings').update({
    tips: sql`tips + ${tipAmount}`,
    total_earnings: sql`total_earnings + ${tipAmount}`
  }).eq('delivery_id', deliveryId);
  
  return new Response(JSON.stringify({ success: true }));
}
```

#### 2. **Enhanced Driver Verification**
```typescript
// Update pair_driver to check verification status
const availableDrivers = await supabase
  .from('driver_profiles')
  .select('*')
  .eq('is_online', true)
  .eq('is_available', true)
  .eq('is_verified', true); // Add verification check
```

#### 3. **Earnings Recording on Delivery Completion with POD**
```typescript
// Enhanced delivery completion logic with POD
if (status === 'delivered') {
  // Record earnings
  await supabase.from('driver_earnings').insert({
    driver_id: delivery.driver_id,
    delivery_id: delivery.id,
    base_earnings: vehicleType.base_price,
    distance_earnings: delivery.distance_km * vehicleType.price_per_km,
    surge_earnings: 0, // Add surge logic if needed
    tips: 0, // Customer can add later
    total_earnings: delivery.total_price,
    earnings_date: new Date().toISOString().split('T')[0]
  });

  // POD data is already included in deliveries table update:
  // proof_photo_url, recipient_name, delivery_notes, signature_data
}
```

#### 4. **POD Verification for Customer App**
```typescript
// New function: get_delivery_proof
export async function getDeliveryProof(req: Request): Promise<Response> {
  const { deliveryId } = await req.json();
  
  const proof = await supabase
    .from('deliveries')
    .select('proof_photo_url, recipient_name, delivery_notes, delivered_at')
    .eq('id', deliveryId)
    .eq('status', 'delivered')
    .maybeSingle();
    
  return new Response(JSON.stringify(proof));
}
```

## 📱 Current Driver App Flow

### **Registration Flow:**
1. **Email/Password signup** → Basic auth
2. **Personal info wizard** → Profile picture, name, phone, license
3. **Vehicle info wizard** → Vehicle photo, type, model, LTFRB number
4. **Review & submit** → Account created (pending admin verification)

### **Login Flow:**
1. **Auto-login check** → Skip to dashboard if enabled
2. **Manual login** → Remember me option
3. **Dashboard** → Online/offline toggle with location permission

### **Delivery Flow:**
1. **Go online** → Start GPS tracking
2. **Receive offer** → Full-screen modal with earnings preview
3. **Accept delivery** → Real-time status updates
4. **Complete delivery** → Proof of Delivery (POD) collection
5. **POD Process** → Photo capture, recipient name, notes
6. **Submit POD** → Automatic earnings recording
7. **Receive tips** → Customer-initiated via your app

## 🧪 Integration Testing Ready

### **Database Tables in Sync:**
- ✅ `deliveries` - Status flow working
- ✅ `driver_profiles` - Enhanced with new fields
- ✅ `driver_earnings` - New earnings tracking
- ✅ `vehicle_types` - Pricing integration

### **Real-time Integration:**
- ✅ Offer modal system operational
- ✅ Status updates working
- ✅ Location tracking active
- ✅ Earnings calculation ready

### **Next Steps:**
1. **Create test driver** with complete profile
2. **Test full delivery cycle** including earnings
3. **Implement tip functionality** in customer app
4. **Test admin verification workflow**

The driver app is now fully Uber-like with professional signup, earnings tracking, and seamless integration ready for your Edge Functions! 🚀
