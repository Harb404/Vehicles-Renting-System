// Edit these to match YOUR MySQL install. (Environment variables override them.)
module.exports = {
  host:     process.env.DB_HOST     || 'localhost',
  port:     Number(process.env.DB_PORT) || 3306,
  user:     process.env.DB_USER     || 'root',
  password: process.env.DB_PASSWORD || '',        // <- put your MySQL root password here
  database: process.env.DB_NAME     || 'vehicle_rental',
};
