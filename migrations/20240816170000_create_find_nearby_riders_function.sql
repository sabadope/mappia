-- Drop the existing function first (if it exists)
DROP FUNCTION IF EXISTS public.find_nearby_riders(text, double precision, integer);

-- Create a function to find nearby riders
create or replace function public.find_nearby_riders(
  p_restaurant_point text,
  p_max_distance double precision default 5000, -- in meters
  p_limit integer default 10
)
returns table (
  id uuid,
  user_id uuid,
  latitude double precision,
  longitude double precision,
  is_online boolean,
  vehicle_type text,
  name text,
  email text
)
language sql
as $$
  select 
    r.id,
    r.user_id,
    st_y(r.current_location::geometry) as latitude,
    st_x(r.current_location::geometry) as longitude,
    r.is_online,
    r.vehicle_type,
    u.name,
    u.email
  from 
    public.riders r
    join public.users u on r.user_id = u.id
  where 
    r.is_online = true
    and r.current_location is not null
    and st_dwithin(
      r.current_location,
      p_restaurant_point::geography,
      p_max_distance
    )
  order by 
    r.current_location <-> p_restaurant_point::geography
  limit p_limit;
$$;

-- Grant execute permission to authenticated users
grant execute on function public.find_nearby_riders(text, double precision, integer) to authenticated;
