Scalar.createApiReference('#api-reference', {
  url: '/docs/openapi.json',
  theme: 'default',
  darkMode: true,
  layout: 'modern',
  localization: { locale: 'pt-BR' },
  persistAuth: false,
  withDefaultFonts: false,
  showDeveloperTools: 'never',
  hideClientButton: true,
  telemetry: false,
  // Mesma origem: nenhum proxy externo recebe tokens, certificados ou XMLs.
  servers: [{ url: window.location.origin, description: window.location.hostname.startsWith('sandbox.') ? 'Homologação — dados separados' : 'Ambiente atual' }],
});
