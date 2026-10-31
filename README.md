

 MySQL (database) Node.js + Express (server/API) · HTML, CSS, JavaScript (frontend)

1. Install 
- Node.js (LTS) — https://nodejs.org
- **MySQL Community Server — https://dev.mysql.com/downloads/mysql/ (the installer also offers MySQL Workbench).

   Remember the root password you set. (MariaDB works too.)

2. Set up the database
Pick one:
- MySQL Workbench: connect → *File → Open SQL Script* → choose `sql/vehicle_rental.sql` → click the lightning-bolt run button.
- Command line: `mysql -u root -p < sql/vehicle_rental.sql`

This creates the `vehicle_rental` database with 16 tables and sample data. It is safe to re-run for a clean reset.

 3. Configure
Open `config.js` and put your MySQL root password in `password: ''`.

4. Run
```
npm install
npm start
```
Open **http://localhost:3000**

Login: username `harvey` · password `123` (other sample accounts: `maria.mgr`, `jose.staff`, same password).
Customers can sign up from the Register here link on the login page.



 Project layout
```
index.js        Express server + REST API (/api/...)
config.js       MySQL connection settings
sql/            vehicle_rental.sql (schema + sample data)
public/         index.html, app.js, style.css  (the website)
```

 Notes
- Passwords are stored as bcrypt hashes. To change one:
  `node -e "console.log(require('bcryptjs').hashSync('newpassword',10))"` then
  `UPDATE employees SET password_hash='<hash>' WHERE username='harvey';`

- Before sharing publicly, set a strong `SESSION_SECRET` environment variable and change the default password.

since mangayo mana hashing si sir