-- Function to update rider location
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
    updated_at = now()
  where user_id = p_user_id;
end;
$$;

-- Function to update rider online status and location
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
    updated_at = now()
  where user_id = p_user_id;
end;
$$;

-- Grant execute permissions to authenticated users
grant execute on function public.update_rider_location(uuid, double precision, double precision) to authenticated;
grant execute on function public.update_rider_online_status(uuid, boolean, double precision, double precision) to authenticated;
