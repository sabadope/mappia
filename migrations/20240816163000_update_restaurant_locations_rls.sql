-- Enable RLS on the table
ALTER TABLE public.restaurant_locations ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Restaurants can view their own location" ON public.restaurant_locations;
DROP POLICY IF EXISTS "Restaurants can insert their own location" ON public.restaurant_locations;
DROP POLICY IF EXISTS "Restaurants can update their own location" ON public.restaurant_locations;

-- Create policies for restaurant locations
CREATE POLICY "Restaurants can view their own location" 
ON public.restaurant_locations 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Restaurants can insert their own location" 
ON public.restaurant_locations 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Restaurants can update their own location" 
ON public.restaurant_locations 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Grant necessary permissions
GRANT SELECT, INSERT, UPDATE ON TABLE public.restaurant_locations TO authenticated;
