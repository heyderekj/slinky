import { onRequestPost as __api_ask_js_onRequestPost } from "/Users/heyderekj/slinky/site/functions/api/ask.js"
import { onRequestGet as __index_ts_onRequestGet } from "/Users/heyderekj/slinky/site/functions/index.ts"
import { onRequest as ___middleware_js_onRequest } from "/Users/heyderekj/slinky/site/functions/_middleware.js"

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
  {
      routePath: "/",
      mountPath: "/",
      method: "",
      middlewares: [___middleware_js_onRequest],
      modules: [],
    },
  ]