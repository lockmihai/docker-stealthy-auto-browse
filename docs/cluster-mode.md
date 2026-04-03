# Cluster Mode

Run a fleet of browser instances behind HAProxy with automatic queuing, sticky sessions, and Redis cookie sync. Useful when you need to handle concurrent requests — each browser handles one request at a time, and the proxy queues the rest until a slot opens.

## What You Get

- **10 browser containers** (configurable) behind a single entry point on port 8080
- **HAProxy queue-proxy** that holds incoming requests when all instances are busy, instead of returning errors
- **Sticky sessions** via `INSTANCEID` cookie — once a client is routed to a browser instance, it stays there
- **Redis cookie sync** — cookies set on one instance propagate to all others via PubSub. New instances joining the cluster load existing cookies from Redis on startup

## Quick Start

```bash
docker compose -f docker-compose.cluster.yml up -d
```

This starts Redis, 10 browser containers, and the HAProxy queue-proxy. The entry point is `http://localhost:8080` — same API as the single-container mode.

### Scale Up

```bash
# Scale to 20 instances (also update MAX_CONCURRENT to match)
docker compose -f docker-compose.cluster.yml up -d --scale browser=20
MAX_CONCURRENT=20 docker compose -f docker-compose.cluster.yml up -d queue-proxy
```

### Watch the Queue

```bash
docker compose -f docker-compose.cluster.yml logs -f queue-proxy
```

## Environment Variables

| Variable         | Default          | What It Does                                                                                                                                              |
| ---------------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `REDIS_URL`      | —                | Redis connection string. Set automatically in cluster mode (`redis://redis:6379`). Set this on standalone containers to join them to a Redis sync cluster. |
| `QUEUE_TIMEOUT`  | `300`            | Seconds a request will wait in the queue before HAProxy returns a 503. Increase for long-running tasks.                                                   |
| `MAX_CONCURRENT` | `10`             | Number of browser instances HAProxy expects. Must match the actual scale count. HAProxy uses this to build the server list.                               |
| `TZ`             | `America/New_York` | Timezone for all browser instances. Set to match your IP's geographic location.                                                                         |

## HAProxy Queue-Proxy

HAProxy sits in front of all browser instances and enforces a concurrency limit of 1 per instance (`maxconn 1` per server). When all instances are handling requests, new requests queue up instead of failing. The `leastconn` balancing algorithm routes to whichever instance has been idle longest.

### Endpoints

| Endpoint           | What It Does                                                            |
| ------------------ | ----------------------------------------------------------------------- |
| `/__queue/health`  | Returns `{"status":"ok"}` — use this for load balancer health checks.  |
| `/__queue/status`  | Returns `{"status":"ok","max_concurrent":N}` — queue configuration.    |

### Stats Dashboard

HAProxy exposes a stats dashboard on port **8081**. Open `http://localhost:8081/` to see live traffic, queue depth, server health, and request rates per instance.

## Sticky Sessions

HAProxy sets an `INSTANCEID` cookie on every response, containing the name of the server that handled the request (e.g. `browser1`, `browser3`).

**Not sending `INSTANCEID` is intentional for self-contained requests.** If you POST a full script — navigate to a site, type something, press enter, get the HTML — HAProxy picks any free browser and the whole thing happens in one shot. You don't care which instance handled it, and not sending the cookie means you get proper load balancing across the fleet.

**Send `INSTANCEID` when you have ongoing state across separate requests.** If you logged in on a browser and need to continue the session across multiple API calls, send the cookie back so HAProxy routes you to the same instance every time. The browser's tab state, local variables, and any non-synced storage live in that specific container.

**Let HAProxy assign an instance, then stick to it:**

```bash
# First request — capture the INSTANCEID from the response
INSTANCEID=$(curl -sS -D - -o /dev/null -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -d '{"action": "goto", "url": "https://example.com"}' \
  | grep -i 'set-cookie:.*INSTANCEID' \
  | sed 's/.*INSTANCEID=\([^;]*\).*/\1/' | tr -d '\r')

# Subsequent requests — send INSTANCEID to route to the same browser
curl -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -H "Cookie: INSTANCEID=$INSTANCEID" \
  -d '{"action": "get_text"}'
```

**Target a specific instance directly:**

```bash
curl -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -H 'Cookie: INSTANCEID=browser3' \
  -d '{"action": "get_text"}'
```

## Redis Cookie Sync

When `REDIS_URL` is set, all cookie operations sync across instances via Redis PubSub:

- `set_cookie` publishes the cookie to the `SABROWSE:UPDATE` channel. All other instances receive it immediately and apply it to their browser context.
- `delete_cookies` publishes a clear event. All instances clear their cookies.
- On startup, each instance loads all existing cookies from Redis (`SABROWSE:COOKIES` hash) before handling any requests.

This means an auth session (like a login cookie) set on `browser1` is immediately available in `browser2`, `browser3`, etc., without any navigation or re-login. If you log into a site on one instance, all instances are logged in.

**Practical consequence:** run a single login sequence on any instance, and the whole fleet is authenticated.

## docker-compose.cluster.yml Overview

```yaml
services:
  redis:
    image: redis:7-alpine

  browser:
    image: psyb0t/stealthy-auto-browse:latest
    scale: 10
    environment:
      - TZ=${TZ:-America/New_York}
      - REDIS_URL=redis://redis:6379
      # - PROXY_URL=http://user:pass@host:port

  queue-proxy:
    image: haproxy:lts-alpine
    environment:
      - QUEUE_TIMEOUT=${QUEUE_TIMEOUT:-300}
      - MAX_CONCURRENT=${MAX_CONCURRENT:-10}
    ports:
      - "8080:8080"
      - "8081:8081"
```

All services share a `browse` Docker network. Browser containers are not exposed directly — all traffic goes through the queue-proxy.
