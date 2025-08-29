-- Test script to set up riders for debugging
-- Run this in your Supabase SQL editor

-- First, let's check if we have any riders
SELECT 
    r.id,
    r.user_id,
    r.is_online,
    r.current_location,
    r.vehicle_type,
    u.name,
    u.email
FROM riders r
JOIN users u ON r.user_id = u.id;

-- Create a test rider if none exist
-- Replace 'your-test-user-id' with an actual user ID from your users table
INSERT INTO riders (
    user_id,
    vehicle_type,
    is_online,
    current_location,
    rating,
    total_deliveries,
    total_earnings,
    level
) VALUES (
    'your-test-user-id', -- Replace with actual user ID
    'Bike',
    true,
    ST_SetSRID(ST_MakePoint(121.0567, 14.5995), 4326)::geography, -- Manila coordinates
    4.5,
    0,
    0.0,
    1
) ON CONFLICT (user_id) DO UPDATE SET
    is_online = true,
    current_location = ST_SetSRID(ST_MakePoint(121.0567, 14.5995), 4326)::geography;

-- Check the PostGIS function
SELECT * FROM find_nearby_riders(
    'SRID=4326;POINT(121.0567 14.5995)', -- Manila coordinates
    5000, -- 5km radius
    10
);

-- Update an existing rider to be online (replace with actual rider ID)
-- UPDATE riders 
-- SET 
--     is_online = true,
--     current_location = ST_SetSRID(ST_MakePoint(121.0567, 14.5995), 4326)::geography,
--     updated_at = NOW()
-- WHERE id = 'your-rider-id';
