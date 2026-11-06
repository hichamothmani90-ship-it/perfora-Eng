/* Site de présentation Perfora. */
// Numéro WhatsApp de contact, au format international sans « + » ni espaces (ex. 212600000000).
// Vide : les boutons « Demander une démo » ouvrent un e-mail.
const WHATSAPP = '212680032888';
if (WHATSAPP) {
  const msg = encodeURIComponent("Bonjour, je souhaite une démo de Perfora (GMAO de terrain).");
  document.querySelectorAll('.js-contact').forEach(a => { a.href = `https://wa.me/${WHATSAPP}?text=${msg}`; a.target = '_blank'; a.rel = 'noopener'; });
}
document.getElementById('an').textContent = new Date().getFullYear();
  
