# 📋 Realtime Testing Checklist

## ✅ Pre-Test Setup
- [ ] Supabase realtime enabled on tables (deliveries, driver_profiles, user_profiles, vehicle_types)
- [ ] RLS policies configured
- [ ] Flutter app running successfully
- [ ] Driver signed up and logged in

## 🎯 Test Scenarios

### Test 1: Delivery Offers Appear Automatically
1. **Setup**: Run test_realtime_data.sql to create pending delivery
2. **Expected**: New offer appears in Delivery Offers screen WITHOUT refresh
3. **Check**: Browser console shows realtime subscription messages
4. **Status**: ⏳ Pending

### Test 2: Accept Delivery Offer
1. **Action**: Click "Accept Offer" on any delivery
2. **Expected**: 
   - Delivery status changes to 'driver_assigned'
   - Driver ID gets assigned to delivery
   - UI updates immediately
3. **Status**: ⏳ Pending

### Test 3: Update Delivery Status
1. **Action**: Use status buttons (Collected, In Transit, Delivered)
2. **Expected**: 
   - Status updates in database
   - UI reflects new status immediately
   - Customer app would see status change
3. **Status**: ⏳ Pending

### Test 4: Driver Location Updates
1. **Action**: Move around or simulate location change
2. **Expected**: 
   - Driver coordinates update in database
   - Realtime subscription sends updates
3. **Status**: ⏳ Pending

### Test 5: Multiple Drivers Testing
1. **Setup**: Open app in multiple tabs/devices with different drivers
2. **Expected**: 
   - Only one driver can accept each delivery
   - Other drivers see offer disappear when accepted
3. **Status**: ⏳ Pending

## 🐛 Common Issues & Solutions

### Issue: "No delivery offers available"
- **Cause**: No pending deliveries in database
- **Solution**: Run test_realtime_data.sql to create test data

### Issue: Offers don't appear automatically
- **Cause**: Realtime not enabled on tables
- **Solution**: Run supabase_realtime_setup.sql

### Issue: "Failed to accept delivery"
- **Cause**: RLS policies blocking driver access
- **Solution**: Check driver_profiles has correct driver_id

### Issue: Location not updating
- **Cause**: Permission denied or GPS disabled
- **Solution**: Enable location permissions in browser

## 🔍 Debug Console Messages

### Expected Console Logs:
```
✅ "Realtime subscriptions initialized"
✅ "Subscribed to deliveries table"
✅ "Delivery offer received: [delivery_id]"
✅ "Driver location updated"
```

### Error Console Logs:
```
❌ "Realtime connection failed"
❌ "Failed to subscribe to deliveries"
❌ "Permission denied"
```

## 📱 Customer App Testing (When Available)

1. **Create delivery** from customer app
2. **Check** if driver app receives offer automatically
3. **Accept delivery** from driver app
4. **Verify** customer sees driver assignment
5. **Update status** and check customer receives updates
6. **Track location** updates on customer side

## 🎯 Success Criteria

- [ ] Delivery offers appear automatically when created
- [ ] Accepting offers works without errors
- [ ] Status updates reflect in real-time
- [ ] Multiple drivers can compete for same delivery
- [ ] Location tracking works smoothly
- [ ] Console shows no realtime errors
- [ ] Database updates reflect immediately in UI