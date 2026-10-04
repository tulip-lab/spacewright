const escapeHtml = (value = '') => String(value).replace(/[&<>"]/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'
})[character]);

function dialogInput({ title, message = '', value = '', confirmLabel = 'Confirm', danger = false, input = true }) {
  return new Promise((resolve) => {
    const dialog = document.createElement('dialog');
    dialog.className = 'modal-dialog';
    dialog.innerHTML = `<form method="dialog"><p class="kicker">SpaceWright</p><h2>${escapeHtml(title)}</h2>${message ? `<p class="dialog-copy">${escapeHtml(message)}</p>` : ''}${input ? `<label class="field"><span>Value</span><input name="value" autocomplete="off" value="${escapeHtml(value)}"></label>` : ''}<div class="actions"><button value="cancel" class="quiet">Cancel</button><button value="confirm" class="${danger ? 'danger' : 'primary'}">${escapeHtml(confirmLabel)}</button></div></form>`;
    const finish = () => {
      const accepted = dialog.returnValue === 'confirm';
      const result = accepted ? (input ? dialog.querySelector('[name="value"]').value.trim() : true) : null;
      dialog.remove();
      resolve(result);
    };
    dialog.addEventListener('close', finish, { once: true });
    dialog.addEventListener('click', (event) => { if (event.target === dialog) dialog.close('cancel'); });
    document.body.append(dialog);
    dialog.showModal();
    const target = input ? dialog.querySelector('input') : dialog.querySelector('[value="confirm"]');
    target.focus();
    if (input) target.select();
  });
}

export const confirmAction = (message, options = {}) => dialogInput({
  title: options.title || 'Confirm Action',
  message,
  confirmLabel: options.confirmLabel || 'Confirm',
  danger: options.danger,
  input: false
});

export const promptValue = (title, value = '', message = '') => dialogInput({
  title,
  message,
  value,
  confirmLabel: 'Apply',
  input: true
});
