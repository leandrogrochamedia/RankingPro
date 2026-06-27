// Ranking Pro — Supabase REST client (Proofly)

(function (global) {
  'use strict';

  function getConfig() {
    const cfg = global.RANKING_PRO_CONFIG || {};
    const url = cfg.SUPABASE_URL || global.SUPABASE_URL;
    const key = cfg.SUPABASE_ANON_KEY || cfg.SUPABASE_KEY || global.SUPABASE_KEY;
    if (!url || !key) {
      throw new Error('Configure config.js com SUPABASE_URL e SUPABASE_ANON_KEY.');
    }
    return { SUPABASE_URL: url, SUPABASE_ANON_KEY: key };
  }

  function baseHeaders(extra) {
    const { SUPABASE_ANON_KEY } = getConfig();
    return {
      apikey: SUPABASE_ANON_KEY,
      Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
      'Content-Type': 'application/json',
      ...(extra || {})
    };
  }

  async function fetchRest(path, options = {}) {
    const { SUPABASE_URL } = getConfig();
    const url = SUPABASE_URL.replace(/\/$/, '') + path;
    const res = await fetch(url, {
      ...options,
      headers: { ...baseHeaders(options.prefer ? { Prefer: options.prefer } : {}), ...(options.headers || {}) }
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
      const msg = data?.message || data?.error || data?.hint || data?.code || res.statusText || 'Erro na API';
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

  async function insert(table, row) {
    const data = await fetchRest('/rest/v1/' + table, {
      method: 'POST',
      prefer: 'return=representation',
      body: JSON.stringify(row)
    });
    return Array.isArray(data) ? data[0] : data;
  }

  async function update(table, query, patch) {
    const q = query.startsWith('?') ? query : '?' + query;
    const data = await fetchRest('/rest/v1/' + table + q, {
      method: 'PATCH',
      prefer: 'return=representation',
      body: JSON.stringify(patch)
    });
    return Array.isArray(data) ? data[0] : data;
  }

  global.RankingProAPI = {
    getConfig,
    fetchRest,
    rpc,
    select,
    insert,
    update
  };
})(window);