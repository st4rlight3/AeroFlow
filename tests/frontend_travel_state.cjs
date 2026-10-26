'use strict';
// Execute the shipped source with a small form DOM and controlled API promises.
// This verifies request/state transitions; browser layout and SQL are tested separately.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {test} = require('node:test');
const sourcePath = path.resolve(__dirname, '../app/static/travel.js');
const source = fs.readFileSync(sourcePath, 'utf8');
const decode = s => String(s ?? '').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const quote = (quantity = 1) => ({quote: {Units: 2, Quantity: quantity, Subtotal: quantity * 100, DiscountAmount: 0, Total: quantity * 100, RefundPercent: 50, CancelCutoffHours: 48, AvailableQuantity: 3}});

function harness({prefill = null, filters = {}, anonymous = false, secondUnit = 'NIGHT', slotCodes = ['AM', 'PM']} = {}) {
  let maps = {}, controls = [], requests = [], bookCalls = [], deferredAvailability = false;
  const stored = new Map(prefill ? [['aeroflow.travelSelection', JSON.stringify(prefill)]] : []);
  const messages = [];
  class Element {
    constructor(tag, attrs = '', content = '') {
      this.tag = tag; this.attrs = attrs; this.handlers = {}; this.field = {hidden: false}; this._html = content;
      for (const m of attrs.matchAll(/([\w-]+)="([^"]*)"/g)) this[m[1]] = decode(m[2]);
      this.name ||= ''; this.value ||= ''; this.disabled = /\bdisabled(?:\s|$)/.test(attrs); this.checked = /\bchecked(?:\s|$)/.test(attrs); this.textContent = '';
      if (tag === 'textarea') this.value = decode(content);
      if (tag === 'select') this.loadOptions(content);
    }
    addEventListener(event, fn) {(this.handlers[event] ??= []).push(fn);}
    closest() {return this.field;}
    querySelector() {return null;}
    insertAdjacentHTML(position, html) {this._html += html; parse(html);}
    set innerHTML(html) {this._html = html; if (this.id === 'main') {controls = []; maps = {main: this}; parse(html);} if (this.tag === 'select') this.loadOptions(html);}
    get innerHTML() {return this._html;}
    loadOptions(html) {const options = [...html.matchAll(/<option\b([^>]*)>/g)]; const selected = options.find(m => /\bselected(?:\s|$)/.test(m[1])) || options[0]; this.value = selected ? decode(/\bvalue="([^"]*)"/.exec(selected[1])?.[1] || '') : '';}
    async emit(event) {for (const fn of this.handlers[event] || []) await fn({currentTarget: this, preventDefault() {}}); if (this['on' + event]) await this['on' + event]({currentTarget: this, preventDefault() {}});}
  }
  function parse(html) {
    for (const m of html.matchAll(/<(form|input|select|button|textarea|div|label)\b([^>]*)(?:>([\s\S]*?)<\/\1>|\s*\/?>)/g)) {
      // Forms/divs can contain nested elements, which are parsed by the independent pass below.
      if (!['form', 'div', 'label'].includes(m[1])) continue;
      const id = /\bid="([^"]*)"/.exec(m[2])?.[1];
      if (id) maps[id] = new Element(m[1], m[2]);
    }
    for (const m of html.matchAll(/<(input|select|button|textarea)\b([^>]*)>(?:([\s\S]*?)<\/\1>)?/g)) {
      const el = new Element(m[1], m[2], m[3] || ''); controls.push(el); if (el.id) maps[el.id] = el;
    }
    if (html.includes('id="tv-book-form"')) {
      // The minimal DOM only needs the named radio group's value for the real source.
      maps['tv-book-form'] ||= new Element('form', 'id="tv-book-form"');
      maps['tv-book-form'].elements = {PackageID: {
        get value() {return controls.find(c => c.name === 'PackageID' && c.checked)?.value || '';},
        set value(value) {controls.filter(c => c.name === 'PackageID').forEach(c => {c.checked = c.value === String(value);});}
      }};
      for (const id of ['tv-end-field', 'tv-unit-label', 'tv-quote-result']) maps[id] ||= new Element('div', `id="${id}"`);
    }
  }
  maps.main = new Element('div', 'id="main"');
  const product = {ProductID: 1, Title: 'Test service', DestinationName: 'Hà Nội', CountryName: 'Việt Nam', IanaTimeZone: 'Asia/Ho_Chi_Minh', CategoryCode: 'hotels', CategoryName: 'Khách sạn', ImagePath: '/static/x', Description: 'Test', Summary: 'Test', ProviderName: 'Test'};
  const packages = [101, 102].map(PackageID => ({PackageID, UnitCode: PackageID === 102 ? secondUnit : 'NIGHT', UnitLabel: 'phòng / đêm', MaxGuests: 2, Name: 'Standard', Description: 'Test', NextDate: '2026-12-15'}));
  const slots = (prefix = '') => ({items: slotCodes.map(SlotCode => ({SlotCode: prefix + SlotCode, StartsAt: '2026-12-15T02:00:00Z', AvailableQuantity: 3, UnitPrice: 100}))});
  const ctx = {
    crypto, URLSearchParams, Map, Number, Math, Date, JSON, console, location: {hash: '#experience/1'},
    state: {user: anonymous ? null : {FullName: 'Test', Email: 'test@example.test', Phone: '0912345678'}},
    sessionStorage: {getItem: key => stored.get(key) || null, setItem: (key, value) => stored.set(key, value), removeItem: key => stored.delete(key)},
    badge: () => '', esc: s => String(s ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'),
    hour: s => s, money: s => String(s), page: (a, b, c) => c, empty: () => '', toast: message => messages.push(message), errorHTML: message => '<div class="form-error">' + message + '</div>',
    $: selector => maps[selector.slice(1)],
    $$: selector => selector === '[name="PackageID"]' ? controls.filter(c => c.name === 'PackageID') : selector.includes('tv-book-form input') ? controls.filter(c => ['input', 'select'].includes(c.tag)) : [],
    formData: () => Object.fromEntries(controls.filter(c => c.name && !c.disabled && (c.type !== 'radio' || c.checked)).map(c => [c.name, c.value])),
    bindForm: () => {throw new Error('Unexpected generic form binding in detail test');},
    api: async (url, method, data) => {
      if (url === '/travel/products/1') return {product, packages, amenities: [], reviews: []};
      if (url.includes('/availability?') && !deferredAvailability) return slots();
      if (url.includes('/availability?') || url === '/travel/quotes') return await new Promise((resolve, reject) => requests.push({url, data, resolve, reject}));
      if (url === '/travel/bookings') {bookCalls.push(data); return {booking: {BookingID: 1}};}
      if (url === '/travel/cart') return {};
      throw Error('Unexpected API ' + url);
    }
  };
  vm.createContext(ctx); vm.runInContext(source, ctx, {filename: sourcePath}); vm.runInContext('travelState.filters=' + JSON.stringify(filters), ctx);
  return {ctx, stored, messages, slots, requests, bookCalls, node: id => maps[id], init: () => vm.runInContext('travelDetail(1)', ctx), quote: () => maps['tv-quote'].onclick(), submit: () => maps['tv-book-form'].emit('submit'), deferSchedule: () => {deferredAvailability = true;}, setPackage: id => {maps['tv-book-form'].elements.PackageID.value = id; return controls.find(c => c.name === 'PackageID' && c.checked).emit('change');}};
}

test('saved choice restores slot, coupon, notes and contact without changing its dates', async () => {
  const saved = {PackageID: 101, StartDate: '2026-12-15', EndDate: '2026-12-17', SlotCode: 'PM', VoucherCode: 'HELLOTRIP', Notes: 'Flight AF123 <pickup>', ContactName: 'Nguyễn A', Quantity: 1, GuestCount: 2};
  const h = harness({prefill: saved}); await h.init();
  for (const [id, expected] of [['tv-slot', saved.SlotCode], ['tv-code', saved.VoucherCode], ['tv-notes', saved.Notes], ['tv-contact', saved.ContactName], ['tv-end', saved.EndDate]]) assert.equal(h.node(id).value, expected);
  assert.match(h.node('tv-code').attrs, /maxlength="30"/);
});

test('a saved slot that is no longer offered asks for a new choice instead of switching silently', async () => {
  const h = harness({slotCodes: ['AM'], prefill: {PackageID: 101, StartDate: '2026-12-15', EndDate: '2026-12-17', SlotCode: 'PM'}}); await h.init();
  assert.equal(h.node('tv-slot').value, ''); assert.equal(h.node('tv-quote').disabled, true); assert.match(h.messages.join(' '), /Khung giờ đã lưu không còn mở bán/);
  await h.quote(); assert.equal(h.requests.length, 0);
  h.node('tv-slot').value = 'AM'; await h.node('tv-slot').emit('input'); assert.equal(h.node('tv-quote').disabled, false);
  const pending = h.quote(); assert.equal(h.requests[0].data.SlotCode, 'AM'); h.requests[0].resolve(quote()); await pending; assert.equal(h.node('tv-book').disabled, false);
});

test('moving the start date preserves the current stay length, including a user-edited checkout', async () => {
  const h = harness({prefill: {PackageID: 101, StartDate: '2026-12-15', EndDate: '2026-12-17'}}); await h.init();
  h.node('tv-start').value = '2026-12-20'; await h.node('tv-start').emit('change'); assert.equal(h.node('tv-end').value, '2026-12-22'); assert.equal(h.node('tv-end').min, '2026-12-21');
  h.node('tv-end').value = '2026-12-25'; await h.node('tv-end').emit('input');
  h.node('tv-start').value = '2026-12-23'; await h.node('tv-start').emit('change'); assert.equal(h.node('tv-end').value, '2026-12-28');
});

test('search without a valid checkout receives a one-night checkout', async () => {
  const h = harness({filters: {StartDate: '2026-12-15', EndDate: '2026-12-15', Guests: 3}}); await h.init(); assert.equal(h.node('tv-end').value, '2026-12-16'); assert.equal(h.node('tv-quantity').value, '2');
});

test('a single-date package disables the hidden checkout instead of leaving a failing date constraint', async () => {
  const h = harness({secondUnit: 'PERSON'}); await h.init(); assert.equal(h.node('tv-end').required, true); assert.equal(h.node('tv-end').disabled, false);
  await h.setPackage(102); assert.equal(h.node('tv-end').disabled, true); assert.equal(h.node('tv-end').required, false); assert.equal(h.node('tv-end').min, '');
  await h.setPackage(101); assert.equal(h.node('tv-end').disabled, false); assert.equal(h.node('tv-end').value, '2026-12-16');
});

test('a quote arriving after quantity changed cannot enable booking or submit the stale amount', async () => {
  const h = harness(); await h.init(); const pending = h.quote();
  h.node('tv-quantity').value = '2'; await h.node('tv-quantity').emit('input'); h.requests[0].resolve(quote()); await pending;
  assert.equal(h.node('tv-book').disabled, true); assert.equal(h.node('tv-quote-result').innerHTML, ''); await h.submit(); assert.equal(h.bookCalls.length, 0); assert.equal(h.node('tv-book').disabled, true);
});

test('equal prices on different dates do not make an obsolete quote valid', async () => {
  const h = harness(); await h.init(); const pending = h.quote();
  h.node('tv-start').value = '2026-12-20'; await h.node('tv-start').emit('input'); await h.node('tv-start').emit('change'); h.requests[0].resolve(quote()); await pending;
  assert.equal(h.node('tv-book').disabled, true); await h.submit(); assert.equal(h.bookCalls.length, 0);
});

test('submit rechecks the actual selection even when a value changes without an input event', async () => {
  const h = harness(); await h.init(); const pending = h.quote(); h.requests[0].resolve(quote()); await pending; assert.equal(h.node('tv-book').disabled, false);
  h.node('tv-end').value = '2026-12-18'; await h.submit(); assert.equal(h.bookCalls.length, 0); assert.equal(h.node('tv-book').disabled, true);
});

test('an older availability response cannot replace the newly selected date or package', async () => {
  const h = harness(); await h.init(); h.deferSchedule();
  h.node('tv-start').value = '2026-12-20'; const old = h.node('tv-start').emit('change'); const latest = h.setPackage(102);
  h.requests[1].resolve(h.slots('NEW-')); await latest; assert.equal(h.node('tv-slot').value, 'NEW-AM');
  h.requests[0].resolve(h.slots('OLD-')); await old; assert.equal(h.node('tv-slot').value, 'NEW-AM'); assert.equal(h.node('tv-start').value, '2026-12-20'); assert.equal(h.node('tv-quote').disabled, false);
});

test('an older quote cannot unlock controls while the newer quote is still pending', async () => {
  const h = harness(); await h.init(); const first = h.quote(); h.node('tv-quantity').value = '2'; await h.node('tv-quantity').emit('input'); const second = h.quote();
  h.requests[0].resolve(quote()); await first; assert.equal(h.node('tv-quote').disabled, true); assert.equal(h.node('tv-book').disabled, true);
  h.requests[1].resolve(quote(2)); await second; assert.equal(h.node('tv-book').disabled, false); await h.submit(); assert.equal(h.bookCalls.length, 1); assert.equal(h.bookCalls[0].Quantity, 2); assert.equal(h.bookCalls[0].ExpectedTotal, 200);
});

test('login resume saves all customer fields and restores them for the same package', async () => {
  const h = harness({anonymous: true}); await h.init(); h.node('tv-slot').value = 'PM'; h.node('tv-code').value = 'helloTRIP'; h.node('tv-notes').value = 'Airport pickup AF123';
  const pending = h.quote(); h.requests[0].resolve(quote()); await pending; await h.submit();
  assert.equal(h.ctx.location.hash, 'login'); const saved = JSON.parse(h.stored.get('aeroflow.travelSelection')); assert.equal(saved.SlotCode, 'PM'); assert.equal(saved.VoucherCode, 'HELLOTRIP'); assert.equal(saved.Notes, 'Airport pickup AF123');
  const resumed = harness({prefill: saved}); await resumed.init(); assert.equal(resumed.node('tv-slot').value, 'PM'); assert.equal(resumed.node('tv-code').value, 'HELLOTRIP'); assert.equal(resumed.node('tv-notes').value, saved.Notes);
});
