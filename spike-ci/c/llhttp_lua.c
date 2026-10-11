/* Throwaway OQ-6 binding: parse one HTTP/1.1 request buffer into a Lua table. */
#include <string.h>
#include <stdlib.h>
#include <lua.h>
#include <lauxlib.h>
#include "llhttp.h"

typedef struct { char *p; size_t n, cap; } db_t;
static void db_add(db_t *b, const char *s, size_t n){ if(b->n+n>b->cap){ b->cap=(b->n+n)*2+64; b->p=realloc(b->p,b->cap);} memcpy(b->p+b->n,s,n); b->n+=n; }
typedef struct {
  lua_State *L;
  int tbl, hdrs;
  db_t url, name, value, body;
  int in_name, in_value, in_url, in_body, nh, complete;
} ctx_t;

static void flush_header(ctx_t *c) {
  if (c->in_name && c->in_value) {
    lua_State *L = c->L;
    lua_createtable(L, 2, 0);
    lua_pushlstring(L, c->name.p, c->name.n); c->name.n=0; lua_rawseti(L, -2, 1);
    lua_pushlstring(L, c->value.p, c->value.n); c->value.n=0; lua_rawseti(L, -2, 2);
    lua_rawseti(L, c->hdrs, ++c->nh);
    c->in_name = c->in_value = 0;
  }
}
static int on_url(llhttp_t *p, const char *at, size_t n) {
  ctx_t *c = p->data; if (!c->in_url) { c->in_url = 1; }
  db_add(&c->url, at, n); return 0; }
static int on_hname(llhttp_t *p, const char *at, size_t n) {
  ctx_t *c = p->data;
  if (c->in_value) flush_header(c);
  if (!c->in_name) { c->in_name = 1; }
  db_add(&c->name, at, n); return 0; }
static int on_hvalue(llhttp_t *p, const char *at, size_t n) {
  ctx_t *c = p->data; c->in_value = 1; db_add(&c->value, at, n); return 0; }
static int on_hdone(llhttp_t *p) {
  ctx_t *c = p->data; lua_State *L = c->L;
  flush_header(c);
  if (c->in_url) { lua_pushlstring(L, c->url.p, c->url.n); lua_setfield(L, c->tbl, "target"); c->in_url = 0; }
  lua_pushstring(L, llhttp_method_name(llhttp_get_method(p))); lua_setfield(L, c->tbl, "method");
  lua_pushfstring(L, "%d.%d", p->http_major, p->http_minor); lua_setfield(L, c->tbl, "version");
  return 0; }
static int on_body(llhttp_t *p, const char *at, size_t n) {
  ctx_t *c = p->data; if (!c->in_body) { c->in_body = 1; }
  db_add(&c->body, at, n); return 0; }
static int on_complete(llhttp_t *p) {
  ctx_t *c = p->data;
  if (c->in_body) { lua_pushlstring(c->L, c->body.p, c->body.n); lua_setfield(c->L, c->tbl, "body"); c->in_body = 0; }
  c->complete = 1; return HPE_PAUSED; }

/* parse(buf) -> table | nil, err, consumed */
static int l_parse(lua_State *L) {
  size_t len; const char *s = luaL_checklstring(L, 1, &len);
  llhttp_t p; llhttp_settings_t st; ctx_t c; memset(&c, 0, sizeof c);
  llhttp_settings_init(&st);
  st.on_url = on_url; st.on_header_field = on_hname; st.on_header_value = on_hvalue;
  st.on_headers_complete = on_hdone; st.on_body = on_body; st.on_message_complete = on_complete;
  llhttp_init(&p, HTTP_REQUEST, &st); p.data = &c; c.L = L;
  lua_settop(L, 1);
  lua_newtable(L); c.tbl = lua_gettop(L);
  lua_newtable(L); c.hdrs = lua_gettop(L);
  lua_pushvalue(L, c.hdrs); lua_setfield(L, c.tbl, "headers");
  llhttp_errno_t e = llhttp_execute(&p, s, len);
  free(c.url.p); free(c.name.p); free(c.value.p); free(c.body.p);
  if (e == HPE_PAUSED && c.complete) { lua_settop(L, c.tbl); return 1; }
  if (e == HPE_OK) { lua_pushnil(L); lua_pushliteral(L, "incomplete"); return 2; }
  lua_pushnil(L); lua_pushstring(L, llhttp_errno_name(e)); return 2;
}
int luaopen_llhttp_lua(lua_State *L) { lua_pushcfunction(L, l_parse); return 1; }
