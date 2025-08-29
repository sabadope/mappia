-- Create restaurant_locations table
CREATE TABLE IF NOT EXISTS restaurant_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  address TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_restaurant_locations_user_id ON restaurant_locations(user_id);

-- Add RLS policy if using Row Level Security
ALTER TABLE restaurant_locations ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to see their own restaurant location
CREATE POLICY "Users can view their own restaurant location"
  ON restaurant_locations
  FOR SELECT
  USING (auth.uid() = user_id);

-- Policy to allow users to update their own restaurant location
CREATE POLICY "Users can update their own restaurant location"
  ON restaurant_locations
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Policy to allow users to insert their own restaurant location
CREATE POLICY "Users can insert their own restaurant location"
  ON restaurant_locations
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy to allow users to delete their own restaurant location
CREATE POLICY "Users can delete their own restaurant location"
  ON restaurant_locations
  FOR DELETE
  USING (auth.uid() = user_id);
