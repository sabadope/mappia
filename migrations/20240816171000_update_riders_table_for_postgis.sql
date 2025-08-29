-- First, add a new column with the correct type
ALTER TABLE public.riders 
ADD COLUMN IF NOT EXISTS current_location_geo geography(POINT, 4326);

-- If you have existing data, you can migrate it like this:
-- UPDATE public.riders 
-- SET current_location_geo = ST_GeomFromText('POINT(' || split_part(current_location, ',', 1) || ' ' || split_part(current_location, ',', 2) || ')', 4326)::geography
-- WHERE current_location IS NOT NULL;

-- Drop the old column if it exists
ALTER TABLE public.riders DROP COLUMN IF EXISTS current_location;

-- Rename the new column to the original name
ALTER TABLE public.riders RENAME COLUMN current_location_geo TO current_location;

-- Add a comment to the column
COMMENT ON COLUMN public.riders.current_location IS 'Stores the rider''s current location as a PostGIS geography point (longitude, latitude)';

-- Create an index for spatial queries
CREATE INDEX IF NOT EXISTS idx_riders_current_location 
ON public.riders USING GIST (current_location);

-- Grant necessary permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.riders TO authenticated;
