CREATE DATABASE IF NOT EXISTS vehicle_rental CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE vehicle_rental;

-- clean reset without DROP DATABASE (some phpMyAdmin setups block it)
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS activity_logs;
DROP TABLE IF EXISTS damage_reports;
DROP TABLE IF EXISTS rental_status_history;
DROP TABLE IF EXISTS late_fees;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS rentals;
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS maintenance_records;
DROP TABLE IF EXISTS insurance;
DROP TABLE IF EXISTS rate_plans;
DROP TABLE IF EXISTS vehicles;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS vehicle_categories;
DROP TABLE IF EXISTS branches;
DROP TABLE IF EXISTS roles;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1. roles
-- ---------------------------------------------------------------------
CREATE TABLE roles (
 role_id INT AUTO_INCREMENT PRIMARY KEY,
 role_name VARCHAR(50) NOT NULL UNIQUE,
 description VARCHAR(255)
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
-- 2. branches
-- ---------------------------------------------------------------------
CREATE TABLE branches (
 branch_id INT AUTO_INCREMENT PRIMARY KEY,
 branch_name VARCHAR(100) NOT NULL UNIQUE,
 address VARCHAR(255) NOT NULL,
 city VARCHAR(100) NOT NULL,
 phone VARCHAR(20) NOT NULL,
 opening_hours VARCHAR(100)
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
-- 3. vehicle_categories
-- ---------------------------------------------------------------------
CREATE TABLE vehicle_categories (
 category_id INT AUTO_INCREMENT PRIMARY KEY,
 category_name VARCHAR(50) NOT NULL UNIQUE,
 description VARCHAR(255),
 seating_capacity TINYINT UNSIGNED NOT NULL,
 CONSTRAINT chk_category_seats CHECK (seating_capacity BETWEEN 1 AND 60)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. customers
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    middle_name VARCHAR(50),
    last_name VARCHAR(50) NOT NULL,
    birth_date DATE NOT NULL,
    gender ENUM('Male','Female','Other') NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL,
    street VARCHAR(150) NOT NULL,
    barangay VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    license_number VARCHAR(30) NOT NULL UNIQUE,
    license_expiry_date DATE NOT NULL,
    emergency_contact_name VARCHAR(100) NOT NULL,
    emergency_contact_phone VARCHAR(20) NOT NULL,
    date_registered DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('Active','Blacklisted') NOT NULL DEFAULT 'Active',

    -- a driver's license can only be held from age 18 onward
    CONSTRAINT chk_customer_dates CHECK (license_expiry_date > DATE_ADD(birth_date, INTERVAL 18 YEAR)),
    INDEX idx_cust_name (last_name, first_name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. employees
-- ---------------------------------------------------------------------
CREATE TABLE employees (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    role_id INT NOT NULL,
    branch_id INT NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL, -- store a HASH, never the real password
    hire_date DATE NOT NULL,
    status ENUM('Active','Inactive') NOT NULL DEFAULT 'Active',
    CONSTRAINT fk_emp_role FOREIGN KEY (role_id) REFERENCES roles(role_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_emp_branch FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. vehicles
-- ---------------------------------------------------------------------
CREATE TABLE vehicles (
    vehicle_id INT AUTO_INCREMENT PRIMARY KEY,
    category_id INT NOT NULL,
    branch_id INT NOT NULL,
    plate_number VARCHAR(15) NOT NULL UNIQUE,
    brand VARCHAR(50) NOT NULL,
    model VARCHAR(50) NOT NULL,
    year SMALLINT NOT NULL,
    color VARCHAR(30) NOT NULL,
    transmission ENUM('Manual','Automatic') NOT NULL,
    fuel_type ENUM('Gasoline','Diesel','Electric','Hybrid') NOT NULL,
    seats TINYINT UNSIGNED NOT NULL,
    mileage INT UNSIGNED NOT NULL DEFAULT 0,
    status ENUM('Available','Reserved','Rented','Maintenance','Unavailable')
    NOT NULL DEFAULT 'Available',

    CONSTRAINT chk_vehicle_year CHECK (year BETWEEN 1990 AND 2100),
    CONSTRAINT chk_vehicle_seats CHECK (seats > 0),
    CONSTRAINT fk_veh_category FOREIGN KEY (category_id) REFERENCES vehicle_categories(category_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_veh_branch FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_veh_status (status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  7. rate_plans   (Daily 1-6 days, Weekly 7-29, Monthly 30+, seasonal)
-- ---------------------------------------------------------------------
CREATE TABLE rate_plans (
  rate_plan_id INT AUTO_INCREMENT PRIMARY KEY,
  category_id  INT           NOT NULL,
  plan_name    VARCHAR(50)   NOT NULL,
  rate_per_day DECIMAL(10,2) NOT NULL,
  min_days     INT           NOT NULL DEFAULT 1,
  max_days     INT           NULL,
  season_start DATE          NULL,
  season_end   DATE          NULL,
  CONSTRAINT chk_rate_amount  CHECK (rate_per_day > 0),
  CONSTRAINT chk_rate_days    CHECK (min_days >= 1 AND (max_days IS NULL OR max_days >= min_days)),
  CONSTRAINT chk_rate_season  CHECK (season_end IS NULL OR season_start IS NULL OR season_end >= season_start),
  CONSTRAINT fk_rate_category FOREIGN KEY (category_id) REFERENCES vehicle_categories(category_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  8. insurance
-- ---------------------------------------------------------------------
CREATE TABLE insurance (
  insurance_id    INT AUTO_INCREMENT PRIMARY KEY,
  vehicle_id      INT           NOT NULL,
  provider        VARCHAR(100)  NOT NULL,
  policy_number   VARCHAR(50)   NOT NULL UNIQUE,
  coverage_type   ENUM('Comprehensive','Third-Party','Collision') NOT NULL,
  coverage_amount DECIMAL(12,2) NOT NULL,
  start_date      DATE          NOT NULL,
  expiry_date     DATE          NOT NULL,
  CONSTRAINT chk_ins_amount CHECK (coverage_amount > 0),
  CONSTRAINT chk_ins_dates  CHECK (expiry_date > start_date),
  CONSTRAINT fk_ins_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  INDEX idx_ins_vehicle_expiry (vehicle_id, expiry_date)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  9. maintenance_records
-- ---------------------------------------------------------------------
CREATE TABLE maintenance_records (
  maintenance_id       INT AUTO_INCREMENT PRIMARY KEY,
  vehicle_id           INT           NOT NULL,
  service_type         VARCHAR(100)  NOT NULL,
  description          TEXT,
  service_date         DATE          NOT NULL,
  next_service_date    DATE          NULL,
  next_service_mileage INT UNSIGNED  NULL,
  cost                 DECIMAL(10,2) NOT NULL DEFAULT 0,
  status               ENUM('Scheduled','In Progress','Completed') NOT NULL DEFAULT 'Scheduled',
  CONSTRAINT chk_maint_cost  CHECK (cost >= 0),
  CONSTRAINT chk_maint_dates CHECK (next_service_date IS NULL OR next_service_date >= service_date),
  CONSTRAINT fk_maint_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  INDEX idx_maint_vehicle_date (vehicle_id, service_date, status)
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
--  10. reservations -- 
-- ---------------------------------------------------------------------
CREATE TABLE reservations ( 
  reservation_id INT AUTO_INCREMENT PRIMARY KEY, 
  customer_id    INT      NOT NULL, 
  vehicle_id     INT      NOT NULL, 
  employee_id    INT      NOT NULL,   -- staff who encoded the booking 
  start_date     DATE     NOT NULL, 
  end_date       DATE     NOT NULL, 
  status         ENUM('Pending','Confirmed','Cancelled','Completed','No-Show') 
                 NOT NULL DEFAULT 'Pending', 
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, 
  CONSTRAINT chk_resv_dates CHECK (end_date >= start_date), 
  CONSTRAINT fk_resv_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id) 
    ON DELETE RESTRICT ON UPDATE CASCADE, 
  CONSTRAINT fk_resv_vehicle  FOREIGN KEY (vehicle_id)  REFERENCES vehicles(vehicle_id) 
    ON DELETE RESTRICT ON UPDATE CASCADE, 
  CONSTRAINT fk_resv_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id) 
    ON DELETE RESTRICT ON UPDATE CASCADE, 
  -- speeds up the "is this vehicle free for these dates?" check 
  INDEX idx_resv_vehicle_dates (vehicle_id, start_date, end_date) 
) ENGINE=InnoDB; 

 -- -------------------------------------------------------------------
  --  11. rentals   (reservation_id NULL = walk-in) -- 
-- ---------------------------------------------------------------------
CREATE TABLE rentals ( 
  rental_id        INT AUTO_INCREMENT PRIMARY KEY, 
  reservation_id   INT          NULL UNIQUE, 
  customer_id      INT          NOT NULL, 
  vehicle_id       INT          NOT NULL, 
  employee_id      INT          NOT NULL, 
  pickup_branch_id INT          NOT NULL, 
  return_branch_id INT          NULL, 
  rental_date      DATETIME     NOT NULL, 
  due_date         DATETIME     NOT NULL, 
  return_date      DATETIME     NULL,          -- NULL = not yet returned 
  start_mileage    INT UNSIGNED NOT NULL, 
  end_mileage      INT UNSIGNED NULL, 
  total_amount     DECIMAL(12,2) NOT NULL DEFAULT 0, 
  status           ENUM('Active','Returned','Overdue','Cancelled') NOT NULL DEFAULT 'Active', 
  CONSTRAINT chk_rental_due     CHECK (due_date > rental_date), 
  CONSTRAINT chk_rental_return  CHECK (return_date IS NULL OR return_date >= rental_date), 
  CONSTRAINT chk_rental_mileage CHECK (end_mileage IS NULL OR end_mileage >= start_mileage), 
CONSTRAINT chk_rental_total   CHECK (total_amount >= 0), 
CONSTRAINT fk_rent_reservation FOREIGN KEY (reservation_id)   REFERENCES reservations(reservation_id) 
ON DELETE RESTRICT ON UPDATE CASCADE, 
CONSTRAINT fk_rent_customer    FOREIGN KEY (customer_id)      REFERENCES customers(customer_id) 
ON DELETE RESTRICT ON UPDATE CASCADE, 
CONSTRAINT fk_rent_vehicle     FOREIGN KEY (vehicle_id)       REFERENCES vehicles(vehicle_id) 
ON DELETE RESTRICT ON UPDATE CASCADE, 
CONSTRAINT fk_rent_employee    FOREIGN KEY (employee_id)      REFERENCES employees(employee_id) 
ON DELETE RESTRICT ON UPDATE CASCADE, 
CONSTRAINT fk_rent_pickup      FOREIGN KEY (pickup_branch_id) REFERENCES branches(branch_id) 
ON DELETE RESTRICT ON UPDATE CASCADE, 
CONSTRAINT fk_rent_return      FOREIGN KEY (return_branch_id) REFERENCES branches(branch_id) 
ON DELETE RESTRICT ON UPDATE CASCADE, 
INDEX idx_rent_vehicle_status (vehicle_id, status, rental_date, due_date), 
INDEX idx_rent_status (status) 
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  12. payments   (RECONSTRUCTED - matches the columns used in the INSERTs)
-- ---------------------------------------------------------------------
CREATE TABLE payments (
  payment_id       INT AUTO_INCREMENT PRIMARY KEY,
  rental_id        INT           NOT NULL,
  amount           DECIMAL(12,2) NOT NULL,
  payment_date     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  payment_method   ENUM('Cash','GCash','Credit Card','Debit Card','Bank Transfer') NOT NULL,
  payment_type     ENUM('Rental Fee','Deposit','Late Fee','Damage Fee','Refund') NOT NULL,
  reference_number VARCHAR(50)   NULL,
  status           ENUM('Pending','Paid','Refunded','Failed') NOT NULL DEFAULT 'Paid',
  CONSTRAINT chk_pay_amount CHECK (amount > 0),
  CONSTRAINT fk_pay_rental FOREIGN KEY (rental_id) REFERENCES rentals(rental_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  INDEX idx_pay_rental (rental_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  13. late_fees   (RECONSTRUCTED - matches the columns used in the INSERTs)
-- ---------------------------------------------------------------------
CREATE TABLE late_fees (
  late_fee_id INT AUTO_INCREMENT PRIMARY KEY,
  rental_id   INT           NOT NULL,
  days_late   INT           NOT NULL,
  fee_amount  DECIMAL(10,2) NOT NULL,
  computed_on DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status      ENUM('Unpaid','Paid','Waived') NOT NULL DEFAULT 'Unpaid',
  CONSTRAINT chk_late_days CHECK (days_late > 0),
  CONSTRAINT chk_late_fee  CHECK (fee_amount >= 0),
  CONSTRAINT fk_late_rental FOREIGN KEY (rental_id) REFERENCES rentals(rental_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
--  14. rental_status_history
-- ---------------------------------------------------------------------
CREATE TABLE rental_status_history (
  history_id INT AUTO_INCREMENT PRIMARY KEY,
  rental_id  INT          NOT NULL,
  changed_by INT          NOT NULL,   -- employee who made the change
  old_status VARCHAR(30)  NULL,       -- NULL for the first status
  new_status VARCHAR(30)  NOT NULL,
  changed_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  remarks    VARCHAR(255),
  CONSTRAINT fk_hist_rental   FOREIGN KEY (rental_id)  REFERENCES rentals(rental_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_hist_employee FOREIGN KEY (changed_by) REFERENCES employees(employee_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
--  15. damage_reports
-- ---------------------------------------------------------------------
CREATE TABLE damage_reports (
  damage_id     INT AUTO_INCREMENT PRIMARY KEY,
  rental_id     INT           NOT NULL,
  vehicle_id    INT           NOT NULL,
  reported_by   INT           NOT NULL,   -- employee who inspected the vehicle
  description   TEXT          NOT NULL,
  severity      ENUM('Minor','Moderate','Major') NOT NULL,
  repair_cost   DECIMAL(10,2) NOT NULL DEFAULT 0,
  reported_date DATE          NOT NULL,
  status        ENUM('Reported','Under Repair','Resolved') NOT NULL DEFAULT 'Reported',
  CONSTRAINT chk_damage_cost CHECK (repair_cost >= 0),
  CONSTRAINT fk_dmg_rental   FOREIGN KEY (rental_id)   REFERENCES rentals(rental_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_dmg_vehicle  FOREIGN KEY (vehicle_id)  REFERENCES vehicles(vehicle_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_dmg_employee FOREIGN KEY (reported_by) REFERENCES employees(employee_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;



-- ---------------------------------------------------------------------
--  16. activity_logs
-- ---------------------------------------------------------------------
CREATE TABLE activity_logs (
  log_id      INT AUTO_INCREMENT PRIMARY KEY,
  employee_id INT          NOT NULL,
  action      VARCHAR(50)  NOT NULL,   -- e.g. CREATE, UPDATE, DELETE, LOGIN
  table_name  VARCHAR(50)  NOT NULL,
  record_id   INT          NULL,
  description VARCHAR(255),
  logged_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_log_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  INDEX idx_log_logged_at (logged_at)
) ENGINE=InnoDB;

-- =====================================================================
--  SAMPLE DATA
-- =====================================================================

INSERT INTO roles (role_name, description) VALUES
('Admin',   'Full access to all modules and reports'),
('Manager', 'Manages branch operations, rates, and reports'),
('Staff',   'Handles reservations, rentals, and payments');

INSERT INTO branches (branch_name, address, city, phone, opening_hours) VALUES
('Manila Main Branch',    '123 Taft Avenue',          'Manila',        '02-8123-4567', '7:00 AM - 8:00 PM'),
('Quezon City Branch',    '45 Timog Avenue',          'Quezon City',   '02-8234-5678', '8:00 AM - 7:00 PM'),
('Angeles City Branch',   '88 MacArthur Highway',     'Angeles City',  '045-625-1234', '8:00 AM - 6:00 PM'),
('Subic Pickup Point',    'Rizal Highway, Subic Bay', 'Olongapo City', '047-252-9876', '9:00 AM - 5:00 PM');

INSERT INTO vehicle_categories (category_name, description, seating_capacity) VALUES
('Sedan',      'Compact and mid-size cars for city driving', 5),
('SUV',        'Sport utility vehicles for families and trips', 7),
('Van',        'Large vans for groups and cargo',              12),
('Pickup',     'Pickup trucks for rough roads and hauling',     5),
('Motorcycle', 'Scooters and motorcycles',                      2);

INSERT INTO customers
(first_name, middle_name, last_name, birth_date, gender, email, phone, street, barangay, city, province, postal_code,
 license_number, license_expiry_date, emergency_contact_name, emergency_contact_phone, status) VALUES
('Juan',   'Dela',    'Cruz',     '1990-05-14', 'Male',   'juan.cruz@email.com',    '0917-111-2233', '12 Mabini St.',      'Barangay 101',   'Manila',       'Metro Manila', '1000', 'N01-23-456789', '2028-05-14', 'Maria Cruz',      '0917-111-9999', 'Active'),
('Maria',  'Lopez',   'Santos',   '1988-09-21', 'Female', 'maria.santos@email.com', '0918-222-3344', '34 Rizal Ave.',      'Barangay Poblacion','Quezon City',  'Metro Manila', '1100', 'N02-34-567890', '2027-09-21', 'Pedro Santos',    '0918-222-8888', 'Active'),
('Pedro',  NULL,      'Ramirez',  '1995-01-30', 'Male',   'pedro.ramirez@email.com','0919-333-4455', '56 Sampaguita St.',  'Barangay San Jose','Angeles City', 'Pampanga',     '2009', 'N03-45-678901', '2029-01-30', 'Elena Ramirez',   '0919-333-7777', 'Active'),
('Ana',    'Reyes',   'Villanueva','1992-11-08','Female', 'ana.villanueva@email.com','0920-444-5566','78 Mabuhay Rd.',     'Barangay Santa Maria','Angeles City','Pampanga',   '2009', 'N04-56-789012', '2028-11-08', 'Luis Villanueva', '0920-444-6666', 'Active'),
('Carlos', 'Mendoza', 'Bautista', '1985-03-17', 'Male',   'carlos.bautista@email.com','0921-555-6677','90 Bonifacio Dr.',  'Barangay 55',    'Manila',       'Metro Manila', '1005', 'N05-67-890123', '2026-12-31', 'Rosa Bautista',   '0921-555-5555', 'Active'),
('Liza',   NULL,      'Garcia',   '1998-07-25', 'Female', 'liza.garcia@email.com',  '0922-666-7788', '23 Luna St.',        'Barangay Commonwealth','Quezon City','Metro Manila','1121','N06-78-901234', '2030-07-25', 'Ramon Garcia',    '0922-666-4444', 'Active'),
('Mark',   'Anthony', 'Torres',   '1993-12-02', 'Male',   'mark.torres@email.com',  '0923-777-8899', '67 Del Pilar St.',   'Barangay Dau',   'Mabalacat',    'Pampanga',     '2010', 'N07-89-012345', '2027-12-02', 'Joy Torres',      '0923-777-3333', 'Active'),
('Grace',  'Ann',     'Flores',   '1996-04-19', 'Female', 'grace.flores@email.com', '0924-888-9900', '5 Katipunan Ave.',   'Barangay Loyola','Quezon City',  'Metro Manila', '1108', 'N08-90-123456', '2029-04-19', 'Ben Flores',      '0924-888-2222', 'Active');

-- password_hash values are FAKE placeholders
INSERT INTO employees (role_id, branch_id, first_name, last_name, email, phone, username, password_hash, hire_date, status) VALUES
(1, 1, 'Ramon',  'Dela Cruz', 'ramon.admin@rental.com',  '0917-000-0001', 'ramon.admin',  '$2a$10$LQeW55EiA.PJnSaxwl/e0.dczuQHa4/2nS6IHn9oTWL4Md9SfGoQy', '2022-01-10', 'Active'),
(2, 1, 'Maria',  'Santos',    'maria.mgr@rental.com',    '0917-000-0002', 'maria.mgr',    '$2a$10$LQeW55EiA.PJnSaxwl/e0.dczuQHa4/2nS6IHn9oTWL4Md9SfGoQy', '2022-03-15', 'Active'),
(3, 1, 'Jose',   'Reyes',     'jose.staff@rental.com',   '0917-000-0003', 'jose.staff',   '$2a$10$LQeW55EiA.PJnSaxwl/e0.dczuQHa4/2nS6IHn9oTWL4Md9SfGoQy', '2023-06-01', 'Active'),
(2, 2, 'Ana',    'Garcia',    'ana.mgr@rental.com',      '0917-000-0004', 'ana.mgr',      '$2a$10$LQeW55EiA.PJnSaxwl/e0.dczuQHa4/2nS6IHn9oTWL4Md9SfGoQy', '2022-08-20', 'Active'),
(3, 2, 'Luis',   'Mendoza',   'luis.staff@rental.com',   '0917-000-0005', 'luis.staff',   '$2a$10$LQeW55EiA.PJnSaxwl/e0.dczuQHa4/2nS6IHn9oTWL4Md9SfGoQy', '2024-02-12', 'Active'),
(3, 3, 'Carla',  'Bautista',  'carla.staff@rental.com',  '0917-000-0006', 'carla.staff',  '$2a$10$LQeW55EiA.PJnSaxwl/e0.dczuQHa4/2nS6IHn9oTWL4Md9SfGoQy', '2024-05-05', 'Active');

INSERT INTO vehicles (category_id, branch_id, plate_number, brand, model, year, color, transmission, fuel_type, seats, mileage, status) VALUES
(1, 1, 'ABC 1234', 'Toyota',     'Vios',        2023, 'White',  'Automatic', 'Gasoline', 5,  30400, 'Available'),
(1, 1, 'DEF 5678', 'Honda',      'City',        2022, 'Silver', 'Automatic', 'Gasoline', 5,  30000, 'Rented'),
(2, 1, 'GHI 9012', 'Toyota',     'Fortuner',    2023, 'Black',  'Automatic', 'Diesel',   7,  44600, 'Available'),
(2, 2, 'JKL 3456', 'Mitsubishi', 'Montero Sport',2022,'Gray',   'Automatic', 'Diesel',   7,  38000, 'Available'),
(3, 2, 'MNO 7890', 'Toyota',     'Hiace',       2021, 'White',  'Manual',    'Diesel',   12, 20250, 'Maintenance'),
(3, 3, 'PQR 1357', 'Nissan',     'Urvan',       2022, 'White',  'Manual',    'Diesel',   12, 27000, 'Available'),
(4, 3, 'STU 2468', 'Ford',       'Ranger',      2023, 'Orange', 'Manual',    'Diesel',   5,  15900, 'Available'),
(4, 2, 'VWX 3579', 'Toyota',     'Hilux',       2022, 'Red',    'Manual',    'Diesel',   5,  22300, 'Available'),
(5, 1, 'YZA 4680', 'Honda',      'Click 160',   2024, 'Blue',   'Automatic', 'Gasoline', 2,  5100,  'Available'),
(5, 3, 'BCD 5791', 'Yamaha',     'NMAX',        2023, 'Black',  'Automatic', 'Gasoline', 2,  8000,  'Rented'),
(2, 3, 'EFG 6802', 'Toyota',     'Rush',        2023, 'Gray',   'Automatic', 'Gasoline', 7,  12500, 'Available'),
(1, 2, 'HIJ 7913', 'Mitsubishi', 'Mirage G4',   2024, 'Red',    'Automatic', 'Gasoline', 5,  3000,  'Available'),
(1, 1, 'NAA 1001', 'Toyota',     'Wigo',         2024, 'Yellow', 'Automatic', 'Gasoline', 5,  4200,  'Available'),
(1, 2, 'NAB 1002', 'Honda',      'Civic',        2023, 'Blue',   'Automatic', 'Gasoline', 5,  11800, 'Available'),
(1, 3, 'NAC 1003', 'Hyundai',    'Accent',       2022, 'Silver', 'Manual',    'Diesel',   5,  26500, 'Available'),
(2, 1, 'NAD 1004', 'Toyota',     'Innova',       2024, 'White',  'Automatic', 'Diesel',   7,  6100,  'Available'),
(2, 2, 'NAE 1005', 'Ford',       'Everest',      2023, 'Black',  'Automatic', 'Diesel',   7,  18900, 'Available'),
(2, 4, 'NAF 1006', 'Mitsubishi', 'Xpander',      2024, 'Gray',   'Automatic', 'Gasoline', 7,  3500,  'Available'),
(3, 1, 'NAG 1007', 'Toyota',     'Hiace Grandia',2023, 'Silver', 'Manual',    'Diesel',   12, 14200, 'Available'),
(4, 3, 'NAH 1008', 'Isuzu',      'D-Max',        2023, 'White',  'Manual',    'Diesel',   5,  21000, 'Available'),
(4, 4, 'NAI 1009', 'Nissan',     'Navara',       2022, 'Gray',   'Automatic', 'Diesel',   5,  29800, 'Available'),
(5, 2, 'NAJ 1010', 'Honda',      'ADV 160',      2024, 'Red',    'Automatic', 'Gasoline', 2,  2300,  'Available');

INSERT INTO rate_plans (category_id, plan_name, rate_per_day, min_days, max_days, season_start, season_end) VALUES
(1, 'Daily',        1500.00, 1,  6,    NULL,         NULL),
(1, 'Weekly',       1300.00, 7,  29,   NULL,         NULL),
(2, 'Daily',        3000.00, 1,  6,    NULL,         NULL),
(2, 'Weekly',       2700.00, 7,  29,   NULL,         NULL),
(3, 'Daily',        3500.00, 1,  6,    NULL,         NULL),
(3, 'Weekly',       3200.00, 7,  29,   NULL,         NULL),
(4, 'Daily',        3200.00, 1,  6,    NULL,         NULL),
(5, 'Daily',         600.00, 1,  6,    NULL,         NULL),
(4, 'Weekly',       2900.00, 7,  29,   NULL,         NULL),
(5, 'Weekly',        550.00, 7,  29,   NULL,         NULL),
(1, 'Monthly',      1200.00, 30, NULL, NULL,         NULL),
(2, 'Monthly',      2400.00, 30, NULL, NULL,         NULL),
(3, 'Monthly',      2800.00, 30, NULL, NULL,         NULL),
(4, 'Monthly',      2600.00, 30, NULL, NULL,         NULL),
(5, 'Monthly',       450.00, 30, NULL, NULL,         NULL),
(1, 'Holiday Peak', 2000.00, 1,  NULL, '2026-12-15', '2027-01-05');

-- Vehicle 10's policy is already expired; vehicle 12 has no policy yet
INSERT INTO insurance (vehicle_id, provider, policy_number, coverage_type, coverage_amount, start_date, expiry_date) VALUES
(1,  'Malayan Insurance', 'POL-2026-0001', 'Comprehensive', 800000.00,  '2026-01-01', '2026-12-31'),
(2,  'Malayan Insurance', 'POL-2026-0002', 'Comprehensive', 750000.00,  '2026-01-01', '2026-12-31'),
(3,  'Pioneer Insurance', 'POL-2026-0003', 'Comprehensive', 2000000.00, '2026-02-01', '2027-01-31'),
(4,  'Pioneer Insurance', 'POL-2026-0004', 'Comprehensive', 1800000.00, '2026-02-01', '2027-01-31'),
(5,  'Standard Insurance','POL-2026-0005', 'Third-Party',   1500000.00, '2026-03-01', '2027-02-28'),
(6,  'Standard Insurance','POL-2026-0006', 'Third-Party',   1500000.00, '2026-03-01', '2027-02-28'),
(7,  'Pioneer Insurance', 'POL-2026-0007', 'Comprehensive', 1700000.00, '2026-04-01', '2027-03-31'),
(8,  'Pioneer Insurance', 'POL-2026-0008', 'Comprehensive', 1600000.00, '2026-04-01', '2027-03-31'),
(9,  'Malayan Insurance', 'POL-2026-0009', 'Collision',      120000.00, '2026-05-01', '2027-04-30'),
(10, 'Malayan Insurance', 'POL-2025-0010', 'Collision',      110000.00, '2025-10-01', '2026-09-30'),
(11, 'Standard Insurance','POL-2026-0011', 'Comprehensive', 1200000.00, '2026-06-01', '2027-05-31'),
(13, 'Malayan Insurance', 'POL-2026-0113', 'Comprehensive',  900000.00, '2026-10-01', '2027-09-30'),
(14, 'Malayan Insurance', 'POL-2026-0114', 'Comprehensive',  900000.00, '2026-10-01', '2027-09-30'),
(15, 'Malayan Insurance', 'POL-2026-0115', 'Comprehensive',  900000.00, '2026-10-01', '2027-09-30'),
(16, 'Malayan Insurance', 'POL-2026-0116', 'Comprehensive', 1800000.00, '2026-10-01', '2027-09-30'),
(17, 'Malayan Insurance', 'POL-2026-0117', 'Comprehensive', 1800000.00, '2026-10-01', '2027-09-30'),
(18, 'Malayan Insurance', 'POL-2026-0118', 'Comprehensive', 1800000.00, '2026-10-01', '2027-09-30'),
(19, 'Malayan Insurance', 'POL-2026-0119', 'Comprehensive', 1500000.00, '2026-10-01', '2027-09-30'),
(20, 'Malayan Insurance', 'POL-2026-0120', 'Comprehensive', 1700000.00, '2026-10-01', '2027-09-30'),
(21, 'Malayan Insurance', 'POL-2026-0121', 'Comprehensive', 1700000.00, '2026-10-01', '2027-09-30'),
(22, 'Malayan Insurance', 'POL-2026-0122', 'Collision',      120000.00, '2026-10-01', '2027-09-30');

-- Vehicle 1's next service date has already passed; vehicle 5 is in the shop now
INSERT INTO maintenance_records (vehicle_id, service_type, description, service_date, next_service_date, next_service_mileage, cost, status) VALUES
(1, 'Preventive Maintenance', 'Oil change and brake inspection',  '2026-07-01', '2026-10-01', 35000, 4500.00,  'Completed'),
(3, 'Preventive Maintenance', 'Oil change and tire rotation',     '2026-08-10', '2026-11-10', 50000, 6200.00,  'Completed'),
(4, 'Preventive Maintenance', 'Scheduled 40,000 km service',      '2026-10-25', '2027-01-25', 48000, 0.00,     'Scheduled'),
(5, 'Engine Repair',          'Overheating issue, radiator replaced','2026-10-12','2026-12-12', 25000, 18500.00, 'In Progress'),
(7, 'Preventive Maintenance', 'Oil change and filter replacement','2026-09-01', '2026-12-01', 20000, 5200.00,  'Completed'),
(9, 'Tune-up',                'Spark plug and belt replacement',  '2026-08-20', '2027-02-20', 8000,  1800.00,  'Completed');

INSERT INTO reservations (customer_id, vehicle_id, employee_id, start_date, end_date, status, created_at) VALUES
(1, 1,  3, '2026-09-01', '2026-09-05', 'Completed', '2026-08-25 10:00:00'),
(2, 3,  3, '2026-09-10', '2026-09-14', 'Completed', '2026-09-02 14:30:00'),
(3, 5,  5, '2026-09-15', '2026-09-17', 'Completed', '2026-09-08 09:15:00'),
(4, 7,  6, '2026-09-20', '2026-09-25', 'Completed', '2026-09-10 11:45:00'),
(5, 9,  3, '2026-10-01', '2026-10-03', 'No-Show',   '2026-09-25 16:20:00'),
(1, 2,  3, '2026-10-10', '2026-10-17', 'Confirmed', '2026-10-03 13:00:00'),
(6, 4,  5, '2026-10-20', '2026-10-24', 'No-Show',   '2026-10-09 10:10:00'),
(2, 1,  3, '2026-10-05', '2026-10-08', 'Cancelled', '2026-09-30 15:05:00');

-- reservation_id NULL = walk-in. Rentals 6 and 7 are OVERDUE (not yet returned)
INSERT INTO rentals (reservation_id, customer_id, vehicle_id, employee_id, pickup_branch_id, return_branch_id,
                     rental_date, due_date, return_date, start_mileage, end_mileage, total_amount, status) VALUES
(1,    1, 1,  3, 1, 1,    '2026-09-01 09:00:00', '2026-09-05 09:00:00', '2026-09-05 08:30:00', 30000, 30400, 6000.00,  'Returned'),
(2,    2, 3,  3, 1, 1,    '2026-09-10 10:00:00', '2026-09-14 10:00:00', '2026-09-14 15:00:00', 44000, 44600, 12000.00, 'Returned'),
(3,    3, 5,  5, 2, 2,    '2026-09-15 08:00:00', '2026-09-17 08:00:00', '2026-09-17 08:00:00', 20000, 20250, 7000.00,  'Returned'),
(4,    4, 7,  6, 3, 3,    '2026-09-20 09:00:00', '2026-09-25 09:00:00', '2026-09-26 09:30:00', 15000, 15900, 16000.00, 'Returned'),
(NULL, 7, 9,  3, 1, 1,    '2026-09-28 09:00:00', '2026-09-30 09:00:00', '2026-09-30 09:00:00', 5000,  5100,  1200.00,  'Returned'),
(NULL, 5, 10, 6, 3, NULL, '2026-10-08 10:00:00', '2026-10-12 10:00:00', NULL,                  8000,  NULL,  2400.00,  'Overdue'),
(6,    1, 2,  3, 1, NULL, '2026-10-10 09:00:00', '2026-10-17 09:00:00', NULL,                  30000, NULL,  9100.00,  'Overdue'),
(NULL, 3, 8,  5, 2, 2,    '2026-08-01 09:00:00', '2026-08-03 09:00:00', '2026-08-03 09:00:00', 22000, 22300, 6400.00,  'Returned'),
(NULL, 6, 3,  3, 1, 1,    '2026-08-15 09:00:00', '2026-08-20 09:00:00', '2026-08-20 09:00:00', 43000, 43700, 15000.00, 'Returned');

INSERT INTO payments (rental_id, amount, payment_date, payment_method, payment_type, reference_number, status) VALUES
(1, 6000.00,  '2026-09-01 09:05:00', 'Cash',          'Rental Fee', NULL,              'Paid'),
(2, 3000.00,  '2026-09-10 10:05:00', 'GCash',         'Deposit',    'GC-20260910-001', 'Paid'),
(2, 9000.00,  '2026-09-14 15:10:00', 'GCash',         'Rental Fee', 'GC-20260914-002', 'Paid'),
(2, 1200.00,  '2026-09-14 15:15:00', 'Cash',          'Late Fee',   NULL,              'Paid'),
(3, 7000.00,  '2026-09-15 08:10:00', 'Credit Card',   'Rental Fee', 'CC-8841',         'Paid'),
(4, 16000.00, '2026-09-20 09:10:00', 'Bank Transfer', 'Rental Fee', 'BT-77310',        'Paid'),
(4, 1600.00,  '2026-09-26 09:40:00', 'Cash',          'Late Fee',   NULL,              'Paid'),
(5, 1200.00,  '2026-09-28 09:05:00', 'Cash',          'Rental Fee', NULL,              'Paid'),
(6, 1200.00,  '2026-10-08 10:05:00', 'Cash',          'Deposit',    NULL,              'Paid'),
(7, 5000.00,  '2026-10-10 09:05:00', 'GCash',         'Deposit',    'GC-20261010-003', 'Paid'),
(8, 6400.00,  '2026-08-01 09:05:00', 'Cash',          'Rental Fee', NULL,              'Paid'),
(9, 15000.00, '2026-08-15 09:05:00', 'Debit Card',    'Rental Fee', 'DC-5521',         'Paid');

INSERT INTO late_fees (rental_id, days_late, fee_amount, computed_on, status) VALUES
(2, 1, 1200.00, '2026-09-14 15:00:00', 'Paid'),
(4, 1, 1600.00, '2026-09-26 09:30:00', 'Paid'),
(6, 3, 1800.00, '2026-10-15 08:00:00', 'Unpaid'),
(7, 8, 12000.00,'2026-10-25 08:00:00', 'Unpaid');

INSERT INTO rental_status_history (rental_id, changed_by, old_status, new_status, changed_at, remarks) VALUES
(1, 3, NULL,     'Active',   '2026-09-01 09:00:00', 'Rental created from reservation'),
(1, 3, 'Active', 'Returned', '2026-09-05 08:30:00', 'Returned on time'),
(2, 3, NULL,     'Active',   '2026-09-10 10:00:00', 'Rental created from reservation'),
(2, 3, 'Active', 'Returned', '2026-09-14 15:00:00', 'Returned 5 hours late, late fee applied'),
(3, 5, NULL,     'Active',   '2026-09-15 08:00:00', 'Rental created from reservation'),
(3, 5, 'Active', 'Returned', '2026-09-17 08:00:00', 'Returned on time'),
(4, 6, NULL,     'Active',   '2026-09-20 09:00:00', 'Rental created from reservation'),
(4, 6, 'Active', 'Returned', '2026-09-26 09:30:00', 'Returned 1 day late, late fee applied'),
(6, 6, NULL,     'Active',   '2026-10-08 10:00:00', 'Walk-in rental'),
(6, 6, 'Active', 'Overdue',  '2026-10-12 10:05:00', 'Not returned by due date'),
(7, 3, NULL,     'Active',   '2026-10-10 09:00:00', 'Rental created from reservation'),
(7, 3, 'Active', 'Overdue',  '2026-10-17 09:05:00', 'Not returned by due date');

INSERT INTO damage_reports (rental_id, vehicle_id, reported_by, description, severity, repair_cost, reported_date, status) VALUES
(4, 7, 6, 'Scratch on rear bumper',  'Minor',    3500.00, '2026-09-26', 'Resolved'),
(2, 3, 3, 'Cracked right side mirror','Moderate', 4800.00, '2026-09-14', 'Under Repair');

INSERT INTO activity_logs (employee_id, action, table_name, record_id, description, logged_at) VALUES
(3, 'LOGIN',  'employees',    3,    'jose.staff logged in',                   '2026-10-10 08:55:00'),
(3, 'CREATE', 'rentals',      7,    'Created rental 7 for customer 1',        '2026-10-10 09:00:00'),
(6, 'UPDATE', 'rentals',      6,    'Rental 6 marked Overdue',                '2026-10-12 10:05:00'),
(1, 'UPDATE', 'vehicles',     5,    'Vehicle 5 set to Maintenance',           '2026-10-12 11:00:00'),
(2, 'CREATE', 'rate_plans',   9,    'Added Holiday Peak plan for Sedans',     '2026-09-30 14:00:00'),
(6, 'CREATE', 'late_fees',    3,    'Late fee computed for rental 6',         '2026-10-15 08:00:00'),
(3, 'UPDATE', 'rentals',      7,    'Rental 7 marked Overdue',                '2026-10-17 09:05:00');

-- ---------------------------------------------------------------------
-- App logins: every sample employee has password 123.
-- Main account:  username  harvey  /  password  123
-- ---------------------------------------------------------------------
UPDATE employees SET username = 'harvey', first_name = 'Harvey' WHERE employee_id = 1;
