/* Site público da Ipiranga — lê os imóveis direto do CRM (Supabase) */
const CFG={SUPABASE_URL:"https://rqdcsydbeaotpmrujryh.supabase.co",SUPABASE_ANON_KEY:"sb_publishable_EZqLB2BtDefw4Swx1Mt5XA_DMV363DC",
  WHATS:"5562999938383",INSTAGRAM:"https://www.instagram.com/ipirangagestaoimob",CRECI:"CRECI 38481-J",
  ENDERECO:"Av. Senador José Lourenço Dias, 1470 – Anápolis-GO",RAZAO:"Ipiranga Soluções Imobiliárias Ltda",GTM:["GTM-TQGMS65N","GTM-PZ8T9ZVH"]};
const sb=window.supabase.createClient(CFG.SUPABASE_URL,CFG.SUPABASE_ANON_KEY);
const BASE=location.pathname.startsWith('/ipiranga-crm/')?'/ipiranga-crm/':'/';
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const brl=v=>(+v||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL',maximumFractionDigits:0});
const soDig=t=>String(t||'').replace(/\D/g,'');
const fotoNossa=u=>/\/storage\/v1\/object\/public\/fotos\//.test(u||'');
const slug=t=>String(t||'imovel').normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,80)||'imovel';
const linkImovel=i=>`${BASE}imovel.html?c=${encodeURIComponent(i.codigo||i.id)}&${slug(i.titulo)}`;
const wa=msg=>`https://wa.me/${CFG.WHATS}?text=${encodeURIComponent(msg)}`;
const specs=i=>[i.area&&`📐 ${String(i.area).replace('.',',')} m²`,i.area_terreno&&!/lote|terreno/i.test(i.tipo||'')&&`🌳 ${String(i.area_terreno).replace('.',',')} m² terreno`,i.quartos&&`🛏️ ${i.quartos}`,i.suites&&`🛁 ${i.suites}`,i.vagas&&`🚗 ${i.vagas}`].filter(Boolean);
function card(i){const f=(i.fotos||[])[0];
  return`<a class="card" href="${linkImovel(i)}"><div class="foto ${f&&!fotoNossa(f)?'wm':''}">${f?`<img loading="lazy" src="${esc(f)}" alt="${esc(i.titulo)}">`:''}<span class="tag">${i.finalidade==='Aluguel'?'Aluguel':'Venda'}${i.tipo?' · '+esc(i.tipo):''}</span></div>
   <div class="info"><div class="preco">${i.valor?brl(i.valor):'Consulte'}</div><div class="tit">${esc(i.titulo)}</div>
   <div class="loc">📍 ${esc([i.condominio,i.bairro].filter(Boolean).join(' · ')||'Anápolis')}</div>
   <div class="specs">${specs(i).map(s=>`<span>${s}</span>`).join('')}</div></div></a>`}
let _cache=null;
async function imoveis(){if(_cache)return _cache;const{data,error}=await sb.from('site_imoveis').select('*').order('criado',{ascending:false});
  if(error){console.error(error);return[]}return _cache=data||[]}
function topo(){return`<header class="topo"><div class="wrap"><a class="logo" href="${BASE}"><img src="${BASE}assets/logo-claro.png" alt="Ipiranga Gestão Imobiliária"></a>
  <nav id="nav"><a href="${BASE}?fin=Venda#imoveis">Comprar</a><a href="${BASE}?fin=Aluguel#imoveis">Alugar</a><a href="${BASE}#sobre">Institucional</a><a href="${BASE}#contato">Contato</a></nav>
  <div class="dir"><a class="btn claro" href="${BASE}crm/">Área do corretor</a><a class="btn wa" href="${wa('Olá! Vim pelo site da Ipiranga e gostaria de atendimento.')}" target="_blank" rel="noopener">WhatsApp</a>
  <button class="menu-cel" onclick="document.getElementById('nav').classList.toggle('on')" aria-label="Menu">☰</button></div></div></header>`}
function rodape(){return`<footer><div class="wrap"><div class="cols"><div><img src="${BASE}assets/logo-escuro.png" alt="Ipiranga"><p>Exclusivamente seu.<br>${CFG.ENDERECO}</p></div>
  <div><b style="color:#fff">Imóveis</b><br><a href="${BASE}?fin=Venda#imoveis">Comprar</a><br><a href="${BASE}?fin=Aluguel#imoveis">Alugar</a><br><a href="${BASE}#contato">Anuncie seu imóvel</a></div>
  <div><b style="color:#fff">Fale com a gente</b><br><a href="${wa('Olá! Vim pelo site da Ipiranga.')}" target="_blank" rel="noopener">WhatsApp (62) 99993-8383</a><br><a href="${CFG.INSTAGRAM}" target="_blank" rel="noopener">Instagram</a><br><a href="${BASE}crm/">Área do corretor</a></div></div>
  <div class="base"><span>© ${new Date().getFullYear()} ${CFG.RAZAO}. Todos os direitos reservados. ${CFG.CRECI}.</span><span>Anápolis-GO</span></div></div></footer>
  <a class="zap" href="${wa('Olá! Vim pelo site da Ipiranga.')}" target="_blank" rel="noopener" aria-label="WhatsApp">💬</a>`}
/* Google Tag Manager só depois do aceite de cookies */
function gtm(){if(window._gtm)return;window._gtm=1;window.dataLayer=window.dataLayer||[];dataLayer.push({'gtm.start':new Date().getTime(),event:'gtm.js'});
  [].concat(CFG.GTM).forEach(i=>{const j=document.createElement('script');j.async=true;j.src='https://www.googletagmanager.com/gtm.js?id='+i;document.head.appendChild(j)})}
function cookies(){let ok=null;try{ok=localStorage.getItem('ipi_cookies')}catch(e){}if(ok==='1')return gtm();if(ok==='0')return;
  const d=document.createElement('div');d.className='cookie';d.innerHTML='<span style="flex:1">Usamos cookies para medir visitas e melhorar sua experiência.</span><button class="btn claro" id="ckN">Recusar</button><button class="btn" id="ckS">Aceitar</button>';
  document.body.appendChild(d);const fim=v=>{try{localStorage.setItem('ipi_cookies',v)}catch(e){}d.remove();if(v==='1')gtm()};$('ckS').onclick=()=>fim('1');$('ckN').onclick=()=>fim('0')}
/* formulário de contato -> lead no CRM (roleta "Site") */
async function enviarLead(form,extra={}){const f=new FormData(form),msg=form.querySelector('.retorno');
  if(f.get('empresa'))return; // armadilha anti-robô
  const nome=(f.get('nome')||'').trim(),tel=(f.get('tel')||'').trim();
  if(nome.length<2||soDig(tel).length<10){msg.innerHTML='<div class="erro">Preencha seu nome e um telefone com DDD.</div>';return}
  const b=form.querySelector('button[type=submit]');b.disabled=true;b.textContent='Enviando…';
  const{error}=await sb.rpc('site_lead',{p_nome:nome,p_tel:tel,p_email:(f.get('email')||'').trim()||null,p_msg:(f.get('msg')||'').trim()||null,p_codigo:extra.codigo||null});
  b.disabled=false;b.textContent='Enviar';
  if(error){console.error(error);msg.innerHTML=`<div class="erro">Não conseguimos enviar agora. Fale com a gente pelo <a href="${wa('Olá! Vim pelo site.')}" target="_blank" rel="noopener">WhatsApp</a>.</div>`;return}
  form.reset();msg.innerHTML='<div class="ok">✅ Recebemos seu contato! Um corretor da Ipiranga vai te chamar em instantes.</div>';
  try{(window.dataLayer=window.dataLayer||[]).push({event:'lead_site',codigo:extra.codigo||''})}catch(e){}}
