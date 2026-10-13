/* =========================================================
   عقارات السويداء — نموذج تفاعلي (Prototype)
   محاكاة منطق التطبيق: زائر / مستخدم / سمسار / إدارة
   ========================================================= */

// ---------- الحالة العامة ----------
const State = {
  role: 'visitor',          // visitor | user | broker | admin
  loggedIn: false,
  phone: '',
  tab: 'offers',            // offers | requests | appointments | profile
  offerCat: 'property',     // property | car
  offerDeal: 'sale',        // sale | rent
  reqCat: 'property',
  reqDeal: 'buy',           // buy | rent
  // قيود المستخدم العادي
  freeOfferUsed: false,
  myAppointments: [],       // حجوزات المستخدم (حد أقصى 5)
  favorites: new Set(),
  currentItem: null,
  bookingDay: null,
  bookingSlot: null,
};

const MAX_APPTS = 5;

// ---------- بيانات وهمية ----------
// مصدر العرض: admin | user | broker  → يحدد لمن يذهب الموعد
const IMG = {
  villa: 'https://images.unsplash.com/photo-1564013799919-ab600027ffc6?w=800',
};
function svgPhoto(label, c1, c2, emoji){
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='400' height='260'>
    <defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'>
    <stop offset='0' stop-color='${c1}'/><stop offset='1' stop-color='${c2}'/></linearGradient></defs>
    <rect width='400' height='260' fill='url(#g)'/>
    <text x='200' y='120' font-size='70' text-anchor='middle'>${emoji}</text>
    <text x='200' y='185' font-size='20' fill='rgba(255,255,255,.85)' text-anchor='middle' font-family='Cairo,sans-serif'>${label}</text>
  </svg>`;
  return 'data:image/svg+xml;utf8,' + encodeURIComponent(svg);
}

const OFFERS = [
  { id:1, cat:'property', deal:'sale', source:'admin', title:'فيلا حديثة - القرى الشرقية', area:'السويداء - القريا',
    price:'180,000$', img:svgPhoto('فيلا','#1f7a4d','#155f3a','🏡'),
    specs:[['🛏️','4 غرف'],['🛁','3 حمام'],['📐','320 م²']], desc:'فيلا مستقلة بتشطيب فاخر، حديقة أمامية وموقف سيارتين، إطلالة مفتوحة.', owner:'المكتب', phone:'0999000111' },
  { id:2, cat:'property', deal:'rent', source:'broker', broker:'سمسار: أبو فادي', title:'شقة مفروشة - وسط المدينة', area:'السويداء - الحي الغربي',
    price:'250$ / شهر', img:svgPhoto('شقة','#2563eb','#1e40af','🏢'),
    specs:[['🛏️','3 غرف'],['🛋️','مفروشة'],['📐','140 م²']], desc:'شقة مفروشة بالكامل بالقرب من الأسواق، طابق ثالث مع مصعد.', owner:'سمسار', phone:'0988222333' },
  { id:3, cat:'property', deal:'sale', source:'user', title:'أرض سكنية - شهبا', area:'السويداء - شهبا',
    price:'45,000$', img:svgPhoto('أرض','#c9a227','#a07f15','🌳'),
    specs:[['📐','500 م²'],['📄','طابو أخضر'],['🛣️','على شارعين']], desc:'أرض سكنية منظمة، صك أخضر، مناسبة للبناء الفوري.', owner:'عرض مستخدم', phone:'0955444555' },
  { id:4, cat:'car', deal:'sale', source:'admin', title:'هيونداي سوناتا 2019', area:'السويداء',
    price:'18,500$', img:svgPhoto('سيارة','#374151','#111827','🚗'),
    specs:[['⛽','بنزين'],['⚙️','أوتوماتيك'],['🛣️','90,000 كم']], desc:'سيارة بحالة ممتازة، فحص كامل، لون فضي، صيانة دورية.', owner:'المكتب', phone:'0999000111' },
  { id:5, cat:'car', deal:'rent', source:'broker', broker:'سمسار: سامر', title:'كيا سبورتاج 2021 - للإيجار', area:'السويداء',
    price:'35$ / يوم', img:svgPhoto('سيارة','#7c3aed','#5b21b6','🚙'),
    specs:[['⛽','بنزين'],['⚙️','أوتوماتيك'],['👥','5 ركاب']], desc:'سيارة دفع رباعي للإيجار اليومي/الأسبوعي مع أو بدون سائق.', owner:'سمسار', phone:'0988222333' },
  { id:6, cat:'property', deal:'sale', source:'admin', title:'محل تجاري - السوق الرئيسي', area:'السويداء - المركز',
    price:'95,000$', img:svgPhoto('محل تجاري','#0e7490','#155e75','🏪'),
    specs:[['📐','60 م²'],['🚪','واجهة 5م'],['🏬','أرضي']], desc:'محل تجاري بموقع حيوي، واجهة زجاجية، مناسب لكل النشاطات.', owner:'المكتب', phone:'0999000111' },
];

const REQUESTS = [
  { id:101, cat:'property', deal:'buy', name:'زبون', phone:'09xx', title:'مطلوب: شقة للشراء', district:'الحي الشرقي',
    budget:'حتى 60,000$', status:'pending', notes:'3 غرف، طابق غير أرضي، تشطيب جيد.' },
  { id:102, cat:'property', deal:'rent', name:'زبون', phone:'09xx', title:'مطلوب: منزل للإيجار', district:'القريا',
    budget:'حتى 200$/شهر', status:'matched', notes:'عائلة صغيرة، يفضّل قرب المدارس.' },
  { id:103, cat:'car', deal:'buy', name:'زبون', phone:'09xx', title:'مطلوب: سيارة عائلية', district:'السويداء',
    budget:'حتى 12,000$', status:'pending', notes:'موديل 2015 فما فوق، أوتوماتيك.' },
];

// ---------- أدوات مساعدة ----------
const $ = (s, r=document) => r.querySelector(s);
const $$ = (s, r=document) => [...r.querySelectorAll(s)];
const screen = $('#screen');

function toast(msg){
  const t = $('#toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(t._t); t._t = setTimeout(()=>t.classList.remove('show'), 2200);
}

function dealLabel(cat, deal){
  if(deal==='sale') return 'بيع';
  if(deal==='rent') return 'إيجار';
  if(deal==='buy')  return cat==='car'?'شراء':'شراء';
  return deal;
}

// أين يذهب الموعد؟ (المنطق الأساسي اللي اتفقنا عليه)
function appointmentRoute(source){
  return source==='broker'
    ? { to:'broker', label:'بانتظار موافقة السمسار' }
    : { to:'admin',  label:'بانتظار تأكيد الإدارة' };
}

// ---------- التنقّل بين الشاشات ----------
function go(view){
  $$('.view').forEach(v=>v.classList.remove('active'));
  const el = $('#view-'+view);
  if(el){ el.classList.add('active'); screen.scrollTop = 0; }
}

// ============================================================
//  بناء الشاشات
// ============================================================
function render(){
  screen.innerHTML = '';
  screen.appendChild(buildMain());
  screen.appendChild(buildDetails());
  screen.appendChild(buildLogin());
  bindMain();
  // العودة للتبويب الحالي
  switchTab(State.tab, true);
}

// ---------- الشاشة الرئيسية (تتضمن التبويبات السفلية) ----------
function buildMain(){
  const v = document.createElement('div');
  v.className = 'view active'; v.id = 'view-main';
  v.innerHTML = `
    <div class="appbar">
      <div class="row">
        <div class="brand">
          <div class="logo">🏛️</div>
          <div><b>عقارات السويداء</b><span>مكتبك العقاري الإلكتروني</span></div>
        </div>
        <button class="iconbtn" id="bellBtn">🔔<span class="badge">2</span></button>
      </div>
      <div class="search" id="searchBar">
        🔍 <input placeholder="ابحث عن عقار، سيارة، منطقة..." />
      </div>
    </div>

    <div id="tab-offers" class="tabpane"></div>
    <div id="tab-requests" class="tabpane" style="display:none"></div>
    <div id="tab-appointments" class="tabpane" style="display:none"></div>
    <div id="tab-profile" class="tabpane" style="display:none"></div>

    <div class="bottomnav">
      <button data-tab="offers" class="active"><span class="ic">🏠</span>العروض</button>
      <button data-tab="requests"><span class="ic">📋</span>الطلبات</button>
      <button data-tab="add" class="fab"><span class="ic">＋</span></button>
      <button data-tab="appointments"><span class="ic">📅</span>مواعيدي</button>
      <button data-tab="profile"><span class="ic">👤</span>حسابي</button>
    </div>
  `;
  return v;
}

// ---------- تبويب العروض ----------
function renderOffers(){
  const pane = $('#tab-offers');
  const items = OFFERS.filter(o=>o.cat===State.offerCat && o.deal===State.offerDeal);
  pane.innerHTML = `
    <div class="seg">
      <button data-ocat="property" class="${State.offerCat==='property'?'active':''}">🏢 عقارات</button>
      <button data-ocat="car" class="${State.offerCat==='car'?'active':''}">🚗 سيارات</button>
    </div>
    <div class="subseg">
      <button class="chip ${State.offerDeal==='sale'?'active':''}" data-odeal="sale">🏷️ بيع</button>
      <button class="chip ${State.offerDeal==='rent'?'active':''}" data-odeal="rent">🔑 إيجار</button>
    </div>
    <div class="secthead"><h2>${items.length} عرض متاح</h2><a>الأحدث ▾</a></div>
    <div class="list">
      ${items.map(offerCard).join('') || emptyHtml('لا توجد عروض في هذا التصنيف بعد')}
    </div>
  `;
  // bind
  $$('[data-ocat]', pane).forEach(b=>b.onclick=()=>{State.offerCat=b.dataset.ocat; renderOffers();});
  $$('[data-odeal]', pane).forEach(b=>b.onclick=()=>{State.offerDeal=b.dataset.odeal; renderOffers();});
  $$('.card', pane).forEach(c=>c.onclick=()=>openDetails(+c.dataset.id));
}

function offerCard(o){
  const tagCls = o.deal==='sale'?'sale':'rent';
  const srcBadge = o.source==='broker' ? `<span class="tag broker l">${o.broker||'سمسار'}</span>`
                  : o.source==='user'  ? `<span class="tag gold l">عرض مستخدم</span>` : '';
  return `
  <div class="card" data-id="${o.id}">
    <div class="photo" style="background-image:url('${o.img}')">
      <div class="ov"></div>
      <span class="tag ${tagCls} r">${dealLabel(o.cat,o.deal)}</span>
      ${srcBadge}
      <div class="price">${o.price}</div>
    </div>
    <div class="body">
      <h3>${o.title}</h3>
      <div class="meta">📍 ${o.area}</div>
      <div class="specs">${o.specs.map(s=>`<span class="spec">${s[0]} ${s[1]}</span>`).join('')}</div>
      <div class="foot">
        <span class="src">${o.source==='admin'?'🏛️ المكتب':o.source==='broker'?'🤝 سمسار':'👤 مستخدم'}</span>
        <button class="btn ghost" onclick="event.stopPropagation(); quickBook(${o.id})">📅 حجز موعد</button>
      </div>
    </div>
  </div>`;
}

// ---------- تبويب الطلبات ----------
function renderRequests(){
  const pane = $('#tab-requests');
  const items = REQUESTS.filter(r=>r.cat===State.reqCat && r.deal===State.reqDeal);
  pane.innerHTML = `
    <div class="seg">
      <button data-rcat="property" class="${State.reqCat==='property'?'active':''}">🏢 عقارات</button>
      <button data-rcat="car" class="${State.reqCat==='car'?'active':''}">🚗 سيارات</button>
    </div>
    <div class="subseg">
      <button class="chip ${State.reqDeal==='buy'?'active':''}" data-rdeal="buy">🛒 ${State.reqCat==='car'?'شراء':'شراء'}</button>
      <button class="chip ${State.reqDeal==='rent'?'active':''}" data-rdeal="rent">🔑 استئجار</button>
    </div>
    <div class="banner"><span class="ic">💡</span><div>الطلبات يضعها الباحثون عن عقار/سيارة. إذا كان لديك ما يطابق طلباً، تواصل مع المكتب.</div></div>
    <div class="list">
      ${items.map(reqCard).join('') || emptyHtml('لا توجد طلبات في هذا التصنيف بعد')}
    </div>
  `;
  $$('[data-rcat]', pane).forEach(b=>b.onclick=()=>{State.reqCat=b.dataset.rcat; renderRequests();});
  $$('[data-rdeal]', pane).forEach(b=>b.onclick=()=>{State.reqDeal=b.dataset.rdeal; renderRequests();});
}

function reqCard(r){
  const statusMap = {pending:['قيد الانتظار','gold'], matched:['تمت المطابقة','green'], completed:['مكتمل','blue'], cancelled:['ملغى','gray']};
  const [st,cls] = statusMap[r.status]||['',''];
  return `
  <div class="rcard">
    <div class="top">
      <b style="font-size:14.5px">${r.title}</b>
      <span class="pill ${cls}">${st}</span>
    </div>
    <div class="meta" style="color:var(--muted);font-size:12.5px;margin-bottom:8px">📍 ${r.district} &nbsp;•&nbsp; 💰 ${r.budget}</div>
    <p style="margin:0 0 10px;font-size:13px;color:#444">${r.notes}</p>
    <div style="display:flex;gap:8px">
      <span class="pill ${r.deal==='buy'?'blue':'purple'}">${dealLabel(r.cat,r.deal)}</span>
      <span class="pill gray">${r.cat==='property'?'عقار':'سيارة'}</span>
    </div>
  </div>`;
}

// ---------- تبويب المواعيد ----------
function renderAppointments(){
  const pane = $('#tab-appointments');
  if(!State.loggedIn){
    pane.innerHTML = lockedHtml('سجّل دخولك لعرض وإدارة مواعيدك');
    bindLockBtn(pane); return;
  }
  const a = State.myAppointments;
  pane.innerHTML = `
    <div class="quota">
      <div style="display:flex;justify-content:space-between;font-size:13px;font-weight:700">
        <span>📅 مواعيدك المحجوزة</span><span>${a.length} / ${MAX_APPTS}</span>
      </div>
      <div class="bar"><i style="width:${(a.length/MAX_APPTS)*100}%"></i></div>
    </div>
    <div class="list" style="padding-top:0">
      ${a.length? a.map(apptItem).join('') : emptyHtml('لا توجد مواعيد محجوزة. اضغط «حجز موعد» على أي عرض.')}
    </div>
  `;
}

function apptItem(a){
  const r = appointmentRoute(a.source);
  return `
  <div class="appt">
    <div class="when"><b>${a.day}</b><span>${a.month}</span></div>
    <div class="info">
      <h4>${a.title}</h4>
      <div class="m">🕐 ${a.slot} &nbsp;•&nbsp; 📍 ${a.area}</div>
      <div style="margin-top:7px"><span class="pill ${r.to==='broker'?'purple':'gold'}">${r.label}</span></div>
    </div>
  </div>`;
}

// ---------- تبويب الحساب ----------
function renderProfile(){
  const pane = $('#tab-profile');
  if(!State.loggedIn){
    pane.innerHTML = lockedHtml('سجّل دخولك للوصول لحسابك ورفع عرضك المجاني');
    bindLockBtn(pane); return;
  }
  pane.innerHTML = `
    <div style="background:linear-gradient(135deg,var(--green),var(--green-d));padding:24px 16px;color:#fff;text-align:center">
      <div class="avatar" style="width:72px;height:72px;font-size:32px;margin:0 auto 10px;background:rgba(255,255,255,.2);color:#fff">👤</div>
      <b style="font-size:17px">مستخدم عقارات السويداء</b>
      <div style="opacity:.85;font-size:13px;margin-top:3px;direction:ltr">${State.phone||'09xxxxxxxx'}</div>
    </div>
    <div class="list" style="padding-top:14px">
      <div class="quota">
        <div style="display:flex;justify-content:space-between;font-size:13px;font-weight:700">
          <span>🎁 عرضك المجاني</span>
          <span class="pill ${State.freeOfferUsed?'gray':'green'}">${State.freeOfferUsed?'مُستخدم':'متاح'}</span>
        </div>
        <p style="margin:8px 0 0;font-size:12.5px;color:var(--muted)">يمكنك نشر عرض واحد مجاناً. للمزيد تواصل مع المكتب للاشتراك.</p>
      </div>
      <div class="menu-item" onclick="openSheet('addOffer')"><div class="mi">➕</div><div><b>رفع عرض جديد</b><br><small>عقار أو سيارة</small></div><span class="ar">‹</span></div>
      <div class="menu-item" onclick="switchTab('appointments')"><div class="mi">📅</div><div><b>مواعيدي</b><br><small>${State.myAppointments.length} موعد</small></div><span class="ar">‹</span></div>
      <div class="menu-item" onclick="toast('قائمة المفضلة — قريباً')"><div class="mi">❤️</div><div><b>المفضلة</b><br><small>${State.favorites.size} عنصر</small></div><span class="ar">‹</span></div>
      <div class="menu-item" onclick="toast('الإعدادات والإشعارات — نموذج')"><div class="mi">⚙️</div><div><b>الإعدادات</b><br><small>الإشعارات، اللغة، الخصوصية</small></div><span class="ar">‹</span></div>
      <div class="menu-item" onclick="logout()"><div class="mi" style="background:#fde8e8;color:var(--danger)">↩</div><div><b style="color:var(--danger)">تسجيل الخروج</b></div></div>
    </div>
  `;
}

// ---------- عناصر مشتركة ----------
function emptyHtml(msg){
  return `<div class="empty"><div class="ic">📭</div><h3>لا يوجد محتوى</h3><p>${msg}</p></div>`;
}
function lockedHtml(msg){
  return `<div class="empty"><div class="ic">🔒</div><h3>تسجيل الدخول مطلوب</h3><p>${msg}</p>
    <button class="btn primary lg" style="margin-top:18px;padding-inline:30px" id="lockLoginBtn">تسجيل الدخول</button></div>`;
}
function bindLockBtn(pane){ const b=$('#lockLoginBtn',pane); if(b) b.onclick=()=>openLogin(); }

// ============================================================
//  شاشة التفاصيل
// ============================================================
function buildDetails(){
  const v = document.createElement('div');
  v.className='view'; v.id='view-details';
  v.innerHTML = `<div id="detContent"></div>`;
  return v;
}
function openDetails(id){
  const o = OFFERS.find(x=>x.id===id); if(!o) return;
  State.currentItem = o;
  const fav = State.favorites.has(id);
  $('#detContent').innerHTML = `
    <div class="det-hero" style="background-image:url('${o.img}')">
      <button class="det-back" onclick="go('main')">→</button>
      <button class="det-fav" onclick="toggleFav(${id},this)">${fav?'❤️':'🤍'}</button>
      <div class="det-dots"><i class="on"></i><i></i><i></i></div>
    </div>
    <div class="det-body">
      <div style="display:flex;gap:8px;margin-bottom:6px">
        <span class="pill ${o.deal==='sale'?'green':'blue'}">${dealLabel(o.cat,o.deal)}</span>
        <span class="pill gray">${o.cat==='property'?'عقار':'سيارة'}</span>
        ${o.source==='broker'?'<span class="pill purple">'+(o.broker||'سمسار')+'</span>':o.source==='user'?'<span class="pill gold">عرض مستخدم</span>':'<span class="pill green">المكتب</span>'}
      </div>
      <div class="det-price">${o.price}</div>
      <div class="det-title">${o.title}</div>
      <div class="meta" style="color:var(--muted)">📍 ${o.area}</div>
      <div class="specgrid">
        ${o.specs.map(s=>`<div class="specbox"><div class="si">${s[0]}</div><div><b>${s[1]}</b><span>تفاصيل</span></div></div>`).join('')}
      </div>
      <div class="panel"><h4>الوصف</h4><p>${o.desc}</p></div>
      <div class="panel"><h4>الناشر</h4>
        <div class="owner"><div class="avatar">${o.source==='admin'?'🏛️':'👤'}</div>
          <div><b>${o.owner}</b><br><small style="color:var(--muted)">${o.source==='broker'?'يتم الحجز بموافقة السمسار':'يتم الحجز عبر المكتب'}</small></div>
        </div>
      </div>
    </div>
    <div class="actionbar">
      <button class="btn ghost" onclick="callOwner()">📞 اتصال</button>
      <button class="btn primary" onclick="quickBook(${id})">📅 حجز موعد معاينة</button>
    </div>
  `;
  go('details');
}
function toggleFav(id, btn){
  if(!requireLogin()) return;
  if(State.favorites.has(id)){State.favorites.delete(id); btn.textContent='🤍';}
  else {State.favorites.add(id); btn.textContent='❤️'; toast('تمت الإضافة للمفضلة');}
}
function callOwner(){
  if(!requireLogin()) return;
  toast('📞 جاري الاتصال... (نموذج)');
}

// ============================================================
//  شاشة تسجيل الدخول (OTP)
// ============================================================
function buildLogin(){
  const v = document.createElement('div');
  v.className='view'; v.id='view-login';
  v.innerHTML = `
    <div class="login-wrap">
      <button class="iconbtn" style="align-self:flex-start" onclick="go('main')">→</button>
      <div class="logo-big">🏛️</div>
      <h2 style="text-align:center;margin:0">عقارات السويداء</h2>
      <p style="text-align:center;opacity:.85;margin:6px 0 0">سجّل دخولك للتفاعل مع التطبيق</p>

      <div class="login-card" id="loginStep1">
        <div class="field">
          <label>رقم الموبايل</label>
          <input id="phoneInput" type="tel" inputmode="numeric" placeholder="09xx xxx xxx" dir="ltr" />
        </div>
        <button class="btn primary block lg" onclick="sendOtp()">إرسال رمز التحقق</button>
        <p style="text-align:center;color:var(--muted);font-size:11.5px;margin:14px 0 0">سيصلك رمز تحقق عبر رسالة قصيرة / واتساب</p>
      </div>

      <div class="login-card" id="loginStep2" style="display:none">
        <b style="font-size:15px">أدخل رمز التحقق</b>
        <p style="color:var(--muted);font-size:12.5px;margin:4px 0 0">أُرسل إلى <span id="otpPhone" dir="ltr"></span></p>
        <div class="otp-boxes">
          <input maxlength="1" inputmode="numeric"/><input maxlength="1" inputmode="numeric"/>
          <input maxlength="1" inputmode="numeric"/><input maxlength="1" inputmode="numeric"/>
        </div>
        <button class="btn primary block lg" onclick="verifyOtp()">تأكيد وتفعيل الحساب</button>
        <p style="text-align:center;color:var(--green);font-size:12.5px;margin:14px 0 0;font-weight:700">إعادة إرسال الرمز (0:59)</p>
        <p style="text-align:center;color:var(--muted);font-size:11px;margin:8px 0 0">رمز تجريبي: أي 4 أرقام</p>
      </div>
    </div>
  `;
  return v;
}
function openLogin(){ $('#loginStep1').style.display='block'; $('#loginStep2').style.display='none'; go('login'); }
function sendOtp(){
  const p = $('#phoneInput').value.trim();
  if(p.length < 6){ toast('أدخل رقم موبايل صحيح'); return; }
  State.phone = p;
  $('#otpPhone').textContent = p;
  $('#loginStep1').style.display='none'; $('#loginStep2').style.display='block';
  // auto-focus otp
  const boxes = $$('.otp-boxes input');
  boxes.forEach((b,i)=>{ b.value=''; b.oninput=()=>{ if(b.value && boxes[i+1]) boxes[i+1].focus(); }; });
  boxes[0].focus();
  toast('تم إرسال الرمز (نموذج)');
}
function verifyOtp(){
  const code = $$('.otp-boxes input').map(b=>b.value).join('');
  if(code.replace(/\D/g,'').length < 4){ toast('أدخل رمز التحقق كاملاً'); return; }
  State.loggedIn = true;
  if(State.role==='visitor') setRole('user');
  toast('✅ تم تفعيل حسابك بنجاح');
  go('main');
  switchTab('profile');
}
function requireLogin(){
  if(State.loggedIn) return true;
  openSheet('loginPrompt');
  return false;
}
function logout(){
  State.loggedIn=false; State.phone=''; State.myAppointments=[]; State.freeOfferUsed=false;
  setRole('visitor'); switchTab('offers'); toast('تم تسجيل الخروج');
}

// ============================================================
//  حجز موعد (Sheet)
// ============================================================
function quickBook(id){
  if(!requireLogin()) return;
  if(State.myAppointments.length >= MAX_APPTS){
    openSheet('quotaFull'); return;
  }
  State.currentItem = OFFERS.find(x=>x.id===id);
  State.bookingDay=null; State.bookingSlot=null;
  openSheet('booking');
}

// ============================================================
//  نظام الـ Sheets (نوافذ منبثقة)
// ============================================================
function openSheet(type){
  closeSheet();
  const ov = document.createElement('div');
  ov.className='overlay active'; ov.id='overlay';
  ov.onclick = e=>{ if(e.target===ov) closeSheet(); };
  ov.innerHTML = `<div class="sheet">${sheetContent(type)}</div>`;
  $('.phone .screen').appendChild(ov);
  if(type==='booking') bindBooking();
}
function closeSheet(){ const o=$('#overlay'); if(o) o.remove(); }

function sheetContent(type){
  if(type==='loginPrompt'){
    return `<div class="grab"></div>
      <div style="text-align:center;padding:6px 0 4px">
        <div style="font-size:48px">🔒</div>
        <h3>سجّل دخولك أولاً</h3>
        <p class="sub">للتفاعل مع التطبيق (الحجز، المفضلة، رفع عرض) تحتاج لتفعيل رقم موبايلك.</p>
        <button class="btn primary block lg" onclick="closeSheet();openLogin()">تسجيل الدخول الآن</button>
        <button class="btn ghost block" style="margin-top:8px" onclick="closeSheet()">لاحقاً</button>
      </div>`;
  }
  if(type==='quotaFull'){
    return `<div class="grab"></div>
      <div style="text-align:center;padding:6px 0">
        <div style="font-size:48px">📅</div>
        <h3>وصلت للحد الأقصى</h3>
        <p class="sub">يمكن للمستخدم حجز ${MAX_APPTS} مواعيد كحد أقصى. ألغِ موعداً قائماً أو تواصل مع المكتب.</p>
        <button class="btn primary block lg" onclick="closeSheet();switchTab('appointments')">عرض مواعيدي</button>
      </div>`;
  }
  if(type==='booking'){
    const o = State.currentItem;
    const r = appointmentRoute(o.source);
    const days = nextDays(6);
    const slots = ['10:00 ص','11:30 ص','1:00 م','3:00 م','4:30 م','6:00 م'];
    return `<div class="grab"></div>
      <h3>حجز موعد معاينة</h3>
      <p class="sub">${o.title}</p>
      <div class="banner" style="margin:0 0 16px"><span class="ic">${r.to==='broker'?'🤝':'🏛️'}</span>
        <div>${r.to==='broker'?'هذا العرض من سمسار — سيُرسل طلب الموعد للسمسار للموافقة.':'سيُرسل طلب الموعد إلى إدارة المكتب للتأكيد.'}</div></div>
      <div class="field"><label>اختر اليوم</label>
        <div class="days" id="dayPick">${days.map((d,i)=>`<div class="day" data-day="${d.day}" data-month="${d.month}"><b>${d.day}</b><span>${d.dow}</span></div>`).join('')}</div>
      </div>
      <div class="field"><label>اختر الوقت</label>
        <div class="slots" id="slotPick">${slots.map(s=>`<div class="slot" data-slot="${s}">${s}</div>`).join('')}</div>
      </div>
      <div class="field"><label>ملاحظات (اختياري)</label>
        <textarea rows="2" placeholder="مثال: أفضّل معاينة بعد الظهر"></textarea></div>
      <button class="btn primary block lg" onclick="confirmBooking()">تأكيد الحجز</button>`;
  }
  if(type==='addOffer'){
    if(State.freeOfferUsed){
      return `<div class="grab"></div>
        <div style="text-align:center;padding:6px 0">
          <div style="font-size:48px">🎁</div>
          <h3>استخدمت عرضك المجاني</h3>
          <p class="sub">لقد نشرت عرضك المجاني. للمزيد من العروض اشترك أو تواصل مع المكتب.</p>
          <button class="btn gold block lg" onclick="toast('التواصل مع المكتب — نموذج');closeSheet()">التواصل للاشتراك</button>
        </div>`;
    }
    return `<div class="grab"></div>
      <h3>رفع عرض جديد</h3>
      <p class="sub">عرضك المجاني الوحيد — سيُراجَع من الإدارة قبل النشر.</p>
      <div class="row2">
        <div class="field"><label>النوع</label><select id="ofCat"><option value="property">عقار</option><option value="car">سيارة</option></select></div>
        <div class="field"><label>الغرض</label><select id="ofDeal"><option value="sale">بيع</option><option value="rent">إيجار</option></select></div>
      </div>
      <div class="field"><label>العنوان</label><input id="ofTitle" placeholder="مثال: شقة للبيع - السويداء"/></div>
      <div class="row2">
        <div class="field"><label>السعر</label><input id="ofPrice" placeholder="السعر"/></div>
        <div class="field"><label>العملة</label><select><option>$</option><option>ل.س</option></select></div>
      </div>
      <div class="field"><label>المنطقة</label><input placeholder="المحافظة - الحي"/></div>
      <div class="field"><label>الوصف</label><textarea rows="3" placeholder="اكتب وصفاً..."></textarea></div>
      <div class="field"><label>الصور</label>
        <div style="border:1.5px dashed var(--line);border-radius:12px;padding:22px;text-align:center;color:var(--muted)">📷 اضغط لإضافة صور</div></div>
      <button class="btn primary block lg" onclick="submitOffer()">إرسال للمراجعة</button>`;
  }
  if(type==='notif'){
    return `<div class="grab"></div>
      <h3>الإشعارات</h3>
      <div class="appt" style="margin-top:12px"><div class="when" style="background:#fde8e8;color:var(--danger)"><b>!</b></div>
        <div class="info"><h4>تم تأكيد موعدك</h4><div class="m">وافق المكتب على موعد معاينة «فيلا حديثة».</div></div></div>
      <div class="appt" style="margin-top:10px"><div class="when"><b>🤝</b></div>
        <div class="info"><h4>رد السمسار</h4><div class="m">وافق السمسار على موعدك للشقة المفروشة.</div></div></div>`;
  }
  return '';
}

function bindBooking(){
  $$('#dayPick .day').forEach(d=>d.onclick=()=>{
    $$('#dayPick .day').forEach(x=>x.classList.remove('active')); d.classList.add('active');
    State.bookingDay={day:d.dataset.day,month:d.dataset.month};
  });
  $$('#slotPick .slot').forEach(s=>s.onclick=()=>{
    $$('#slotPick .slot').forEach(x=>x.classList.remove('active')); s.classList.add('active');
    State.bookingSlot=s.dataset.slot;
  });
}
function confirmBooking(){
  if(!State.bookingDay || !State.bookingSlot){ toast('اختر اليوم والوقت'); return; }
  const o = State.currentItem;
  State.myAppointments.push({
    title:o.title, area:o.area, source:o.source,
    day:State.bookingDay.day, month:State.bookingDay.month, slot:State.bookingSlot
  });
  const r = appointmentRoute(o.source);
  closeSheet();
  toast('✅ تم إرسال الطلب — '+r.label);
  switchTab('appointments');
}
function submitOffer(){
  const t = $('#ofTitle').value.trim();
  if(!t){ toast('أدخل عنوان العرض'); return; }
  State.freeOfferUsed=true; closeSheet();
  toast('✅ أُرسل عرضك للمراجعة من الإدارة');
  switchTab('profile');
}

// ============================================================
//  أدوات التاريخ
// ============================================================
function nextDays(n){
  const dows=['أحد','إثنين','ثلاثاء','أربعاء','خميس','جمعة','سبت'];
  const months=['ينا','فبر','مار','أبر','ماي','يون','يول','أغس','سبت','أكت','نوف','ديس'];
  const out=[]; const now=new Date();
  for(let i=1;i<=n;i++){ const d=new Date(now); d.setDate(now.getDate()+i);
    out.push({day:d.getDate(), dow:dows[d.getDay()], month:months[d.getMonth()]}); }
  return out;
}

// ============================================================
//  التبويبات السفلية
// ============================================================
function switchTab(tab, silent){
  if(tab==='add'){
    if(!requireLogin()) return;
    openSheet('addOffer'); return;
  }
  // tabs requiring login
  State.tab = tab;
  $$('.tabpane').forEach(p=>p.style.display='none');
  const pane = $('#tab-'+tab); if(pane) pane.style.display='block';
  $$('.bottomnav button').forEach(b=>b.classList.toggle('active', b.dataset.tab===tab));

  if(tab==='offers') renderOffers();
  if(tab==='requests') renderRequests();
  if(tab==='appointments') renderAppointments();
  if(tab==='profile') renderProfile();
  go('main');
}

function bindMain(){
  $$('.bottomnav button').forEach(b=>b.onclick=()=>switchTab(b.dataset.tab));
  const bell = $('#bellBtn'); if(bell) bell.onclick=()=>{ if(requireLogin()) openSheet('notif'); };
  const sb = $('#searchBar'); if(sb) sb.onclick=()=>toast('🔍 البحث والفلترة — نموذج');
}

// ============================================================
//  تبديل الدور (شريط التجربة)
// ============================================================
function setRole(role){
  State.role = role;
  $$('.role-switch button').forEach(b=>b.classList.toggle('on', b.dataset.role===role));
  if(role==='visitor'){ State.loggedIn=false; }
  else { State.loggedIn=true; if(!State.phone) State.phone='0991 234 567'; }
}
$$('.role-switch button').forEach(b=>b.onclick=()=>{
  setRole(b.dataset.role);
  if(b.dataset.role==='visitor'){ State.phone=''; }
  toast('وضع التجربة: '+({visitor:'زائر',user:'مستخدم',broker:'سمسار',admin:'إدارة'})[b.dataset.role]
    + (b.dataset.role==='broker'||b.dataset.role==='admin'?' — لوحة التحكم قيد الإعداد':''));
  switchTab('offers');
});

// ساعة
function tick(){ const d=new Date(); $('#clock').textContent = d.getHours()+':'+String(d.getMinutes()).padStart(2,'0'); }
setInterval(tick,10000); tick();

// تشغيل
render();
