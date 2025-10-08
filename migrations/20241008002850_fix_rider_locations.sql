-- Update existing rider locations to populate latitude and longitude columns
UPDATE public.riders 
SET 
  latitude = ST_Y(current_location::geometry),
  longitude = ST_X(current_location::geometry)
WHERE 
  current_location IS NOT NULL 
  AND (latitude IS NULL OR longitude IS NULL);

-- Verify the update
SELECT id, 
       ST_Y(current_location::geometry) as lat_from_geom,
       ST_X(current_location::geometry) as lng_from_geom,
       latitude, 
       longitude,
       current_location IS NULL as is_location_null
FROM public.riders
WHERE current_location IS NOT NULL
LIMIT 10;
