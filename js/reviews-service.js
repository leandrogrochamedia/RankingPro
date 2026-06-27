// Ranking Pro — submit review via QR (Proofly REST + RPC)

(function (global) {
  'use strict';

  const API = () => global.RankingProAPI;
  const QR = () => global.RankingProQR;

  async function submitQrReviewDirect(token, rating, comment) {
    const check = await QR().validateToken(token);
    if (check.status === 'used') return { status: 'used' };
    if (check.status === 'expired') return { status: 'expired' };
    if (check.status !== 'valid') return { status: 'invalid' };

    const trimmed = (comment || '').trim();
    if (trimmed.length > 500) {
      return { status: 'error', message: 'Comentário deve ter no máximo 500 caracteres.' };
    }

    const qr = await QR().fetchQrByToken(token);
    if (!qr) return { status: 'invalid' };

    const review = await API().insert('reviews', {
      professional_id: qr.professional_id,
      rating: rating,
      comment: trimmed || null,
      verified: true,
      is_verified: true,
      qr_token: token,
      review_type: 'client_to_professional',
      source: 'cliente',
      user_id: null
    });

    try {
      await API().update('qr_codes', '?id=eq.' + encodeURIComponent(qr.id), {
        used_at: new Date().toISOString()
      });
    } catch (err) {
      if (!String(err.message).includes('used_at')) {
        console.warn('qr_codes.used_at:', err.message);
      }
    }

    const prof = await API().select(
      'professionals',
      '?id=eq.' + encodeURIComponent(qr.professional_id) + '&select=id,name&limit=1'
    );

    return {
      status: 'success',
      review_id: review?.id,
      professional_id: prof?.[0]?.id || qr.professional_id,
      professional_name: prof?.[0]?.name || check.professional_name
    };
  }

  async function submitQrReview(token, rating, comment) {
    try {
      const rpc = await API().rpc('submit_qr_review', {
        p_token: token,
        p_rating: rating,
        p_comment: comment || null
      });
      if (rpc && rpc.status) return rpc;
    } catch (err) {
      if (!String(err.message).includes('PGRST202')) {
        console.warn('submit_qr_review RPC:', err.message);
      }
    }
    return submitQrReviewDirect(token, rating, comment);
  }

  global.RankingProReviews = {
    submitQrReview
  };
})(window);