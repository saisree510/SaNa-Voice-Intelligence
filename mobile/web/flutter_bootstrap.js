{{flutter_js}}
{{flutter_build_config}}

(async () => {
  // Earlier GitHub Pages releases registered Flutter's generated service
  // worker. Remove it so authentication and project data never come from a
  // stale cached application bundle after a deployment.
  if ('serviceWorker' in navigator) {
    const wasControlled = navigator.serviceWorker.controller !== null;
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));

    if (wasControlled && sessionStorage.getItem('soul-sw-cleared') !== 'true') {
      sessionStorage.setItem('soul-sw-cleared', 'true');
      window.location.reload();
      return;
    }
  }

  sessionStorage.removeItem('soul-sw-cleared');
  await _flutter.loader.load();
})();
