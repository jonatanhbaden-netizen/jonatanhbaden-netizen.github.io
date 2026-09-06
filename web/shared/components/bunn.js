// Same footer on every page. Injected so the pages stay small.
const bunn = document.createElement('footer');
bunn.className = 'bunn';
bunn.innerHTML = `
  <div class="innhold rad-mellom">
    <span class="svak">© 2026 Jobbo · Oslo</span>
    <nav class="rad">
      <a href="/stillinger.html">Ledige stillinger</a>
      <a href="/om.html">Om Jobbo</a>
      <a href="/konto/vilkar.html">Vilkår</a>
      <a href="/konto/personvern.html">Personvern</a>
    </nav>
  </div>`;
document.body.append(bunn);
