// Ranking Pro — QR (Proofly qr_codes — REST direto + RPC quando existir)

(function (global) {
  'use strict';

  const API = () => global.RankingProAPI;

  function newToken() {
    if (global.crypto?.randomUUID) return global.crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  async function fetchQrByToken(token) {
    try {
      const rows = await API().select(
        'qr_codes',
        '?token=eq.' + encodeURIComponent(token) +
          '&select=id,professional_id,token,expires_at,used_at&limit=1'
      );
      return rows?.[0] || null;
    } catch (err) {
      if (String(err.message).includes('used_at')) {
        const rows = await API().select(
          'qr_codes',
          '?token=eq.' + encodeURIComponent(token) +
            '&select=id,professional_id,token,expires_at&limit=1'
        );
        return rows?.[0] || null;
      }
      throw err;
    }
  }

  async function hasReviewForToken(token) {
    const rows = await API().select(
      'reviews',
      '?qr_token=eq.' + encodeURIComponent(token) + '&select=id&limit=1'
    );
    return !!(rows && rows.length);
  }

  async function fetchProfessionalBrief(id) {
    const rows = await API().select(
      'professionals',
      '?id=eq.' + encodeURIComponent(id) +
        '&select=id,name,specialty,avatar_url,avg_rating,total_reviews&limit=1'
    );
    return rows?.[0] || null;
  }

  async function validateTokenDirect(token) {
    const qr = await fetchQrByToken(token);
    if (!qr) return { status: 'invalid' };

    const prof = await fetchProfessionalBrief(qr.professional_id);
    const base = {
      professional_id: prof?.id || qr.professional_id,
      professional_name: prof?.name || '',
      professional_specialty: prof?.specialty || ''
    };

    if (qr.used_at || (await hasReviewForToken(token))) {
      return { status: 'used', ...base };
    }

    if (qr.expires_at && new Date(qr.expires_at) < new Date()) {
      return { status: 'expired', ...base };
    }

    return {
      status: 'valid',
      session_id: qr.id,
      expires_at: qr.expires_at,
      ...base
    };
  }

  async function validateToken(token) {
    if (!token) return { status: 'invalid' };
    try {
      const rpc = await API().rpc('validate_qr_token', { p_token: token });
      if (rpc && rpc.status) return rpc;
    } catch (err) {
      if (!String(err.message).includes('PGRST202')) {
        console.warn('validate_qr_token RPC:', err.message);
      }
    }
    return validateTokenDirect(token);
  }

  async function createSessionDirect(professionalId, expiresHours = 2) {
    const token = newToken();
    const url = buildQrUrl(token);
    const expiresAt = new Date(Date.now() + expiresHours * 60 * 60 * 1000).toISOString();
    const row = await API().insert('qr_codes', {
      professional_id: professionalId,
      token: token,
      url: url,
      expires_at: expiresAt
    });
    const prof = await fetchProfessionalBrief(professionalId);
    return {
      status: 'success',
      session_id: row?.id,
      token: token,
      url: url,
      expires_at: expiresAt,
      professional_id: prof?.id || professionalId,
      professional_name: prof?.name || ''
    };
  }

  async function createSession(professionalId, expiresHours = 2) {
    try {
      const rpc = await API().rpc('create_qr_session', {
        p_professional_id: professionalId,
        p_expires_hours: expiresHours,
        p_app_base_url: global.location.origin
      });
      if (rpc?.status === 'success') return rpc;
    } catch (err) {
      if (!String(err.message).includes('PGRST202')) {
        console.warn('create_qr_session RPC:', err.message);
      }
    }
    return createSessionDirect(professionalId, expiresHours);
  }

  function getTokenFromUrl() {
    const params = new URLSearchParams(global.location.search);
    return params.get('token') || params.get('qr_token') || null;
  }

  function getProfessionalIdFromUrl() {
    const params = new URLSearchParams(global.location.search);
    return params.get('professionalId') || params.get('professional_id') || null;
  }

  function buildQrUrl(token) {
    const base = global.location.origin + '/qr/';
    return base + '?token=' + encodeURIComponent(token);
  }

  function buildAvaliarUrl(token) {
    const base = global.location.origin + '/avaliar/';
    return base + '?token=' + encodeURIComponent(token);
  }

  function buildProfileUrl(professionalId) {
    return global.location.origin + '/p/?id=' + encodeURIComponent(professionalId);
  }

  function getProfessionalIdFromRpc(data) {
    return data?.professional_id || data?.professional_slug || null;
  }

  global.RankingProQR = {
    validateToken,
    createSession,
    getTokenFromUrl,
    getProfessionalIdFromUrl,
    buildQrUrl,
    buildAvaliarUrl,
    buildProfileUrl,
    getProfessionalIdFromRpc,
    fetchQrByToken
  };
})(window);