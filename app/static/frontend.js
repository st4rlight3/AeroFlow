'use strict';

// Small local icon set: no font or remote JavaScript dependency.
function afIcon(name){
 const paths={
  plane:'<path d="m22 2-7 20-4-9-9-4Z"/><path d="m22 2-11 11"/>',
  arrow:'<path d="M4 12h16m-6-6 6 6-6 6"/>',
  search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  location:'<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/>',
  calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 2v6m10-6v6M3 11h18m-13 5h2m4 0h2"/>',
  ticket:'<path d="M3 7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v3a2 2 0 0 0 0 4v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-3a2 2 0 0 0 0-4Z"/><path d="M15 5v3m0 3v2m0 3v3"/>',
  shield:'<path d="m12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6Z"/><path d="m8 12 3 3 5-6"/>',
  seat:'<path d="M7 3v9a3 3 0 0 0 3 3h8m-1-7v7m-10 0-2 6m13-6 2 6M5 3h5v8H5Z"/>',
  spark:'<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5Z"/>',
  wallet:'<path d="M20 8V5a2 2 0 0 0-2-2H5a3 3 0 0 0 0 6h15v12H5a3 3 0 0 1-3-3V6"/><path d="M20 12h-5v5h5"/>',
  pause:'<path d="M8 5v14m8-14v14"/>',
  play:'<path d="m8 4 12 8-12 8Z"/>',
  check:'<path d="m5 12 4 4L19 6"/>',
  clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'
 };
 return `<svg class="af-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${paths[name]||paths.plane}</svg>`;
}
function afDestinationImage(code){
 const domestic={HAN:'hanoi',SGN:'saigon',DAD:'danang'};
 if(domestic[code])return '/static/images/'+domestic[code]+'.webp';
 if(['SIN','BKK','HKT','CNX','KUL','PEN','DPS','CGK','MNL','CEB','HKG','TPE','ICN','PUS','NRT','KIX','PEK','PVG','DEL','BOM','DXB','DOH','IST','CDG','LHR','FRA','SYD','MEL','LAX','SFO','JFK','YVR'].includes(code))return '/static/images/destinations/'+code+'.svg';
 return '/static/images/sky-panorama.svg';
}
function afDestinationExplorer(routes){
 const filters=[['WORLD','Quốc tế'],['VN','Việt Nam'],['ASIA','Châu Á'],['EUROPE','Châu Âu'],['OCEANIA','Châu Đại Dương'],['AMERICAS','Châu Mỹ'],['MIDDLE_EAST','Trung Đông']];
 return `<div class="af-destination-tabs" aria-label="Khu vực điểm đến">${filters.filter(([k])=>routes.some(r=>k==='WORLD'?r.DestinationCountryCode!=='VN':k==='VN'?r.DestinationCountryCode==='VN':r.DestinationRegion===k&&r.DestinationCountryCode!=='VN')).map(([k,v])=>`<button type="button" class="small ghost" data-region="${k}" aria-pressed="false">${v}</button>`).join('')}</div><p id="af-destination-count" class="muted"></p><div id="af-destinations" class="af-destination-grid"></div><div class="af-explore-more"><button type="button" class="ghost small" id="af-more-destinations" hidden>Xem thêm điểm đến</button></div>`;
}
function afBindDestinationExplorer(routes){
 let region=routes.some(r=>r.DestinationCountryCode!=='VN')?'WORLD':'VN',limit=6;
 const matches=r=>region==='WORLD'?r.DestinationCountryCode!=='VN':region==='VN'?r.DestinationCountryCode==='VN':r.DestinationRegion===region&&r.DestinationCountryCode!=='VN';
 function draw(){
  const items=routes.filter(matches);
  $('#af-destination-count').textContent=`${items.length} điểm đến · Giá cho 1 người lớn, đã bao gồm thuế`;
  $$('[data-region]').forEach(b=>{b.setAttribute('aria-pressed',String(b.dataset.region===region));b.classList.toggle('ghost',b.dataset.region!==region);});
  $('#af-destinations').innerHTML=items.slice(0,limit).map(x=>`<article class="af-destination"><div class="af-destination-visual"><img src="${afDestinationImage(x.DestinationCode)}" alt="Minh họa ${esc(x.DestinationCity)}" width="760" height="950" loading="lazy"><span class="af-destination-code">${esc(x.DestinationCode)} · ${esc(x.DestinationCountryName)}</span><h3>${esc(x.DestinationCity)}</h3></div><div class="af-destination-body"><div class="af-destination-route"><span>${esc(x.OriginCity)} ${afIcon('arrow')} ${esc(x.DestinationCity)}</span><span>${x.FlightCount} chuyến mở bán</span></div><div class="af-destination-price"><div><small>${day(x.NextDeparture,x.OriginTimeZone)} · 1 người lớn, gồm thuế</small><strong>${money(x.FromPrice)}</strong></div><button type="button" class="route-search" data-destination="${x.DestinationID}" aria-label="Tìm chuyến ${esc(x.OriginCity)} đến ${esc(x.DestinationCity)}">${afIcon('arrow')}</button></div></div></article>`).join('');
  $('#af-more-destinations').hidden=limit>=items.length;
  $$('#af-destinations .route-search').forEach(b=>b.onclick=()=>{const x=items.find(r=>r.DestinationID===Number(b.dataset.destination));state.search={origin:x.OriginID,destination:x.DestinationID,date:x.DepartureDate||dateInput(x.NextDeparture),passengers:1};sessionStorage.setItem('aeroflow.search',JSON.stringify(state.search));location.hash='results';});
 }
 $$('[data-region]').forEach(b=>b.onclick=()=>{region=b.dataset.region;limit=6;draw();});
 $('#af-more-destinations').onclick=()=>{limit+=6;draw();};draw();
}
function afSkyArt(){return `<span class="af-sky-art" aria-hidden="true"><svg viewBox="0 0 260 250" fill="none" focusable="false"><defs><radialGradient id="skyGlow"><stop stop-color="#c3ebe0"/><stop offset="1" stop-color="#eff9f2" stop-opacity="0"/></radialGradient><linearGradient id="skyGlobe" x1="50" y1="40" x2="200" y2="220" gradientUnits="userSpaceOnUse"><stop stop-color="#fafffc"/><stop offset="1" stop-color="#a9dbcf"/></linearGradient><linearGradient id="skyWing" x1="84" y1="79" x2="184" y2="147" gradientUnits="userSpaceOnUse"><stop stop-color="#fff"/><stop offset="1" stop-color="#d3ebe5"/></linearGradient></defs><circle cx="130" cy="126" r="122" fill="url(#skyGlow)"/><circle cx="128" cy="137" r="74" fill="url(#skyGlobe)" stroke="#80b9aa" stroke-width="1.2"/><ellipse cx="128" cy="137" rx="32" ry="74" stroke="#8fbfb2" stroke-width=".8"/><ellipse cx="128" cy="137" rx="74" ry="29" stroke="#8fbfb2" stroke-width=".8"/><path d="M55 137h146m-137-33h128M64 171h128m-64-108v148" stroke="#8fbfb2" stroke-width=".8"/><path d="m90 91 13 3 12 15-6 15-15 3-8 18-13-4-5-20 9-11Zm41 51 20-8 21 11-8 15-14 2-8 25-13-10-5-18Zm34-54 17 8 9 20-13 4-14-12Z" fill="#72ac97" fill-opacity=".32"/><ellipse cx="128" cy="137" rx="112" ry="40" transform="rotate(-30 128 137)" stroke="#4b9b86" stroke-dasharray="3 7" stroke-width="1.3"/><circle cx="39" cy="184" r="5" fill="#e4936c"/><circle cx="218" cy="94" r="4" fill="#087e68"/><g class="af-sky-plane"><path d="m66 96 68-7 43-43c6-6 12-8 16-4s1 11-4 16l-42 43-8 68-13 8-6-56-30 21-3 19-9 6-5-29-27-6 6-9 19-2 22-28-57-5Z" fill="url(#skyWing)" stroke="#348b76" stroke-width="1.6" stroke-linejoin="round"/><path d="m92 141 87-88m-46 39 14 9m-27 20 10-12" stroke="#459c86" stroke-width="1.3"/><path d="m171 55 7 6m-13 0 6 6" stroke="#14725f" stroke-width="3" stroke-linecap="round"/></g><path d="M210 201v12m-6-6h12M39 65v9m-4-5h8" stroke="#e5a076" stroke-width="1.8" stroke-linecap="round"/><circle cx="200" cy="36" r="3" fill="#8abfac"/></svg></span>`;}
function afScene(route){
 if(!route)return '';
 return `<div class="af-flight-note"><span class="af-note-icon">${afIcon('plane')}</span><div><small>HÀNH TRÌNH GỢI Ý</small><strong>${esc(route.OriginCode)} <span>→</span> ${esc(route.DestinationCode)}</strong><p>${day(route.NextDeparture)} · 1 người lớn</p></div><span class="af-note-fare"><small>Đã bao gồm thuế</small><b>${money(route.FromPrice)}</b></span></div>`;
}

function afDepartureHour(f){return Number(new Intl.DateTimeFormat('en-GB',{hour:'2-digit',hourCycle:'h23',timeZone:f.OriginTimeZone||'Asia/Ho_Chi_Minh'}).format(new Date(f.DepartureTime)));}
function afBasicFilters(items){return `<section class="card af-flight-filters"><div class="u-filters"><label>Hãng hàng không<select id="af-airline"><option value="">Tất cả hãng</option>${[...new Map(items.map(f=>[f.AirlineCode,f.AirlineName])).entries()].map(([k,v])=>`<option value="${esc(k)}">${esc(v)}</option>`).join('')}</select></label><label>Giá tối thiểu / người<input id="af-min-price" type="number" min="0" placeholder="Không giới hạn"></label><label>Giá tối đa / người<input id="af-max-price" type="number" min="0" placeholder="Không giới hạn"></label><label>Giờ khởi hành<select id="af-departure"><option value="">Cả ngày</option><option value="0">00:00 – 05:59</option><option value="6">06:00 – 11:59</option><option value="12">12:00 – 17:59</option><option value="18">18:00 – 23:59</option></select></label><label>Thời gian bay tối đa (giờ)<input id="af-duration" type="number" min="0.5" step="0.5" placeholder="Không giới hạn"></label><label>Sắp xếp<select id="af-sort"><option value="departure">Khởi hành sớm</option><option value="price">Giá thấp nhất</option><option value="duration">Bay nhanh nhất</option><option value="arrival">Đến sớm nhất</option></select></label></div><div class="section-head"><small id="af-filter-count" aria-live="polite"></small><button type="button" class="ghost small" id="af-reset-filters">Xóa bộ lọc</button></div></section>`;}
function afBasicCalendar(items){return `<div class="u-calendar" aria-label="Giá vé các ngày lân cận">${items.map(c=>`<button type="button" class="ghost small ${c.Date===state.search.date?'u-selected':''}" data-basic-date="${esc(c.Date)}"><span>${day(c.Date+'T12:00:00Z')}</span><strong>${money(c.FromPrice)}</strong><small>/ người lớn · gồm thuế</small></button>`).join('')}</div>`;}
function afBindBasicFilters(items){
 function draw(){const airline=$('#af-airline').value,min=Number($('#af-min-price').value),max=Number($('#af-max-price').value),part=$('#af-departure').value,duration=Number($('#af-duration').value),sort=$('#af-sort').value;
  const filtered=items.filter(f=>{const h=afDepartureHour(f);return (!airline||f.AirlineCode===airline)&&(!min||Number(f.FromPrice)>=min)&&(!max||Number(f.FromPrice)<=max)&&(part===''||(h>=Number(part)&&h<Number(part)+6))&&(!duration||(new Date(f.ArrivalTime)-new Date(f.DepartureTime))/3600000<=duration);}).sort((a,b)=>sort==='price'?Number(a.FromPrice)-Number(b.FromPrice):sort==='duration'?(new Date(a.ArrivalTime)-new Date(a.DepartureTime))-(new Date(b.ArrivalTime)-new Date(b.DepartureTime)):new Date(sort==='arrival'?a.ArrivalTime:a.DepartureTime)-new Date(sort==='arrival'?b.ArrivalTime:b.DepartureTime));
  $('#af-filter-count').textContent=`${filtered.length} / ${items.length} chuyến phù hợp · Bay thẳng · Giờ địa phương`;
  $('#af-flight-results').innerHTML=filtered.map(flightCard).join('')||empty('Chưa có chuyến phù hợp','Thử nới khoảng giá, thời gian hoặc chọn hãng khác.');
 }
 $$('.af-flight-filters select,.af-flight-filters input').forEach(el=>el.addEventListener('input',draw));
 $('#af-reset-filters').onclick=()=>{$$('.af-flight-filters input').forEach(el=>el.value='');$$('.af-flight-filters select').forEach(el=>el.selectedIndex=0);draw();};
 $$('[data-basic-date]').forEach(b=>b.onclick=async()=>{state.search.date=b.dataset.basicDate;sessionStorage.setItem('aeroflow.search',JSON.stringify(state.search));await results();});draw();
}

(function initAeroFlowVisuals(){
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 let paused=false;
 try{paused=localStorage.getItem('aeroflow.motion')==='off';}catch{}
 let observer=null,scheduled=false;
 const seen=new WeakSet();
 function motionOff(){return paused||reduced.matches;}
 function syncMotion(){
  document.documentElement.classList.toggle('af-motion-off',motionOff());
  const control=document.querySelector('#motion-toggle');
  if(control){control.innerHTML=afIcon(motionOff()?'play':'pause')+`<span>${motionOff()?'Bật chuyển động':'Tắt chuyển động'}</span>`;control.setAttribute('aria-pressed',String(!motionOff()));control.disabled=reduced.matches;control.title=reduced.matches?'Đang giảm chuyển động theo cài đặt thiết bị':'Tùy chọn hiệu ứng';}
  if(motionOff())document.querySelectorAll('.af-reveal-pending').forEach(el=>{el.classList.remove('af-reveal-pending');el.classList.add('af-revealed');observer?.unobserve(el);});
 }
 function decorate(){
  scheduled=false;
  const current=(location.hash.slice(1).split('/')[0]||'home');
  document.body.dataset.page=current;
  const groups={flight:'ultimate',results:'ultimate',seats:'ultimate',passengers:'ultimate',review:'ultimate','ultimate-passengers':'ultimate','ultimate-seats':'ultimate','ultimate-review':'ultimate',booking:'bookings',ticket:'bookings',exchange:'bookings',options:'bookings',operations:'admin',promotions:'admin'};
  document.querySelectorAll('.header nav a').forEach(a=>{const active=a.hash.slice(1)===(groups[current]||current);a.classList.toggle('active',active);if(active)a.setAttribute('aria-current','page');else a.removeAttribute('aria-current');});
  const candidates=document.querySelectorAll('#main .af-destination,#main .af-feature,#main .af-journey-banner,#main .flight,#main .fare-card,#main .u-option,#main .stat');
  let index=0;
  candidates.forEach(el=>{
   if(seen.has(el))return;seen.add(el);
   if(!observer||motionOff()||index>24)return;
   el.style.setProperty('--af-delay',Math.min(index++%4,3)*65+'ms');el.classList.add('af-reveal-pending');observer.observe(el);
  });
 }
 function schedule(){if(!scheduled){scheduled=true;requestAnimationFrame(decorate);}}
 function boot(){
  if('IntersectionObserver' in window){observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.remove('af-reveal-pending');entry.target.classList.add('af-revealed');observer.unobserve(entry.target);}}),{threshold:.06});}
  syncMotion();
  document.addEventListener('click',event=>{
   const link=event.target.closest('[data-journey-kind]');
   if(!link||!state.search)return;
   const first={OriginID:Number(state.search.origin),DestinationID:Number(state.search.destination),Date:state.search.date};
   uJourney.kind=link.dataset.journeyKind;uJourney.legs=[first,{OriginID:first.DestinationID,DestinationID:first.OriginID,Date:uDatePlus(first.Date,3)}];
   uJourney.results=[];uJourney.picks=[];uJourney.passengers=[];uJourney.selections=[];uJourney.quote=null;
  });
  document.querySelector('#motion-toggle')?.addEventListener('click',()=>{paused=!paused;try{localStorage.setItem('aeroflow.motion',paused?'off':'on');}catch{}syncMotion();});
  reduced.addEventListener('change',syncMotion);
  const main=document.querySelector('#main');
  new MutationObserver(records=>{
   for(const record of records)for(const node of record.removedNodes)if(node.nodeType===1){observer?.unobserve(node);node.querySelectorAll('.af-reveal-pending').forEach(el=>observer?.unobserve(el));}
   if(records.some(r=>[...r.addedNodes].some(n=>n.nodeType===1)))schedule();
  }).observe(main,{childList:true,subtree:true});
  window.addEventListener('hashchange',()=>{document.querySelector('#route-progress')?.classList.add('af-loading');});
  window.addEventListener('aeroflow:route-ready',()=>{document.querySelector('#route-progress')?.classList.remove('af-loading');schedule();});
  document.addEventListener('visibilitychange',()=>document.documentElement.classList.toggle('af-tab-hidden',document.hidden));
  document.querySelector('#back-top')?.addEventListener('click',()=>window.scrollTo({top:0,left:0,behavior:'instant'}));
  window.addEventListener('scroll',()=>{document.querySelector('.header')?.classList.toggle('af-scrolled',window.scrollY>16);},{passive:true});
  schedule();
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
