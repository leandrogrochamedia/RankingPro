// Ranking Pro — submit review via QR RPC

(function (global) {
  'use strict';

  const API = () => global.RankingProAPI;

  async function submitQrReview(token, rating, comment) {
    return API().rpc('submit_qr_review', {
      p_token: token,
      p_rating: rating,
      p_comment: comment || null
    });
  }

  global.RankingProReviews = {
    submitQrReview
  };
})(window);