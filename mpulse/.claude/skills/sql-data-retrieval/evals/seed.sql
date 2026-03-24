-- Seed data for sql-data-retrieval skill testing
-- Healthcare-adjacent test data (not real)

CREATE TABLE IF NOT EXISTS members (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    plan TEXT NOT NULL,
    enrolled_date TEXT NOT NULL,
    status TEXT NOT NULL,
    state TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS claims (
    id INTEGER PRIMARY KEY,
    member_id INTEGER NOT NULL REFERENCES members(id),
    amount REAL NOT NULL,
    service_date TEXT NOT NULL,
    claim_type TEXT NOT NULL,
    provider_id INTEGER REFERENCES providers(id),
    status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS providers (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    specialty TEXT NOT NULL,
    state TEXT NOT NULL,
    npi TEXT NOT NULL
);

-- Providers
INSERT INTO providers VALUES (1, 'Dr. Sarah Chen', 'Internal Medicine', 'NY', '1234567890');
INSERT INTO providers VALUES (2, 'Dr. James Wilson', 'Cardiology', 'CA', '2345678901');
INSERT INTO providers VALUES (3, 'Dr. Maria Garcia', 'Pediatrics', 'TX', '3456789012');
INSERT INTO providers VALUES (4, 'Dr. Robert Kim', 'Orthopedics', 'FL', '4567890123');
INSERT INTO providers VALUES (5, 'Dr. Lisa Patel', 'Dermatology', 'IL', '5678901234');

-- Members
INSERT INTO members VALUES (1, 'Alice Johnson', 'Gold', '2024-01-15', 'active', 'NY');
INSERT INTO members VALUES (2, 'Bob Smith', 'Silver', '2024-02-01', 'active', 'CA');
INSERT INTO members VALUES (3, 'Carol Davis', 'Gold', '2023-06-15', 'active', 'TX');
INSERT INTO members VALUES (4, 'Dan Brown', 'Bronze', '2024-03-01', 'inactive', 'FL');
INSERT INTO members VALUES (5, 'Eve Martinez', 'Gold', '2023-01-01', 'active', 'IL');
INSERT INTO members VALUES (6, 'Frank Lee', 'Silver', '2024-04-15', 'active', 'NY');
INSERT INTO members VALUES (7, 'Grace Wang', 'Gold', '2023-09-01', 'active', 'CA');
INSERT INTO members VALUES (8, 'Henry Taylor', 'Bronze', '2024-01-01', 'suspended', 'TX');
INSERT INTO members VALUES (9, 'Iris Chen', 'Silver', '2023-11-15', 'active', 'FL');
INSERT INTO members VALUES (10, 'Jack Wilson', 'Gold', '2024-05-01', 'active', 'IL');
INSERT INTO members VALUES (11, 'Kate Adams', 'Silver', '2023-03-15', 'active', 'NY');
INSERT INTO members VALUES (12, 'Leo Garcia', 'Bronze', '2024-06-01', 'active', 'CA');
INSERT INTO members VALUES (13, 'Mia Robinson', 'Gold', '2023-08-01', 'active', 'TX');
INSERT INTO members VALUES (14, 'Noah Clark', 'Silver', '2024-02-15', 'inactive', 'FL');
INSERT INTO members VALUES (15, 'Olivia White', 'Gold', '2023-12-01', 'active', 'IL');

-- Claims
INSERT INTO claims VALUES (1, 1, 250.00, '2024-06-15', 'office_visit', 1, 'paid');
INSERT INTO claims VALUES (2, 1, 1200.00, '2024-07-01', 'procedure', 2, 'paid');
INSERT INTO claims VALUES (3, 2, 150.00, '2024-06-20', 'office_visit', 1, 'paid');
INSERT INTO claims VALUES (4, 3, 3500.00, '2024-05-10', 'surgery', 4, 'paid');
INSERT INTO claims VALUES (5, 3, 200.00, '2024-06-01', 'lab_work', 1, 'pending');
INSERT INTO claims VALUES (6, 4, 175.00, '2024-04-15', 'office_visit', 3, 'denied');
INSERT INTO claims VALUES (7, 5, 450.00, '2024-07-10', 'imaging', 2, 'paid');
INSERT INTO claims VALUES (8, 5, 125.00, '2024-07-15', 'office_visit', 5, 'paid');
INSERT INTO claims VALUES (9, 6, 800.00, '2024-06-25', 'procedure', 4, 'pending');
INSERT INTO claims VALUES (10, 7, 300.00, '2024-05-20', 'office_visit', 2, 'paid');
INSERT INTO claims VALUES (11, 7, 2100.00, '2024-06-15', 'surgery', 4, 'paid');
INSERT INTO claims VALUES (12, 8, 150.00, '2024-03-01', 'office_visit', 3, 'denied');
INSERT INTO claims VALUES (13, 9, 425.00, '2024-07-05', 'imaging', 2, 'paid');
INSERT INTO claims VALUES (14, 10, 175.00, '2024-07-20', 'office_visit', 1, 'pending');
INSERT INTO claims VALUES (15, 11, 550.00, '2024-06-10', 'procedure', 5, 'paid');
INSERT INTO claims VALUES (16, 12, 200.00, '2024-07-01', 'lab_work', 1, 'paid');
INSERT INTO claims VALUES (17, 13, 1800.00, '2024-05-25', 'surgery', 4, 'paid');
INSERT INTO claims VALUES (18, 13, 150.00, '2024-06-20', 'office_visit', 3, 'paid');
INSERT INTO claims VALUES (19, 14, 275.00, '2024-04-10', 'office_visit', 2, 'denied');
INSERT INTO claims VALUES (20, 15, 350.00, '2024-07-15', 'lab_work', 1, 'pending');
