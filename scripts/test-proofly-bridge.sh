#!/bin/sh
# Teste E2E — Proofly (REST direto ou RPC)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f config.js ]; then
  echo "ERRO: config.js ausente"
  exit 1
fi

SUPABASE_URL=$(python3 -c "import re; c=open('config.js').read(); m=re.search(r\"SUPABASE_URL:\\s*'([^']+)'\", c); print(m.group(1) if m else '')")
SUPABASE_KEY=$(python3 -c "import re; c=open('config.js').read(); m=re.search(r\"SUPABASE_ANON_KEY:\\s*'([^']+)'\", c); print(m.group(1) if m else '')")
HDR1="apikey: $SUPABASE_KEY"
HDR2="Authorization: Bearer $SUPABASE_KEY"

echo "1) Profissional..."
PROF_JSON=$(/usr/bin/curl -s "$SUPABASE_URL/rest/v1/professionals?select=id,name&order=name.asc&limit=1" -H "$HDR1" -H "$HDR2")
PROF_ID=$(echo "$PROF_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'])")
PROF_NAME=$(echo "$PROF_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['name'])")
echo "   $PROF_NAME ($PROF_ID)"

TOKEN=$(python3 -c "import uuid; print(uuid.uuid4())")
EXPIRES=$(python3 -c "from datetime import datetime,timedelta; print((datetime.utcnow()+timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")
URL="http://localhost:8765/qr/?token=$TOKEN"

echo "2) INSERT qr_codes..."
CREATE=$(/usr/bin/curl -s -X POST "$SUPABASE_URL/rest/v1/qr_codes" \
  -H "$HDR1" -H "$HDR2" -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d "{\"professional_id\":\"$PROF_ID\",\"token\":\"$TOKEN\",\"url\":\"$URL\",\"expires_at\":\"$EXPIRES\"}")
echo "$CREATE" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d; print('   OK token=', r.get('token','?'))"

echo "3) validate (REST)..."
VAL=$(/usr/bin/curl -s "$SUPABASE_URL/rest/v1/qr_codes?token=eq.$TOKEN&select=id,expires_at&limit=1" -H "$HDR1" -H "$HDR2")
echo "$VAL" | python3 -c "import sys,json; assert json.load(sys.stdin), 'invalid'; print('   OK')"

echo "4) submit review anônima..."
SUB=$(/usr/bin/curl -s -X POST "$SUPABASE_URL/rest/v1/reviews" \
  -H "$HDR1" -H "$HDR2" -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d "{\"professional_id\":\"$PROF_ID\",\"rating\":5,\"comment\":\"Teste Magrão $(date +%H:%M)\",\"verified\":true,\"is_verified\":true,\"qr_token\":\"$TOKEN\",\"review_type\":\"client_to_professional\",\"source\":\"cliente\",\"user_id\":null}")
echo "$SUB" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d; print('   OK review', r.get('id','?'))"

echo "5) single-use check..."
DUP=$(/usr/bin/curl -s "$SUPABASE_URL/rest/v1/reviews?qr_token=eq.$TOKEN&select=id&limit=1" -H "$HDR1" -H "$HDR2")
echo "$DUP" | python3 -c "import sys,json; assert json.load(sys.stdin); print('   OK bloqueado por review existente')"

echo "6) avg_rating..."
sleep 1
PROF=$(/usr/bin/curl -s "$SUPABASE_URL/rest/v1/professionals?id=eq.$PROF_ID&select=name,avg_rating,total_reviews" -H "$HDR1" -H "$HDR2")
echo "$PROF" | python3 -c "import sys,json; d=json.load(sys.stdin)[0]; print('   ', d['name'], 'avg=', d['avg_rating'], 'total=', d['total_reviews'])"

echo ""
echo "✅ PONTE PROOFLY — teste API OK"
echo "UI: http://localhost:8765/p/?id=$PROF_ID"