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
function afDestinationImage(code){return '/static/images/'+({HAN:'hanoi',SGN:'saigon',DAD:'danang'}[code]||'danang')+'.webp';}
function afScene(route){
 if(!route)return '';
 return `<div class="af-flight-note"><span class="af-note-icon">${afIcon('plane')}</span><div><small>HÀNH TRÌNH GỢI Ý</small><strong>${esc(route.OriginCode)} <span>→</span> ${esc(route.DestinationCode)}</strong><p>${day(route.NextDeparture)} · 1 người lớn</p></div><span class="af-note-fare"><small>Từ · đã gồm thuế</small><b>${money(route.FromPrice)}</b></span></div>`;
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
