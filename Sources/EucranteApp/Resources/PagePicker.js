(() => {
  const items = new Map();
  const clean = (raw) => {
    try {
      const u = new URL(raw, location.href);
      if (!['https:', 'http:'].includes(u.protocol) || u.username || u.password || u.href.length > 8192) return null;
      const host = u.hostname.toLowerCase();
      if (host === 'youtu.be' || host === 'youtube.com' || host.endsWith('.youtube.com')) {
        const id = host === 'youtu.be' ? u.pathname.slice(1).split('/')[0] :
          u.searchParams.get('v') || (/^\/(shorts|embed|live)\/([^/]+)/.exec(u.pathname) || [])[2];
        if (!id || !/^[\w-]{11}$/.test(id)) return null;
        return 'https://www.youtube.com/watch?v=' + id;
      }
      u.hash = '';
      return u.href;
    } catch { return null; }
  };
  const mediaLink = (url) => /\.(mp4|m4a|mp3|webm|mov|wav|flac|m3u8)(\?|$)/i.test(url) ||
    /https?:\/\/([^/]+\.)?(youtube\.com|youtu\.be|vimeo\.com|soundcloud\.com|bandcamp\.com|tiktok\.com|instagram\.com|twitter\.com|x\.com|dailymotion\.com)\//i.test(url);
  let truncated = false;
  function add(raw, title) {
    const url = clean(raw);
    if (!url || items.has(url)) return;
    if (items.size >= 100) { truncated = true; return; }
    const item = { url, title: String(title || '').trim().replace(/\s+/g, ' ').slice(0, 240) };
    if (JSON.stringify([...items.values(), item]).length > 55000) { truncated = true; return; }
    items.set(url, item);
  }
  add(location.href, document.title);
  for (const node of document.querySelectorAll('video,audio,video source,audio source,iframe[src]')) {
    const url = node.currentSrc || node.src;
    if (url && (node.tagName !== 'IFRAME' || mediaLink(url))) add(url, node.title || document.title);
  }
  for (const node of document.querySelectorAll('a[href]')) {
    if (mediaLink(node.href)) add(node.href, node.title || node.getAttribute('aria-label') || node.textContent);
  }
  const payload = { page: location.href, title: document.title.slice(0, 240), items: [...items.values()], truncated };
  if (!payload.items.length) { alert('No media links found on this page.'); return; }
  location.href = 'eucrante://page?payload=' + encodeURIComponent(JSON.stringify(payload));
})();
