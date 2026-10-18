/* Spike only: a listening TCP socket with SO_REUSEPORT, returned as an fd for uv.tcp_open. */
#include <lua.h>
#include <lauxlib.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>

static int rp_listen(lua_State *L) {
  const char *host = luaL_checkstring(L, 1);
  int port = (int)luaL_checkinteger(L, 2);
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one);
  struct sockaddr_in a;
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_port = htons((unsigned short)port);
  inet_pton(AF_INET, host, &a.sin_addr);
  if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, 1024) != 0) {
    close(fd);
    return luaL_error(L, "rp.listen failed");
  }
  lua_pushinteger(L, fd);
  return 1;
}

int luaopen_rp(lua_State *L) {
  lua_newtable(L);
  lua_pushcfunction(L, rp_listen);
  lua_setfield(L, -2, "listen");
  return 1;
}
