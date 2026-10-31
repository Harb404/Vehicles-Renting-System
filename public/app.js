// ---------- tiny helpers ----------
const $ = (s, r = document) => r.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = n => '₱' + Number(n || 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const badge = s => `<span class="badge ${esc(s)}">${esc(s)}</span>`;
const t = k => r => esc(r[k]);

function toast(msg, err) {
  const el = $('#toast'); el.textContent = msg; el.className = 'show' + (err ? ' err' : '');
  clearTimeout(toast.id); toast.id = setTimeout(() => el.className = '', 4500);
}
async function api(url, method = 'GET', body) {
  const r = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) { const e = new Error(d.error || 'Request failed'); e.status = r.status; throw e; }
  return d;
}
const el = html => { const x = document.createElement('template'); x.innerHTML = html.trim(); return x.content.firstElementChild; };
const table = (cols, rows) => !rows.length ? '<p>No records.</p>' :
  `<div class="wrap"><table><tr>${cols.map(c => `<th>${esc(c[0])}</th>`).join('')}</tr>` +
  rows.map(r => `<tr>${cols.map(c => `<td>${c[1](r)}</td>`).join('')}</tr>`).join('') + '</table></div>';
const plainTable = (rows, moneyKeys = []) => table(
  Object.keys(rows[0] || {}).map(k => [k.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()), r => moneyKeys.includes(k) ? money(r[k]) : esc(r[k] ?? '—')]), rows);

// build a form from field specs: {name,label,type,options:[...],req,attrs,value}
function form(fields, submitText, onSubmit) {
  const f = el(`<form class="box">${fields.map(x => {
    const input = x.options
      ? `<select name="${x.name}">${x.options.map(o => { const [v, tx] = Array.isArray(o) ? o : [o, o]; return `<option value="${esc(v)}">${esc(tx)}</option>`; }).join('')}</select>`
      : `<input name="${x.name}" type="${x.type || 'text'}" ${x.req === false ? '' : 'required'} ${x.attrs || ''} value="${esc(x.value ?? '')}">`;
    return `<label>${esc(x.label)} ${input}</label>`;
  }).join('')}<div class="end"><button>${esc(submitText)}</button></div></form>`);
  f.onsubmit = async e => {
    e.preventDefault();
    try { await onSubmit(Object.fromEntries(new FormData(f)), f); } catch (err) { if (err.status === 401 && !$('#shell').classList.contains('hidden')) return showAuth(); toast(err.message, true); }
  };
  return f;
}
const adultMax = () => { const d = new Date(); d.setFullYear(d.getFullYear() - 18); return d.toISOString().slice(0, 10); };
const tomorrow = () => new Date(Date.now() + 864e5).toISOString().slice(0, 10);
const customerFields = () => [
  { label: 'First name', name: 'first_name' }, { label: 'Middle name (optional)', name: 'middle_name', req: false }, { label: 'Last name', name: 'last_name' },
  { label: 'Birth date', name: 'birth_date', type: 'date', attrs: `max="${adultMax()}"` }, { label: 'Gender', name: 'gender', options: ['Male', 'Female', 'Other'] },
  { label: 'Email', name: 'email', type: 'email' }, { label: 'Phone', name: 'phone' }, { label: 'Street', name: 'street' }, { label: 'Barangay', name: 'barangay' },
  { label: 'City', name: 'city' }, { label: 'Province', name: 'province' }, { label: 'Postal code', name: 'postal_code' },
  { label: "Driver's license no.", name: 'license_number' }, { label: 'License expiry', name: 'license_expiry_date', type: 'date', attrs: `min="${tomorrow()}"` },
  { label: 'Emergency contact name', name: 'emergency_contact_name' }, { label: 'Emergency contact phone', name: 'emergency_contact_phone' },
];
const opts = list => list.map(x => [x.id, x.name]);

// ---------- views ----------
const rentalCols = [['#', t('rental_id')], ['Customer', t('customer')], ['Vehicle', t('vehicle')], ['Pickup', t('branch_name')],
  ['Rented', t('rental_date')], ['Due', t('due_date')], ['Returned', r => esc(r.return_date ?? '—')],
  ['Total', r => money(r.total_amount)], ['Status', r => badge(r.status)]];

const views = {
  async dashboard(v) {
    const d = await api('/api/dashboard');
    v.innerHTML = `<h1>Dashboard</h1><div class="cards">${Object.entries(d.stats).map(([k, x]) =>
      `<div class="card">${esc(k)}<b>${k.startsWith('Revenue') ? money(x) : esc(x)}</b></div>`).join('')}</div><h2>Recent rentals</h2>` + table(rentalCols, d.recent);
  },

  async vehicles(v) {
    const status = new URLSearchParams(location.hash.split('?')[1] || '').get('status') || '';
    const [rows, lk] = await Promise.all([api('/api/vehicles' + (status ? '?status=' + encodeURIComponent(status) : '')), api('/api/lookups')]);
    v.innerHTML = `<h1>Vehicles</h1><label style="display:inline-flex;flex-direction:row;gap:8px;align-items:center;margin-bottom:12px">Filter:
      <select id="flt"><option value="">All</option>${['Available', 'Reserved', 'Rented', 'Maintenance', 'Unavailable'].map(s => `<option ${s === status ? 'selected' : ''}>${s}</option>`).join('')}</select></label>` +
      table([['Plate', t('plate_number')], ['Vehicle', r => esc(`${r.brand} ${r.model} (${r.year})`)], ['Category', t('category_name')], ['Branch', t('branch_name')],
        ['Trans.', t('transmission')], ['Fuel', t('fuel_type')], ['Seats', t('seats')], ['Mileage', r => Number(r.mileage).toLocaleString() + ' km'], ['Status', r => badge(r.status)]], rows) + '<h2>Add vehicle</h2>';
    $('#flt').onchange = e => { location.hash = '#vehicles' + (e.target.value ? '?status=' + e.target.value : ''); };
    v.append(form([
      { label: 'Plate number', name: 'plate_number' }, { label: 'Brand', name: 'brand' }, { label: 'Model', name: 'model' },
      { label: 'Year', name: 'year', type: 'number', attrs: 'min="1990" max="2100"' }, { label: 'Color', name: 'color' },
      { label: 'Category', name: 'category_id', options: opts(lk.categories) }, { label: 'Branch', name: 'branch_id', options: opts(lk.branches) },
      { label: 'Transmission', name: 'transmission', options: ['Automatic', 'Manual'] }, { label: 'Fuel', name: 'fuel_type', options: ['Gasoline', 'Diesel', 'Electric', 'Hybrid'] },
      { label: 'Seats', name: 'seats', type: 'number', value: 5, attrs: 'min="1"' }, { label: 'Mileage (km)', name: 'mileage', type: 'number', value: 0, req: false, attrs: 'min="0"' },
    ], 'Add vehicle', async d => { await api('/api/vehicles', 'POST', d); toast('Vehicle added.'); render(); }));
  },

  async customers(v) {
    const q = new URLSearchParams(location.hash.split('?')[1] || '').get('q') || '';
    const rows = await api('/api/customers?q=' + encodeURIComponent(q));
    v.innerHTML = `<h1>Customers</h1><form id="sf" style="margin-bottom:12px"><input id="q" placeholder="Search name, email, license" value="${esc(q)}"> <button>Search</button></form>` +
      table([['#', t('customer_id')], ['Name', r => esc(`${r.first_name} ${r.last_name}`)], ['Email', t('email')], ['Phone', t('phone')], ['City', t('city')],
        ['License', t('license_number')], ['Expires', t('license_expiry_date')], ['Status', r => badge(r.status)]], rows) + '<h2>Register customer</h2>';
    $('#sf').onsubmit = e => { e.preventDefault(); location.hash = '#customers?q=' + encodeURIComponent($('#q').value); };
    v.append(form(customerFields(), 'Register', async d => { await api('/api/customers', 'POST', d); toast('Customer registered.'); render(); }));
  },

  async reservations(v) {
    const [rows, lk] = await Promise.all([api('/api/reservations'), api('/api/lookups')]);
    v.innerHTML = '<h1>Reservations</h1>' + table([['#', t('reservation_id')], ['Customer', t('customer')], ['Vehicle', t('vehicle')], ['Start', t('start_date')], ['End', t('end_date')],
      ['Status', r => badge(r.status)], ['', r => ['Pending', 'Confirmed'].includes(r.status)
        ? (r.status === 'Pending' ? `<button class="small green act" data-id="${r.reservation_id}" data-s="Confirmed">Confirm</button> ` : '') +
          `<button class="small red act" data-id="${r.reservation_id}" data-s="Cancelled">Cancel</button>` : '']], rows) + '<h2>New reservation</h2>';
    v.onclick = async e => {
      const b = e.target.closest('.act'); if (!b || (b.dataset.s === 'Cancelled' && !confirm('Cancel this reservation?'))) return;
      try { await api(`/api/reservations/${b.dataset.id}/status`, 'POST', { status: b.dataset.s }); toast('Reservation ' + b.dataset.s + '.'); render(); } catch (err) { toast(err.message, true); }
    };
    v.append(form([
      { label: 'Customer', name: 'customer_id', options: opts(lk.customers) }, { label: 'Vehicle', name: 'vehicle_id', options: opts(lk.bookable) },
      { label: 'Start date', name: 'start_date', type: 'date', attrs: `min="${new Date().toISOString().slice(0, 10)}"` },
      { label: 'End date', name: 'end_date', type: 'date', attrs: `min="${new Date().toISOString().slice(0, 10)}"` },
    ], 'Reserve', async d => { await api('/api/reservations', 'POST', d); toast('Reservation created.'); render(); }));
  },

  async rentals(v) {
    const [rows, lk] = await Promise.all([api('/api/rentals'), api('/api/lookups')]);
    const brOpts = id => lk.branches.map(b => `<option value="${b.id}" ${b.id === id ? 'selected' : ''}>${esc(b.name)}</option>`).join('');
    v.innerHTML = '<h1>Rentals</h1><h2>New walk-in rental</h2><div id="nf"></div><h2>All rentals</h2>' +
      table([...rentalCols, ['Return vehicle', r => ['Active', 'Overdue'].includes(r.status)
        ? `<span class="ret-box"><input type="number" class="km" min="${r.start_mileage}" value="${r.start_mileage}" title="End mileage"><select class="br">${brOpts(r.pickup_branch_id)}</select>` +
          `<button class="small green ret" data-id="${r.rental_id}">Return</button></span>` : '']], rows);
    v.onclick = async e => {
      const b = e.target.closest('.ret'); if (!b) return; const box = b.parentElement;
      try { const d = await api(`/api/rentals/${b.dataset.id}/return`, 'POST', { end_mileage: $('.km', box).value, return_branch_id: $('.br', box).value });
        toast(`Rental #${b.dataset.id} returned. ${d.remark}.`); render(); } catch (err) { toast(err.message, true); }
    };
    $('#nf').replaceWith(form([
      { label: 'Customer', name: 'customer_id', options: opts(lk.customers) }, { label: 'Vehicle (available)', name: 'vehicle_id', options: opts(lk.available) },
      { label: 'Due date & time', name: 'due_date', type: 'datetime-local' },
    ], 'Start rental', async d => { const r = await api('/api/rentals', 'POST', d); toast(`Rental #${r.id} created: ${r.days} day(s), total ${money(r.total)}`); render(); }));
  },

  async reports(v) {
    const defs = [['overdue', '1. Overdue rentals', 'JOIN rentals + customers + vehicles, LEFT JOIN late_fees', ['late_fees']],
      ['insurance', '2. Vehicles with no valid insurance', 'LEFT JOIN vehicles + insurance, IS NULL', []],
      ['revenue', '3. Revenue by pickup branch', 'payments JOIN rentals JOIN branches, GROUP BY', ['revenue']],
      ['categories', '4. Rentals per vehicle category', 'LEFT JOINs + GROUP BY', ['billed']],
      ['norentals', '5. Customers who have never rented', 'LEFT JOIN, IS NULL', []]];
    const data = await Promise.all(defs.map(d => api('/api/reports/' + d[0])));
    v.innerHTML = '<h1>Reports</h1>' + defs.map((d, i) => `<h2>${esc(d[1])} <small>(${esc(d[2])})</small></h2>` + (data[i].length ? plainTable(data[i], d[3]) : '<p>No records.</p>')).join('');
  },
};

// ---------- app shell / routing ----------
async function render() {
  const name = (location.hash.slice(1).split('?')[0]) || 'dashboard';
  document.querySelectorAll('nav a').forEach(a => a.classList.toggle('on', a.getAttribute('href') === '#' + name));
  const v = $('#view'); v.onclick = null;
  try { await (views[name] || views.dashboard)(v); }
  catch (e) { if (e.status === 401) return showAuth(); v.innerHTML = `<div class="flash err">${esc(e.message)}</div>`; }
}
function showShell(emp) { $('#auth').classList.add('hidden'); $('#shell').classList.remove('hidden'); $('#who').textContent = emp.name; render(); }
function showAuth() {
  $('#shell').classList.add('hidden'); $('#auth').classList.remove('hidden'); $('#loginBox').classList.remove('hidden'); $('#regBox').classList.add('hidden');
  $('#loginForm').replaceChildren(form([{ label: 'Username', name: 'username', attrs: 'autofocus' }, { label: 'Password', name: 'password', type: 'password' }], 'Log in',
    async d => showShell(await api('/api/login', 'POST', d))));
}
$('#showReg').onclick = () => {
  $('#loginBox').classList.add('hidden'); $('#regBox').classList.remove('hidden');
  $('#regForm').replaceChildren(form(customerFields(), 'Register', async (d, f) => {
    await api('/api/register', 'POST', d); f.reset();
    $('#regForm').prepend(el("<div class='flash'>Thank you! You're registered. Please visit our branch with your driver's license to rent a vehicle.</div>"));
  }));
};
$('#showLogin').onclick = showAuth;
$('#logout').onclick = async () => { await api('/api/logout', 'POST'); showAuth(); };
window.addEventListener('hashchange', () => !$('#shell').classList.contains('hidden') && render());
api('/api/me').then(showShell).catch(showAuth);
