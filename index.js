//pede ra e change or ang config.js para sa database connection
//pede ra e change ang port sa .env file or sa PORT environment variable
//bcryptjs is used for hashing employee passwords or admin 
// passwords, so make sure to use it when creating new employees
//idk na ang part ani since old nmn pero inaani ra nako ge himo




//---------------------------------------------------------------------------//



const express = require('express');
const session = require('express-session');
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const path = require('path');
const cfg = require('./config');

const pool = mysql.createPool({...cfg, dateStrings: true, connectionLimit: 10 });
const app = express();
app.use(express.json());
app.use(session({
    secret: process.env.SESSION_SECRET || 'change-this-secret',
    resave: false,
    saveUninitialized: false,
    cookie: { httpOnly: true, sameSite: 'lax', maxAge: 8 * 3600 * 1000 },
}));
app.use(express.static(path.join(__dirname, 'public')));

// ---------- helpers ----------
class HttpError extends Error {
    constructor(status, msg) {
        super(msg);
        this.status = status;
    }
}
const bad = (msg, status = 400) => { throw new HttpError(status, msg); };
const pad = n => String(n).padStart(2, '0');
const fmt = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const today = () => fmt(new Date()).slice(0, 10);
const toDate = s => new Date(String(s).replace(' ', 'T'));
const need = (req, res, next) => req.session.emp ? next() : res.status(401).json({ error: 'Please log in.' });
const log = (db, emp, action, table, id, desc) =>
    db.query('INSERT INTO activity_logs (employee_id, action, table_name, record_id, description) VALUES (?,?,?,?,?)', [emp, action, table, id, desc]);

// pick the rate plan that fits the number of days (non-seasonal)
async function dailyRate(db, categoryId, days) {
    const [r] = await db.query(
        `SELECT rate_per_day FROM rate_plans WHERE category_id = ? AND season_start IS NULL
     AND min_days <= ? AND (max_days IS NULL OR max_days >= ?) ORDER BY min_days DESC LIMIT 1`, [categoryId, days, days]);
    return r.length ? Number(r[0].rate_per_day) : 0;
}

const CUST = ['first_name', 'middle_name', 'last_name', 'birth_date', 'gender', 'email', 'phone', 'street', 'barangay', 'city',
    'province', 'postal_code', 'license_number', 'license_expiry_date', 'emergency_contact_name', 'emergency_contact_phone'
];
async function addCustomer(b) {
    const v = {};
    CUST.forEach(k => v[k] = String(b[k] ? b[k] : '').trim());
    for (const k of CUST)
        if (k !== 'middle_name' && !v[k]) bad(k.replace(/_/g, ' ') + ' is required.');
    if (!/^\S+@\S+\.\S+$/.test(v.email)) bad('Email is not valid.');
    if (!['Male', 'Female', 'Other'].includes(v.gender)) bad('Pick a gender.');
    const lim = new Date();
    lim.setFullYear(lim.getFullYear() - 18);
    if (new Date(v.birth_date) > lim) bad('Customer must be at least 18 years old.');
    if (v.license_expiry_date <= today()) bad("The driver's license is expired.");
    try {
        const [r] = await pool.query(`INSERT INTO customers (${CUST.join(',')}) VALUES (${CUST.map(() => '?').join(',')})`, CUST.map(k => v[k] || null));
        return r.insertId;
    } catch (e) {
        if (e.code === 'ER_DUP_ENTRY') bad('That email or license number is already registered.', 409);
        if (e.errno === 3819 || e.errno === 4025) bad('License must expire after the customer turns 18.');
        throw e;
    }
}

// ---------- auth ----------
app.post('/api/login', async(req, res) => {
    const [
        [e]
    ] = await pool.query("SELECT * FROM employees WHERE username = ? AND status = 'Active'", [String(req.body.username || '').trim()]);
    if (!e || !(await bcrypt.compare(String(req.body.password || ''), e.password_hash))) bad('Wrong username or password.', 401);
    await new Promise(r => req.session.regenerate(r));
    req.session.emp = { id: e.employee_id, name: e.first_name, username: e.username };
    await log(pool, e.employee_id, 'LOGIN', 'employees', e.employee_id, e.username + ' logged in');
    res.json(req.session.emp);
});
app.post('/api/logout', (req, res) => req.session.destroy(() => res.json({ ok: true })));
app.get('/api/me', (req, res) => req.session.emp ? res.json(req.session.emp) : res.status(401).json({ error: 'Not logged in.' }));

// public: customers sign themselves up
app.post('/api/register', async(req, res) => { res.json({ id: await addCustomer(req.body) }); });

// ---------- lookups & dashboard ----------
app.get('/api/lookups', need, async(req, res) => {
    const q = async s => (await pool.query(s))[0];
    res.json({
        categories: await q('SELECT category_id id, category_name name FROM vehicle_categories'),
        branches: await q('SELECT branch_id id, branch_name name FROM branches'),
        customers: await q("SELECT customer_id id, CONCAT(last_name, ', ', first_name) name FROM customers WHERE status='Active' ORDER BY last_name"),
        available: await q("SELECT vehicle_id id, CONCAT(brand,' ',model,' · ',plate_number) name FROM vehicles WHERE status='Available' ORDER BY brand"),
        bookable: await q("SELECT vehicle_id id, CONCAT(brand,' ',model,' · ',plate_number) name FROM vehicles WHERE status NOT IN ('Maintenance','Unavailable') ORDER BY brand"),
    });
});

const RENTAL_LIST = `SELECT r.*, CONCAT(c.first_name,' ',c.last_name) customer, CONCAT(v.brand,' ',v.model) vehicle, b.branch_name
  FROM rentals r JOIN customers c ON c.customer_id = r.customer_id JOIN vehicles v ON v.vehicle_id = r.vehicle_id
  JOIN branches b ON b.branch_id = r.pickup_branch_id`;
const markOverdue = () => pool.query("UPDATE rentals SET status='Overdue' WHERE status='Active' AND due_date < NOW()");

app.get('/api/dashboard', need, async(req, res) => {
    await markOverdue();
    const one = async s => Object.values((await pool.query(s))[0][0])[0];
    res.json({
        stats: {
            'Available vehicles': await one("SELECT COUNT(*) FROM vehicles WHERE status='Available'"),
            'Rented out': await one("SELECT COUNT(*) FROM vehicles WHERE status='Rented'"),
            'Overdue rentals': await one("SELECT COUNT(*) FROM rentals WHERE status='Overdue'"),
            'Active customers': await one("SELECT COUNT(*) FROM customers WHERE status='Active'"),
            'Revenue (paid)': Number(await one("SELECT COALESCE(SUM(amount),0) FROM payments WHERE status='Paid'")),
        },
        recent: (await pool.query(RENTAL_LIST + ' ORDER BY r.rental_date DESC LIMIT 8'))[0],
    });
});

// ---------- vehicles ----------
app.get('/api/vehicles', need, async(req, res) => {
    const st = req.query.status;
    const [rows] = await pool.query(`SELECT v.*, c.category_name, b.branch_name FROM vehicles v
    JOIN vehicle_categories c ON c.category_id = v.category_id JOIN branches b ON b.branch_id = v.branch_id
    ${st ? 'WHERE v.status = ?' : ''} ORDER BY v.vehicle_id`, st ? [st] : []);
    res.json(rows);
});
app.post('/api/vehicles', need, async(req, res) => {
    const b = req.body;
    for (const k of['category_id', 'branch_id', 'plate_number', 'brand', 'model', 'year', 'color', 'transmission', 'fuel_type', 'seats'])
        if (!String(b[k] ? b[k] : '').trim()) bad(k.replace(/_/g, ' ') + ' is required.');
    try {
        const [r] = await pool.query(`INSERT INTO vehicles (category_id,branch_id,plate_number,brand,model,year,color,transmission,fuel_type,seats,mileage)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)`, [b.category_id, b.branch_id, b.plate_number.trim().toUpperCase(), b.brand.trim(), b.model.trim(),
            b.year, b.color.trim(), b.transmission, b.fuel_type, b.seats, b.mileage || 0
        ]);
        await log(pool, req.session.emp.id, 'CREATE', 'vehicles', r.insertId, 'Added vehicle ' + b.plate_number);
        res.json({ id: r.insertId });
    } catch (e) {
        if (e.code === 'ER_DUP_ENTRY') bad('That plate number already exists.', 409);
        if (e.errno === 3819 || e.errno === 4025) bad('Check the year (1990-2100) and seats.');
        throw e;
    }
});

// ---------- customers ----------
app.get('/api/customers', need, async(req, res) => {
    const [rows] = await pool.query(`SELECT * FROM customers WHERE CONCAT(first_name,' ',last_name,' ',email,' ',license_number) LIKE ? ORDER BY customer_id DESC`, ['%' + (req.query.q || '') + '%']);
    res.json(rows);
});
app.post('/api/customers', need, async(req, res) => {
    const id = await addCustomer(req.body);
    await log(pool, req.session.emp.id, 'CREATE', 'customers', id, 'Registered ' + req.body.email);
    res.json({ id });
});

// ---------- reservations ----------
app.get('/api/reservations', need, async(req, res) => {
    const [rows] = await pool.query(`SELECT r.*, CONCAT(c.first_name,' ',c.last_name) customer, CONCAT(v.brand,' ',v.model,' · ',v.plate_number) vehicle
    FROM reservations r JOIN customers c ON c.customer_id = r.customer_id JOIN vehicles v ON v.vehicle_id = r.vehicle_id ORDER BY r.reservation_id DESC`);
    res.json(rows);
});
app.post('/api/reservations', need, async(req, res) => {
    const { customer_id, vehicle_id, start_date, end_date } = req.body;
    if (!customer_id || !vehicle_id || !start_date || !end_date) bad('Fill in every field.');
    if (end_date < start_date || start_date < today()) bad('Invalid dates.');
    const [
        [c]
    ] = await pool.query('SELECT status FROM customers WHERE customer_id = ?', [customer_id]);
    if (!c || c.status !== 'Active') bad('Customer is blacklisted or not found.');
    const [
        [o]
    ] = await pool.query(`SELECT COUNT(*) n FROM reservations WHERE vehicle_id = ? AND status IN ('Pending','Confirmed') AND start_date <= ? AND end_date >= ?`, [vehicle_id, end_date, start_date]);
    if (o.n > 0) bad('That vehicle is already booked for those dates.', 409);
    const [r] = await pool.query('INSERT INTO reservations (customer_id,vehicle_id,employee_id,start_date,end_date) VALUES (?,?,?,?,?)', [customer_id, vehicle_id, req.session.emp.id, start_date, end_date]);
    await log(pool, req.session.emp.id, 'CREATE', 'reservations', r.insertId, 'Reservation for vehicle ' + vehicle_id);
    res.json({ id: r.insertId });
});
app.post('/api/reservations/:id/status', need, async(req, res) => {
    const s = req.body.status;
    if (!['Confirmed', 'Cancelled'].includes(s)) bad('Invalid status.');
    await pool.query("UPDATE reservations SET status = ? WHERE reservation_id = ? AND status IN ('Pending','Confirmed')", [s, req.params.id]);
    await log(pool, req.session.emp.id, 'UPDATE', 'reservations', req.params.id, 'Reservation set to ' + s);
    res.json({ ok: true });
});

// ---------- rentals ----------
app.get('/api/rentals', need, async(req, res) => {
    await markOverdue();
    res.json((await pool.query(RENTAL_LIST + ' ORDER BY r.rental_id DESC'))[0]);
});
app.post('/api/rentals', need, async(req, res) => {
    const b = req.body,
        emp = req.session.emp.id,
        conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const [
            [veh]
        ] = await conn.query("SELECT * FROM vehicles WHERE vehicle_id = ? AND status = 'Available' FOR UPDATE", [b.vehicle_id]);
        const [
            [cust]
        ] = await conn.query("SELECT * FROM customers WHERE customer_id = ? AND status = 'Active'", [b.customer_id]);
        const now = new Date(),
            due = new Date(b.due_date);
        if (!veh) bad('Vehicle is not available.');
        if (!cust) bad('Customer is blacklisted or not found.');
        if (isNaN(due) || due <= now) bad('Due date must be in the future.');
        if (cust.license_expiry_date < fmt(due).slice(0, 10)) bad("Customer's license expires before the due date.");
        const days = Math.max(1, Math.ceil((due - now) / 86400000));
        const total = (await dailyRate(conn, veh.category_id, days)) * days;
        const [r] = await conn.query(`INSERT INTO rentals (customer_id,vehicle_id,employee_id,pickup_branch_id,rental_date,due_date,start_mileage,total_amount)
      VALUES (?,?,?,?,?,?,?,?)`, [cust.customer_id, veh.vehicle_id, emp, veh.branch_id, fmt(now), fmt(due), veh.mileage, total]);
        await conn.query("UPDATE vehicles SET status = 'Rented' WHERE vehicle_id = ?", [veh.vehicle_id]);
        await conn.query('INSERT INTO rental_status_history (rental_id,changed_by,old_status,new_status,remarks) VALUES (?,?,NULL,?,?)', [r.insertId, emp, 'Active', 'Walk-in rental']);
        await log(conn, emp, 'CREATE', 'rentals', r.insertId, 'Created rental ' + r.insertId);
        await conn.commit();
        res.json({ id: r.insertId, days, total });
    } catch (e) { await conn.rollback(); throw e; } finally { conn.release(); }
});
app.post('/api/rentals/:id/return', need, async(req, res) => {
    const emp = req.session.emp.id,
        conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const [
            [rent]
        ] = await conn.query(`SELECT r.*, v.category_id FROM rentals r JOIN vehicles v ON v.vehicle_id = r.vehicle_id
      WHERE r.rental_id = ? AND r.status IN ('Active','Overdue') FOR UPDATE`, [req.params.id]);
        if (!rent) bad('Rental not found or already returned.');
        const endKm = parseInt(req.body.end_mileage, 10);
        if (isNaN(endKm) || endKm < rent.start_mileage) bad('End mileage cannot be lower than the start mileage.');
        const now = new Date(),
            due = toDate(rent.due_date);
        let remark = 'Returned on time',
            fee = 0,
            daysLate = 0;
        if (now > due) { // late fee = 50% of the daily rate for each late day
            daysLate = Math.ceil((now - due) / 86400000);
            fee = daysLate * (await dailyRate(conn, rent.category_id, 1)) * 0.5;
            await conn.query('INSERT INTO late_fees (rental_id,days_late,fee_amount) VALUES (?,?,?)', [rent.rental_id, daysLate, fee]);
            remark = `Returned ${daysLate} day(s) late, late fee ${fee.toFixed(2)}`;
        }
        await conn.query("UPDATE rentals SET status='Returned', return_date=?, end_mileage=?, return_branch_id=? WHERE rental_id=?", [fmt(now), endKm, req.body.return_branch_id, rent.rental_id]);
        await conn.query("UPDATE vehicles SET status='Available', mileage=?, branch_id=? WHERE vehicle_id=?", [endKm, req.body.return_branch_id, rent.vehicle_id]);
        await conn.query('INSERT INTO rental_status_history (rental_id,changed_by,old_status,new_status,remarks) VALUES (?,?,?,?,?)', [rent.rental_id, emp, rent.status, 'Returned', remark]);
        await log(conn, emp, 'UPDATE', 'rentals', rent.rental_id, remark);
        await conn.commit();
        res.json({ remark, fee, daysLate });
    } catch (e) { await conn.rollback(); throw e; } finally { conn.release(); }
});

// ---------- reports (JOINs) ----------
const REPORTS = {
    overdue: `SELECT r.rental_id, CONCAT(c.first_name,' ',c.last_name) AS customer, c.phone, CONCAT(v.brand,' ',v.model) AS vehicle,
      r.due_date, DATEDIFF(NOW(), r.due_date) AS days_overdue, COALESCE(SUM(lf.fee_amount),0) AS late_fees
    FROM rentals r JOIN customers c ON c.customer_id=r.customer_id JOIN vehicles v ON v.vehicle_id=r.vehicle_id
    LEFT JOIN late_fees lf ON lf.rental_id=r.rental_id AND lf.status='Unpaid'
    WHERE r.status='Overdue' GROUP BY r.rental_id ORDER BY days_overdue DESC`,
    insurance: `SELECT v.plate_number, CONCAT(v.brand,' ',v.model) AS vehicle, v.status
    FROM vehicles v LEFT JOIN insurance i ON i.vehicle_id=v.vehicle_id AND i.expiry_date >= CURDATE() WHERE i.insurance_id IS NULL`,
    revenue: `SELECT b.branch_name, COUNT(DISTINCT r.rental_id) AS rentals, SUM(p.amount) AS revenue
    FROM payments p JOIN rentals r ON r.rental_id=p.rental_id JOIN branches b ON b.branch_id=r.pickup_branch_id
    WHERE p.status='Paid' GROUP BY b.branch_id ORDER BY revenue DESC`,
    categories: `SELECT vc.category_name, COUNT(r.rental_id) AS total_rentals, COALESCE(SUM(r.total_amount),0) AS billed
    FROM vehicle_categories vc LEFT JOIN vehicles v ON v.category_id=vc.category_id LEFT JOIN rentals r ON r.vehicle_id=v.vehicle_id
    GROUP BY vc.category_id ORDER BY total_rentals DESC`,
    norentals: `SELECT c.customer_id, CONCAT(c.first_name,' ',c.last_name) AS customer, c.email, c.date_registered
    FROM customers c LEFT JOIN rentals r ON r.customer_id=c.customer_id WHERE r.rental_id IS NULL`,
};
app.get('/api/reports/:name', need, async(req, res) => {
    if (!REPORTS[req.params.name]) bad('Unknown report.', 404);
    res.json((await pool.query(REPORTS[req.params.name]))[0]);
});

// ---------- errors ----------
app.use('/api', (req, res) => res.status(404).json({ error: 'Not found.' }));
app.use((err, req, res, next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
    console.error(err);
    res.status(500).json({ error: 'Server error: ' + (err.sqlMessage || err.message) });
});

const PORT = process.env.PORT || 3000;
pool.query('SELECT 1').then(() => console.log('✅ Database connected.'))
    .catch(e => console.error('\n❌ Cannot connect to MySQL: ' + e.message + '\n   Is MySQL running? Check the password in config.js\n'));
app.listen(PORT, () => console.log(`🚗 Vehicle Rental running at http://localhost:${PORT}`));