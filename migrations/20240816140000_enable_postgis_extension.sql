-- Enable PostGIS extension
create extension if not exists postgis with schema extensions;

-- Grant usage to authenticated users
grant usage on schema public to authenticated;
grant usage on schema extensions to authenticated;

grant select on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

alter default privileges in schema public grant all on tables to authenticated;
alter default privileges in schema public grant all on functions to authenticated;
alter default privileges in schema public grant all on sequences to authenticated;
