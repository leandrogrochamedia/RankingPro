-- Ranking Pro Shark — Núcleo Semana 1–2
-- Rodar no SQL Editor do projeto Supabase NOVO

-- Extensão para UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =====================================================
-- TABELAS
-- =====================================================

CREATE TABLE professionals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  specialty TEXT,
  avatar_url TEXT,
  whatsapp TEXT,
  average_rating NUMERIC(3,2) NOT NULL DEFAULT 0,
  total_reviews INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE qr_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  professional_id UUID NOT NULL REFERENCES professionals(id) ON DELETE CASCADE,
  token TEXT UNIQUE NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_qr_sessions_token ON qr_sessions(token);
CREATE INDEX idx_qr_sessions_professional ON qr_sessions(professional_id);

CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  professional_id UUID NOT NULL REFERENCES professionals(id) ON DELETE CASCADE,
  qr_session_id UUID NOT NULL UNIQUE REFERENCES qr_sessions(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  is_verified BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reviews_professional ON reviews(professional_id, created_at DESC);

-- =====================================================
-- TRIGGER: recalcular nota média
-- =====================================================

CREATE OR REPLACE FUNCTION recalc_professional_rating(p_professional_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_avg NUMERIC(3,2);
  v_count INTEGER;
BEGIN
  SELECT
    COALESCE(ROUND(AVG(rating)::NUMERIC, 2), 0),
    COUNT(*)::INTEGER
  INTO v_avg, v_count
  FROM reviews
  WHERE professional_id = p_professional_id;

  UPDATE professionals
  SET
    average_rating = v_avg,
    total_reviews = v_count,
    updated_at = NOW()
  WHERE id = p_professional_id;
END;
$$;

CREATE OR REPLACE FUNCTION trg_reviews_recalc_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM recalc_professional_rating(NEW.professional_id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER reviews_after_insert_recalc
  AFTER INSERT ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION trg_reviews_recalc_rating();

-- =====================================================
-- RPC: validar token QR
-- =====================================================

CREATE OR REPLACE FUNCTION validate_qr_token(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session qr_sessions%ROWTYPE;
  v_prof professionals%ROWTYPE;
BEGIN
  IF p_token IS NULL OR LENGTH(TRIM(p_token)) = 0 THEN
    RETURN json_build_object('status', 'invalid');
  END IF;

  SELECT * INTO v_session
  FROM qr_sessions
  WHERE token = TRIM(p_token);

  IF NOT FOUND THEN
    RETURN json_build_object('status', 'invalid');
  END IF;

  SELECT * INTO v_prof
  FROM professionals
  WHERE id = v_session.professional_id;

  IF v_session.used_at IS NOT NULL THEN
    RETURN json_build_object(
      'status', 'used',
      'professional_slug', v_prof.slug,
      'professional_name', v_prof.name
    );
  END IF;

  IF v_session.expires_at < NOW() THEN
    RETURN json_build_object(
      'status', 'expired',
      'professional_slug', v_prof.slug,
      'professional_name', v_prof.name
    );
  END IF;

  RETURN json_build_object(
    'status', 'valid',
    'session_id', v_session.id,
    'professional_id', v_session.professional_id,
    'professional_slug', v_prof.slug,
    'professional_name', v_prof.name,
    'professional_specialty', v_prof.specialty,
    'expires_at', v_session.expires_at
  );
END;
$$;

-- =====================================================
-- RPC: submeter avaliação via QR (único ponto de INSERT)
-- =====================================================

CREATE OR REPLACE FUNCTION submit_qr_review(
  p_token TEXT,
  p_rating INTEGER,
  p_comment TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session qr_sessions%ROWTYPE;
  v_prof professionals%ROWTYPE;
  v_review_id UUID;
  v_comment TEXT;
BEGIN
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RETURN json_build_object('status', 'error', 'message', 'Nota inválida. Escolha de 1 a 5.');
  END IF;

  v_comment := NULLIF(TRIM(p_comment), '');
  IF v_comment IS NOT NULL AND LENGTH(v_comment) > 500 THEN
    RETURN json_build_object('status', 'error', 'message', 'Comentário deve ter no máximo 500 caracteres.');
  END IF;

  SELECT * INTO v_session
  FROM qr_sessions
  WHERE token = TRIM(p_token)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('status', 'invalid');
  END IF;

  IF v_session.used_at IS NOT NULL THEN
    RETURN json_build_object('status', 'used');
  END IF;

  IF v_session.expires_at < NOW() THEN
    RETURN json_build_object('status', 'expired');
  END IF;

  SELECT * INTO v_prof
  FROM professionals
  WHERE id = v_session.professional_id;

  INSERT INTO reviews (professional_id, qr_session_id, rating, comment, is_verified)
  VALUES (v_session.professional_id, v_session.id, p_rating, v_comment, TRUE)
  RETURNING id INTO v_review_id;

  UPDATE qr_sessions
  SET used_at = NOW()
  WHERE id = v_session.id;

  RETURN json_build_object(
    'status', 'success',
    'review_id', v_review_id,
    'professional_slug', v_prof.slug,
    'professional_name', v_prof.name
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('status', 'used');
END;
$$;

-- =====================================================
-- RPC: criar sessão QR (dev/MVP — Semana 3 terá auth)
-- =====================================================

CREATE OR REPLACE FUNCTION create_qr_session(
  p_professional_id UUID,
  p_expires_hours INTEGER DEFAULT 2
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prof professionals%ROWTYPE;
  v_token TEXT;
  v_session_id UUID;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF p_expires_hours IS NULL OR p_expires_hours < 1 OR p_expires_hours > 48 THEN
    p_expires_hours := 2;
  END IF;

  SELECT * INTO v_prof
  FROM professionals
  WHERE id = p_professional_id;

  IF NOT FOUND THEN
    RETURN json_build_object('status', 'error', 'message', 'Profissional não encontrado.');
  END IF;

  v_token := gen_random_uuid()::TEXT;
  v_expires_at := NOW() + (p_expires_hours || ' hours')::INTERVAL;

  INSERT INTO qr_sessions (professional_id, token, expires_at)
  VALUES (p_professional_id, v_token, v_expires_at)
  RETURNING id INTO v_session_id;

  RETURN json_build_object(
    'status', 'success',
    'session_id', v_session_id,
    'token', v_token,
    'expires_at', v_expires_at,
    'professional_slug', v_prof.slug,
    'professional_name', v_prof.name
  );
END;
$$;

-- =====================================================
-- RLS
-- =====================================================

ALTER TABLE professionals ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- professionals: leitura pública
CREATE POLICY professionals_select_public
  ON professionals FOR SELECT
  TO anon, authenticated
  USING (true);

-- professionals: escrita só authenticated (seed manual / futuro dashboard)
CREATE POLICY professionals_insert_auth
  ON professionals FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY professionals_update_auth
  ON professionals FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- qr_sessions: sem acesso direto anon (só via RPC)
CREATE POLICY qr_sessions_no_anon_select
  ON qr_sessions FOR SELECT
  TO anon
  USING (false);

CREATE POLICY qr_sessions_insert_auth
  ON qr_sessions FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- reviews: leitura pública (perfil)
CREATE POLICY reviews_select_public
  ON reviews FOR SELECT
  TO anon, authenticated
  USING (true);

-- reviews: sem INSERT direto (só via submit_qr_review RPC)
CREATE POLICY reviews_no_direct_insert
  ON reviews FOR INSERT
  TO anon, authenticated
  WITH CHECK (false);

-- =====================================================
-- GRANTS para RPCs
-- =====================================================

GRANT EXECUTE ON FUNCTION validate_qr_token(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION submit_qr_review(TEXT, INTEGER, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_qr_session(UUID, INTEGER) TO anon, authenticated;

-- =====================================================
-- SEED dev
-- =====================================================

INSERT INTO professionals (slug, name, specialty)
VALUES ('joao-barbeiro-teste', 'João Barbeiro (Teste)', 'Barbeiro')
ON CONFLICT (slug) DO NOTHING;