/**
 * The public shop page: plain HTML and one script file, no framework, so it loads fast on a phone.
 * The script is served from our own address because the server's security policy refuses inline scripts.
 * Everything that comes from the business or a customer is put on the page as text, never as markup.
 */

export const storeHtml = (slug: string) => `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Shop</title>
<style>
:root{--bg:#f4f6fb;--card:#fff;--ink:#14213d;--mute:#5b6478;--brand:#1e5eff;--line:#e3e7f0;--ok:#16794c}
@media(prefers-color-scheme:dark){:root{--bg:#0f1420;--card:#171e2e;--ink:#e8ecf5;--mute:#98a2b8;--line:#263049;--brand:#6b97ff;--ok:#4cc38a}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 system-ui,sans-serif}
header{padding:20px 16px 8px;max-width:960px;margin:auto}h1{margin:0;font-size:24px}.mute{color:var(--mute);font-size:14px}
main{max-width:960px;margin:auto;padding:8px 16px 120px}
#search{width:100%;padding:12px;border:1px solid var(--line);border-radius:10px;background:var(--card);color:var(--ink);font-size:16px;margin:8px 0 16px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden;display:flex;flex-direction:column}
.card img{width:100%;aspect-ratio:4/3;object-fit:cover;background:var(--line)}
.card .b{padding:10px 12px;display:flex;flex-direction:column;gap:4px;flex:1}.name{font-weight:600}.price{font-size:18px}
button{font:inherit;border:0;border-radius:10px;padding:10px 14px;background:var(--brand);color:#fff;cursor:pointer}
button.ghost{background:transparent;color:var(--brand);border:1px solid var(--brand)}button:disabled{opacity:.5;cursor:default}
.qty{display:flex;align-items:center;gap:10px;margin-top:auto}.qty b{min-width:24px;text-align:center}.qty button{padding:6px 12px}
#bar{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-top:1px solid var(--line);padding:12px 16px;display:none}
#bar .in{max-width:960px;margin:auto;display:flex;justify-content:space-between;align-items:center;gap:12px}
dialog{border:0;border-radius:14px;padding:20px;max-width:480px;width:calc(100% - 32px);background:var(--card);color:var(--ink)}dialog::backdrop{background:#0008}
label{display:block;margin:10px 0 4px;font-size:14px;color:var(--mute)}input,textarea{width:100%;padding:10px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--ink);font:inherit}
.row{display:flex;justify-content:space-between;gap:8px;padding:4px 0}.err{color:#c62828;margin-top:8px}.ok{color:var(--ok)}.hp{position:absolute;left:-9999px}
</style></head><body data-slug="${slug.replace(/[^a-z0-9-]/g, '')}">
<header><h1 id="title">Shop</h1><div class="mute" id="sub"></div></header>
<main><input id="search" type="search" placeholder="Search products" aria-label="Search products"><div id="grid" class="grid"></div><p id="empty" class="mute" hidden>Nothing to show.</p></main>
<div id="bar"><div class="in"><div><b id="count"></b> <span class="mute" id="total"></span></div><button id="open">Place order</button></div></div>
<dialog id="dlg"><form id="form" method="dialog">
<h2 style="margin-top:0">Your order</h2><div id="lines"></div><div class="row"><b>Total</b><b id="sum"></b></div><div class="mute" id="tax"></div>
<label for="name">Your name</label><input id="name" required maxlength="100" autocomplete="name">
<label for="phone">Mobile number</label><input id="phone" required inputmode="tel" maxlength="20" autocomplete="tel">
<label for="address">Delivery address</label><textarea id="address" rows="2" maxlength="300" autocomplete="street-address"></textarea>
<label for="note">Note (optional)</label><input id="note" maxlength="300">
<input class="hp" id="website" tabindex="-1" autocomplete="off" aria-hidden="true">
<div id="msg" class="err" role="alert"></div>
<div style="display:flex;gap:8px;margin-top:14px;justify-content:flex-end"><button type="button" class="ghost" id="cancel">Back</button><button id="send">Send order</button></div>
</form></dialog>
<script src="/store/_assets/store.js"></script></body></html>`;

export const storeScript = `(function(){
var slug=document.body.dataset.slug,$=function(i){return document.getElementById(i)},cart={},data={items:[]};
var rs=function(n){return '\\u20b9'+Number(n).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2})};
function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e}
function render(){
  var q=$('search').value.trim().toLowerCase(),g=$('grid');g.textContent='';
  var shown=data.items.filter(function(i){return !q||i.name.toLowerCase().indexOf(q)>=0});
  $('empty').hidden=shown.length>0;
  shown.forEach(function(i){
    var c=el('div','card');
    if(i.image){var im=el('img');im.src='/store/'+slug+'/image/'+i.image;im.alt='';im.loading='lazy';c.appendChild(im)}
    var b=el('div','b');b.appendChild(el('div','name',i.name));b.appendChild(el('div','price',rs(i.price)+(i.unit?' / '+i.unit:'')));
    if(i.soldOut)b.appendChild(el('div','mute','Out of stock'));
    else{var n=cart[i.id]||0,qy=el('div','qty');
      if(n){var m=el('button','ghost','\\u2212');m.onclick=function(){set(i.id,n-1)};qy.appendChild(m);qy.appendChild(el('b','',n))}
      var p=el('button','ghost',n?'+':'Add');p.onclick=function(){set(i.id,n+1)};qy.appendChild(p);b.appendChild(qy)}
    c.appendChild(b);g.appendChild(c)})}
function set(id,n){if(n<=0)delete cart[id];else cart[id]=Math.min(n,999);render();bar()}
function lines(){return data.items.filter(function(i){return cart[i.id]}).map(function(i){return{item:i,qty:cart[i.id]}})}
function sum(){return lines().reduce(function(s,l){return s+l.item.price*l.qty},0)}
function bar(){var n=lines().reduce(function(s,l){return s+l.qty},0);$('bar').style.display=n?'block':'none';$('count').textContent=n+(n===1?' item':' items');$('total').textContent=rs(sum())}
$('open').onclick=function(){var l=$('lines');l.textContent='';lines().forEach(function(x){var r=el('div','row');r.appendChild(el('span','',x.qty+' \\u00d7 '+x.item.name));r.appendChild(el('span','',rs(x.item.price*x.qty)));l.appendChild(r)});
  $('sum').textContent=rs(sum());$('tax').textContent='Prices include GST where it applies. '+(data.note||'');$('msg').textContent='';$('send').disabled=false;$('dlg').showModal()};
$('cancel').onclick=function(){$('dlg').close()};$('search').oninput=render;
$('form').onsubmit=function(e){e.preventDefault();$('send').disabled=true;$('msg').textContent='';
  fetch('/store/'+slug+'/orders',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({name:$('name').value,phone:$('phone').value,address:$('address').value,note:$('note').value,website:$('website').value,
    lines:lines().map(function(l){return{itemId:l.item.id,quantity:l.qty}})})})
  .then(function(r){return r.json().then(function(j){return{ok:r.ok,j:j}})})
  .then(function(x){if(!x.ok){$('msg').textContent=(x.j&&x.j.error&&x.j.error.message)||'Could not send the order.';$('send').disabled=false;return}
    cart={};render();bar();$('dlg').close();document.body.insertBefore(el('p','ok','Thank you! Your order '+x.j.number+' was sent. '+data.name+' will contact you to confirm.'),document.querySelector('main'))})
  .catch(function(){$('msg').textContent='No connection. Please try again.';$('send').disabled=false})};
fetch('/store/'+slug+'/data').then(function(r){if(!r.ok)throw 0;return r.json()}).then(function(d){data=d;document.title=d.name;$('title').textContent=d.name;
  $('sub').textContent=[d.tagline,d.phone,d.address].filter(Boolean).join(' \\u00b7 ');render()})
  .catch(function(){$('title').textContent='Shop not found';$('search').hidden=true});
})();`;
