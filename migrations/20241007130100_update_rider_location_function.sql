-- Update the existing function to also set latitude and longitude columns
create or replace function public.update_rider_location(
  p_user_id uuid,
  p_latitude double precision,
  p_longitude double precision
) returns void
language plpgsql
security definer
as $$
begin
  update public.riders
  set 
    current_location = ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
    latitude = p_latitude,
    longitude = p_longitude,
    updated_at = now()
  where user_id = p_user_id;
end;
$$;

-- Update the online status function as well for consistency
create or replace function public.update_rider_online_status(
  p_user_id uuid,
  p_is_online boolean,
  p_latitude double precision,
  p_longitude double precision
) returns void
language plpgsql
security definer
as $$
begin
  update public.riders
  set 
    is_online = p_is_online,
    current_location = case 
      when p_is_online then ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography
      else current_location
    end,
    latitude = case when p_is_online then p_latitude else latitude end,
    longitude = case when p_is_online then p_longitude else longitude end,
    updated_at = now()
  where user_id = p_user_id;
end;
$$;
