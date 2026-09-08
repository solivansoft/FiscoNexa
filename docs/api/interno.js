const form = document.getElementById('acesso');
const input = document.getElementById('token');
const message = document.getElementById('mensagem');
document.getElementById('encerrar').addEventListener('click', () => window.location.reload());
form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const token = input.value.trim().replace(/^Bearer\s+/i, '');
  input.value = '';
  message.textContent = 'Validando acesso…';
  try {
    const response = await fetch('/administracao/documentacao', {
      headers: { Authorization: `Bearer ${token}` }, cache: 'no-store', redirect: 'error',
    });
    if (!response.ok) {
      message.textContent = response.status === 401 || response.status === 403
        ? 'Acesso recusado. Use uma sessão válida de superadmin.'
        : 'Documentação temporariamente indisponível.';
      return;
    }
    const content = await response.json();
    Scalar.createApiReference('#api-reference', {
      content, theme: 'default', darkMode: true, localization: { locale: 'pt-BR' },
      persistAuth: false, withDefaultFonts: false, telemetry: false,
      hideClientButton: true, showDeveloperTools: 'never',
      servers: [{ url: window.location.origin, description: 'Ambiente atual' }],
    });
    form.hidden = true;
    document.getElementById('encerrar').hidden = false;
  } catch {
    message.textContent = 'Não foi possível acessar a documentação.';
  }
});
