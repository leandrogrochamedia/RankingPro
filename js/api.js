// Ranking Pro — Supabase REST client

(function (global) {
  'use strict';

  function getConfig() {
    const cfg = global.RANKING_PRO_CONFIG;
    if (!cfg?.SUPABASE_URL || !cfg?.SUPABASE_ANON_KEY) {
      throw new Error('Configure config.js com SUPABASE_URL e SUPABASE_ANON_KEY.');
    }
    return cfg;
  }

  function baseHeaders() {
    const { SUPABASE_ANON_KEY } = getConfig();
    return {
      apikey: SUPABASE_ANON_KEY,
      Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
      'Content-Type': 'application/json'
    };
  }

  async function fetchRest(path, options = {}) {
    const { SUPABASE_URL } = getConfig();
    const url = SUPABASE_URL.replace(/\/$/, '') + path;
    const res = await fetch(url, {
      ...options,
      headers: { ...baseHeaders(), ...(options.headers || {}) }
    });

    const text = await res.text();
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = text;
      }
    }

    if (!res.ok) {
      const msg = data?.message || data?.error || data?.hint || res.statusText || 'Erro na API';
      throw new Error(typeof msg === 'string' ? msg : JSON.stringify(msg));
    }

    return data;
  }

  async function rpc(fnName, params = {}) {
    return fetchRest('/rest/v1/rpc/' + fnName, {
      method: 'POST',
      body: JSON.stringify(params)
    });
  }

  async function select(table, query = '') {
    const q = query.startsWith('?') ? query : '?' + query;
    return fetchRest('/rest/v1/' + table + q);
  }

  global.RankingProAPI = {
    getConfig,
    fetchRest,
    rpc,
    select
  };
})(window);