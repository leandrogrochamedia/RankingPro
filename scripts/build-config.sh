#!/bin/sh
set -eu

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "AVISO: SUPABASE_URL e SUPABASE_ANON_KEY não definidas — config.js não gerado."
  echo "Para deploy Netlify, configure em Site settings → Environment variables."
  exit 0
fi

cat > config.js << EOF
window.RANKING_PRO_CONFIG = {
  SUPABASE_URL: '${SUPABASE_URL}',
  SUPABASE_ANON_KEY: '${SUPABASE_ANON_KEY}'
};
EOF

echo "config.js gerado para deploy."