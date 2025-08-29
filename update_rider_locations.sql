-- Update rider locations with test data
-- Run this in your Supabase SQL editor

-- First, let's see what riders we have
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

-- Update rider locations with test coordinates near the restaurant
-- Replace the rider IDs with actual IDs from your database

-- Update rider 1 (near the restaurant)
UPDATE riders 
SET 
    current_location = ST_SetSRID(ST_MakePoint(121.0901156, 14.2710116), 4326)::geography,
    updated_at = NOW()
WHERE user_id IN (
    SELECT id FROM users WHERE name = 'Rider' LIMIT 1
);

-- Update rider 2 (slightly further)
UPDATE riders 
SET 
    current_location = ST_SetSRID(ST_MakePoint(121.0851156, 14.2760116), 4326)::geography,
    updated_at = NOW()
WHERE user_id IN (
    SELECT id FROM users WHERE name = 'testrider' LIMIT 1
);

-- Update rider 3 (within 5km)
UPDATE riders 
SET 
    current_location = ST_SetSRID(ST_MakePoint(121.0951156, 14.2660116), 4326)::geography,
    updated_at = NOW()
WHERE user_id IN (
    SELECT id FROM users WHERE name = 'rider1' LIMIT 1
);

-- Verify the updates
SELECT 
    r.id,
    r.user_id,
    r.is_online,
    r.current_location,
    ST_AsText(r.current_location::geometry) as location_text,
    r.vehicle_type,
    u.name,
    u.email
FROM riders r
JOIN users u ON r.user_id = u.id
WHERE r.is_online = true;

-- Test the function with the restaurant location
SELECT * FROM find_nearby_riders(
    'SRID=4326;POINT(121.0901156 14.2710116)', -- Restaurant coordinates
    5000, -- 5km radius
    10
);
