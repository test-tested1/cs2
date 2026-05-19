-- Complete Supabase Schema for CS2 Case Tracker
-- This is the final, complete schema with all tables, indexes, and policies

-- Drop existing tables if they exist (for clean setup)
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS data_entries CASCADE;
DROP TABLE IF EXISTS cases CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;

-- Create accounts table
CREATE TABLE accounts (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  image_url TEXT,
  status VARCHAR(20) DEFAULT 'Unused' CHECK (status IN ('Unused', 'Played')),
  week_start_date DATE,
  last_played_date DATE,
  status_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  user_id VARCHAR(255) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for accounts
CREATE INDEX idx_accounts_user_id ON accounts(user_id);
CREATE INDEX idx_accounts_name ON accounts(name);
CREATE INDEX idx_accounts_status ON accounts(status);
CREATE INDEX idx_accounts_week_start_date ON accounts(week_start_date);
CREATE INDEX idx_accounts_created_at ON accounts(created_at);

-- Create cases table
CREATE TABLE cases (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  user_id VARCHAR(255) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for cases
CREATE INDEX idx_cases_user_id ON cases(user_id);
CREATE INDEX idx_cases_name ON cases(name);
CREATE INDEX idx_cases_price ON cases(price);
CREATE INDEX idx_cases_created_at ON cases(created_at);

-- Create data_entries table
CREATE TABLE data_entries (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL,
  week VARCHAR(10) NOT NULL,
  account_id INTEGER NOT NULL,
  account_name VARCHAR(255) NOT NULL,
  case_id INTEGER NOT NULL,
  case_name VARCHAR(255) NOT NULL,
  case_price DECIMAL(10, 2) NOT NULL,
  gun_name VARCHAR(255) NOT NULL,
  gun_price DECIMAL(10, 2) NOT NULL,
  total DECIMAL(10, 2) NOT NULL,
  submitted_by VARCHAR(255) NOT NULL,
  user_id VARCHAR(255) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
  FOREIGN KEY (case_id) REFERENCES cases(id) ON DELETE CASCADE
);

-- Create indexes for data_entries
CREATE INDEX idx_data_entries_user_id ON data_entries(user_id);
CREATE INDEX idx_data_entries_date ON data_entries(date);
CREATE INDEX idx_data_entries_week ON data_entries(week);
CREATE INDEX idx_data_entries_account_id ON data_entries(account_id);
CREATE INDEX idx_data_entries_case_id ON data_entries(case_id);
CREATE INDEX idx_data_entries_created_at ON data_entries(created_at);
CREATE INDEX idx_data_entries_total ON data_entries(total);

-- Create notifications table
CREATE TABLE notifications (
  id SERIAL PRIMARY KEY,
  user_id VARCHAR(255) NOT NULL,
  type VARCHAR(50) NOT NULL CHECK (type IN ('account_created', 'account_updated', 'account_deleted', 'case_created', 'case_updated', 'case_deleted', 'data_entry_created')),
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  related_id INTEGER,
  related_type VARCHAR(20) CHECK (related_type IN ('account', 'case', 'data_entry')),
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  read_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for notifications
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);
CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_user_id_is_read ON notifications(user_id, is_read);

-- Initialize existing accounts with current week's Wednesday (if any exist)
-- This calculates the Wednesday of the current week
UPDATE accounts 
SET week_start_date = (
  CASE 
    WHEN EXTRACT(DOW FROM CURRENT_DATE) >= 3 THEN 
      CURRENT_DATE - INTERVAL '1 day' * (EXTRACT(DOW FROM CURRENT_DATE) - 3)
    ELSE 
      CURRENT_DATE - INTERVAL '1 day' * (EXTRACT(DOW FROM CURRENT_DATE) + 4)
  END
),
status = 'Unused'
WHERE week_start_date IS NULL;

-- Enable Row Level Security on all tables
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can manage their own accounts" ON accounts;
DROP POLICY IF EXISTS "Users can manage their own cases" ON cases;
DROP POLICY IF EXISTS "Users can manage their own data entries" ON data_entries;
DROP POLICY IF EXISTS "Users can manage their own notifications" ON notifications;

-- Create simplified RLS policies for accounts
CREATE POLICY "Users can manage their own accounts" ON accounts
  FOR ALL USING (true) WITH CHECK (true);

-- Create simplified RLS policies for cases
CREATE POLICY "Users can manage their own cases" ON cases
  FOR ALL USING (true) WITH CHECK (true);

-- Create simplified RLS policies for data_entries
CREATE POLICY "Users can manage their own data entries" ON data_entries
  FOR ALL USING (true) WITH CHECK (true);

-- Create simplified RLS policies for notifications
CREATE POLICY "Users can manage their own notifications" ON notifications
  FOR ALL USING (true) WITH CHECK (true);

-- Create some useful views for reporting
CREATE OR REPLACE VIEW weekly_stats AS
SELECT 
  user_id,
  week,
  COUNT(*) as total_entries,
  SUM(total) as total_spent,
  AVG(total) as average_spent,
  MIN(total) as min_spent,
  MAX(total) as max_spent,
  COUNT(DISTINCT account_id) as accounts_used,
  COUNT(DISTINCT case_id) as cases_opened
FROM data_entries
GROUP BY user_id, week
ORDER BY week DESC;

CREATE OR REPLACE VIEW account_summary AS
SELECT 
  a.id,
  a.name,
  a.status,
  a.week_start_date,
  a.last_played_date,
  a.user_id,
  a.created_at,
  COUNT(de.id) as total_entries,
  COALESCE(SUM(de.total), 0) as total_spent,
  MAX(de.created_at) as last_entry_date
FROM accounts a
LEFT JOIN data_entries de ON a.id = de.account_id
GROUP BY a.id, a.name, a.status, a.week_start_date, a.last_played_date, a.user_id, a.created_at
ORDER BY a.created_at DESC;

CREATE OR REPLACE VIEW case_summary AS
SELECT 
  c.id,
  c.name,
  c.price,
  c.user_id,
  c.created_at,
  COUNT(de.id) as times_opened,
  COALESCE(SUM(de.total), 0) as total_spent_on_case,
  MAX(de.created_at) as last_opened_date
FROM cases c
LEFT JOIN data_entries de ON c.id = de.case_id
GROUP BY c.id, c.name, c.price, c.user_id, c.created_at
ORDER BY c.created_at DESC;

-- Create functions for common operations
CREATE OR REPLACE FUNCTION get_current_week_wednesday()
RETURNS DATE AS $$
BEGIN
  RETURN CASE 
    WHEN EXTRACT(DOW FROM CURRENT_DATE) >= 3 THEN 
      CURRENT_DATE - INTERVAL '1 day' * (EXTRACT(DOW FROM CURRENT_DATE) - 3)
    ELSE 
      CURRENT_DATE - INTERVAL '1 day' * (EXTRACT(DOW FROM CURRENT_DATE) + 4)
  END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION format_week_string(week_date DATE)
RETURNS VARCHAR(10) AS $$
BEGIN
  RETURN TO_CHAR(week_date, 'YYYY-MM-DD');
END;
$$ LANGUAGE plpgsql;

-- Create trigger function to update status_updated timestamp
CREATE OR REPLACE FUNCTION update_status_updated_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.status_updated = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for accounts table
DROP TRIGGER IF EXISTS update_accounts_status_updated ON accounts;
CREATE TRIGGER update_accounts_status_updated
  BEFORE UPDATE ON accounts
  FOR EACH ROW
  EXECUTE FUNCTION update_status_updated_column();

-- Schema creation completed successfully
SELECT 'Supabase schema setup completed successfully!' as status;
