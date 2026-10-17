import { onRequestPost as __api_ask_js_onRequestPost } from "/Users/heyderekj/slinky/site/functions/api/ask.js"
import { onRequestGet as __index_ts_onRequestGet } from "/Users/heyderekj/slinky/site/functions/index.ts"

export const routes = [
    {
      routePath: "/api/ask",
      mountPath: "/api",
      method: "POST",
      middlewares: [],
      modules: [__api_ask_js_onRequestPost],
    },
  {
      routePath: "/",
      mountPath: "/",
      method: "GET",
      middlewares: [],
      modules: [__index_ts_onRequestGet],
    },
  ]