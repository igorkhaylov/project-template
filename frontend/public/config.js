// Development runtime config, served as-is by the Vite dev server.
// In the Docker image this URL is answered by nginx instead (nginx/default.conf.template),
// which renders the same object from APP_API_BASE_URL / APP_ENVIRONMENT at container start.
window.__APP_CONFIG__ = {
  apiBaseUrl: "",
  environment: "dev",
};
