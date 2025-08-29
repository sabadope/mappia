-- Create or replace the function to update restaurant location
CREATE OR REPLACE FUNCTION public.update_restaurant_location(
  p_user_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_address text DEFAULT NULL
) 
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if the user exists and is a restaurant
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;
  
  -- Insert or update the restaurant location
  INSERT INTO public.restaurant_locations (
    user_id,
    latitude,
    longitude,
    address,
    updated_at
  )
  VALUES (
    p_user_id,
    p_latitude,
    p_longitude,
    p_address,
    NOW()
  )
  ON CONFLICT (user_id) 
  DO UPDATE SET
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    address = EXCLUDED.address,
    updated_at = NOW();
    
  RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Error updating restaurant location: %', SQLERRM;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.update_restaurant_location(uuid, double precision, double precision, text) TO authenticated;
