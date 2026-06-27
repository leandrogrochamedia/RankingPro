// Ranking Pro — QR session validation & creation

(function (global) {
  'use strict';

  const API = () => global.RankingProAPI;

  async function validateToken(token) {
    if (!token) return { status: 'invalid' };
    return API().rpc('validate_qr_token', { p_token: token });
  }

  async function createSession(professionalId, expiresHours = 2) {
    return API().rpc('create_qr_session', {
      p_professional_id: professionalId,
      p_expires_hours: expiresHours
    });
  }

  function getTokenFromUrl() {
    const params = new URLSearchParams(window.location.search);
    return params.get('token') || null;
  }

  function buildQrUrl(token) {
    const base = window.location.origin + '/qr/';
    return base + '?token=' + encodeURIComponent(token);
  }

  function buildAvaliarUrl(token) {
    const base = window.location.origin + '/avaliar/';
    return base + '?token=' + encodeURIComponent(token);
  }

  function buildProfileUrl(slug) {
    return window.location.origin + '/p/?slug=' + encodeURIComponent(slug);
  }

  global.RankingProQR = {
    validateToken,
    createSession,
    getTokenFromUrl,
    buildQrUrl,
    buildAvaliarUrl,
    buildProfileUrl
  };
})(window);