# Ledger HTTP API — Requirements (Stage 0, v2: APPROVED 2026-11-22)

> This document is R20 of [`../REQUIREMENTS.md`](../REQUIREMENTS.md) (Ledger v3) and part of it. It
> is plain English, with IDs H1–H16, literal examples E1–E35 and verification items V1–V8.
>
> **Approved by the user on 2026-11-22.** The decisions are recorded in §10. H-D2 was decided as
> (b): amounts, balances and totals are JSON **strings of base-10 digits** (`"1000"`), not JSON
> numbers. Every other decision went as recommended. v2 of this document applies H-D2 to H8, H9,
> H10, H11 and to examples E1–E35, with the `Content-Length` values recomputed. Changes from here
> on need a new sign-off.

## 1. What it is
An HTTP server, written in TypeScript and run by Node.js, that gives HTTP access to every Ledger
command. Requests and responses have JSON bodies. The server is **transport only**:

```
client --HTTP/JSON--> server.ts --one line per command--> ledger <dir> serve --> LeanKV files
       <--HTTP/JSON--           <--one answer line-------        (Lean, proven core)
```

The server turns each request into one line of Ledger's line protocol (R18), writes it to a single
long-lived `ledger <dir> serve` process, reads the one answer line, and turns that line into the
HTTP response. Every ledger rule is decided by the Lean ledger: valid names and amounts, balances
and limits, the order in which errors are checked, and durability. The server decides only what a
line cannot express: the route, the HTTP method, the body size, and whether the body is a JSON
object of the right shape (H9).

## 2. Running the server
- **H1. Command.**
  `node examples/ledger/http/server.ts <dir> [--port N] [--host ADDR] [--ledger PATH]`
  - `<dir>` is the ledger directory, as for the CLI. It is created if missing.
  - `--port` defaults to `8080`. `--port 0` picks a free port.
  - `--host` defaults to `127.0.0.1`, so by default only this machine can connect (H-D8).
  - `--ledger` defaults to the built CLI, `examples/ledger/impl/.lake/build/bin/ledger`, located
    relative to `server.ts`.
  - Node.js 24 or newer runs the `.ts` file directly. It strips the types, so there is no build
    step, no compiler and no npm package. The code therefore uses only TypeScript syntax that Node
    can strip (no `enum`, no `namespace`). The server and its tests import only `node:` modules.
    There is no `package.json` with dependencies and no `node_modules`.
- **H2. Startup.** The server starts `ledger <dir> serve` and accepts no connection until the
  ledger has opened its store.
  - If the ledger reports `ERR CORRUPT offset p`, the server writes that line to stderr and exits
    3 without listening.
  - If the ledger reports an I/O error, or the address cannot be listened on, the server writes
    the reason to stderr and exits 4.
  - Bad command-line arguments: a usage message on stderr, exit 2.
  - When it is ready, the server prints exactly one line to stdout,
    `listening on http://ADDR:PORT`, with the actual port (useful with `--port 0`).
- **H3. Shutdown.** On SIGINT or SIGTERM the server stops accepting connections. It finishes the
  requests already sent to the ledger, closes the ledger's input (serve then exits 0), and exits 0.
  Requests not yet sent to the ledger get `503` `{"error":"UNAVAILABLE"}`. A `kill -9` at any
  moment is safe for the data: durability is the ledger's (H14).
- **H4. Fail-stop.** If the ledger answers `ERR IO`, the request that caused it gets `500`
  `{"error":"IO"}`. As in R16, that command may or may not have been applied. Every request still
  waiting gets `503` `{"error":"UNAVAILABLE"}`, and the server exits 4. If the ledger process
  exits unexpectedly, or answers a line the server cannot map (H10), the request in flight gets
  `500` `{"error":"INTERNAL"}`, the waiting ones get `503`, and the server exits 5. The server
  never restarts the ledger by itself (see H-D7).

## 3. Requests
- **H5. Routes.** One route per Ledger command. Every route uses `POST` (see H-D1).

  | Route | Ledger command | Body fields (all required, no others) |
  |---|---|---|
  | `POST /open` | `open NAME` | `name` |
  | `POST /deposit` | `deposit NAME AMOUNT` | `name`, `amount` |
  | `POST /withdraw` | `withdraw NAME AMOUNT` | `name`, `amount` |
  | `POST /transfer` | `transfer FROM TO AMOUNT` | `from`, `to`, `amount` |
  | `POST /balance` | `balance NAME` | `name` |
  | `POST /accounts` | `accounts` | none |
  | `POST /total` | `total` | none |

  The request target must be exactly one of these seven paths. Anything else is `404`
  `{"error":"NOT_FOUND"}`. That includes a trailing slash, a query string, or a different case.
  Any method other than `POST` on one of these paths is `405` `{"error":"METHOD_NOT_ALLOWED"}`
  with the header `Allow: POST`.
- **H6. Body.** The body must be a JSON object whose keys are exactly the route's fields. An empty
  body counts as `{}`, so `/accounts` and `/total` can be called with no body. The request's
  `Content-Type` header is not checked. If a key appears twice, the last one counts, as with
  JavaScript's `JSON.parse`. The body may be at most 65,536 bytes. A larger body is `413`
  `{"error":"TOO_LARGE"}`.
- **H7. Names** (`name`, `from`, `to`) must be JSON strings. The server sends a name to the ledger
  as its UTF-8 bytes, unchanged, when the name is not empty and contains no space and no control
  character (U+0000–U+001F, U+007F).

  A name that is empty or contains such a character cannot be written as one word of a line. The
  server sends the word `?` in its place. This changes no answer. Every name in that group is
  invalid under R2, and so is `?`, and `BAD_NAME` is the first check of every command that takes a
  name (§3). So the ledger answers `ERR BAD_NAME`, exactly as the model does for the original
  name (H-D4). Parsing comes before every rule. If the same request also has an amount that is
  not plain digits, the answer is `ERR USAGE`, as the CLI would give.
- **H8. Amounts** (`amount`) must be JSON strings, in base-10 digits: `"1250"` means 1250 cents
  (H-D2). A JSON number such as `1250` has the wrong type, so it is `400` `USAGE` (H9.4,
  example E27). The server never converts an amount to a JavaScript number, because 2⁶³ − 1 is
  larger than a JavaScript number holds exactly. It sends the string's text to the ledger
  unchanged, when the string is not empty and contains no space and no control character
  (U+0000–U+001F, U+007F). Examples: `"1250"`, `"0"`, `"9223372036854775808"`, `"12.50"`, `"-5"`.

  Any other string (empty, or containing a space or control character, such as `"1 000"`) cannot
  be written as one word of a line. The server sends the word `?` in its place, exactly as for
  names (H7). Such a string is not plain digits, and neither is `?`. Parsing the line comes before
  every rule check, so the ledger answers `ERR USAGE` for both, the same answer the CLI gives
  (R4, R14). See example E28.

  The ledger decides everything else, as R4 says. Anything but plain digits is `ERR USAGE`
  (`400`). Plain digits whose value is `0` or more than `MAX` are `ERR BAD_AMOUNT` (`422`).
- **H9. What the server decides itself.** The server answers, without contacting the ledger, only
  these cases, checked in this order:
  1. an unknown path: `404` `NOT_FOUND`;
  2. a method other than `POST`: `405` `METHOD_NOT_ALLOWED`;
  3. a body over 65,536 bytes: `413` `TOO_LARGE`;
  4. a body that is not valid JSON, is not an object, lacks a field, has an extra field, or has a
     field of the wrong JSON type: `400` `USAGE`. Every field is a JSON string. That includes
     `amount`, so an amount given as a JSON number is the wrong type.

  Everything else goes to the ledger, and the answer comes from the ledger.

## 4. Responses
- **H10. Answer to response.** The response depends only on the ledger's answer line, and for
  `OK` on the route.

  | Ledger answer line | Status | Body |
  |---|---|---|
  | `OK` (from `/open`) | `201 Created` | `{"ok":true}` |
  | `OK` (from `/transfer`) | `200 OK` | `{"ok":true}` |
  | `BALANCE b` | `200 OK` | `{"balance":"b"}` |
  | `ACCOUNTS n N1 B1 … Nn Bn` | `200 OK` | `{"accounts":[{"name":"N1","balance":"B1"},…]}` (`[]` when n = 0), in the ledger's order |
  | `TOTAL t` | `200 OK` | `{"total":"t"}` |
  | `ERR BAD_NAME` | `422 Unprocessable Entity` | `{"error":"BAD_NAME"}` |
  | `ERR BAD_AMOUNT` | `422 Unprocessable Entity` | `{"error":"BAD_AMOUNT"}` |
  | `ERR SAME_ACCOUNT` | `422 Unprocessable Entity` | `{"error":"SAME_ACCOUNT"}` |
  | `ERR UNKNOWN_ACCOUNT n` | `404 Not Found` | `{"error":"UNKNOWN_ACCOUNT","account":"n"}` |
  | `ERR ACCOUNT_EXISTS` | `409 Conflict` | `{"error":"ACCOUNT_EXISTS"}` |
  | `ERR INSUFFICIENT_FUNDS` | `409 Conflict` | `{"error":"INSUFFICIENT_FUNDS"}` |
  | `ERR BALANCE_LIMIT` | `409 Conflict` | `{"error":"BALANCE_LIMIT"}` |
  | `ERR USAGE` | `400 Bad Request` | `{"error":"USAGE"}` |
  | `ERR IO` | `500 Internal Server Error` | `{"error":"IO"}` (then H4) |
  | any other line, or no line | `500 Internal Server Error` | `{"error":"INTERNAL"}` (then H4) |

  Responses the server makes itself (H3, H4, H9):

  | Case | Status | Body |
  |---|---|---|
  | malformed body (H9.4) | `400 Bad Request` | `{"error":"USAGE"}` |
  | unknown path | `404 Not Found` | `{"error":"NOT_FOUND"}` |
  | method not `POST` | `405 Method Not Allowed` + `Allow: POST` | `{"error":"METHOD_NOT_ALLOWED"}` |
  | body too large | `413 Payload Too Large` | `{"error":"TOO_LARGE"}` |
  | server stopping or stopped | `503 Service Unavailable` | `{"error":"UNAVAILABLE"}` |

  **The rule behind the status codes** (H-D3):
  - `422`: the request can never succeed as written (a bad name or amount, a transfer to itself).
  - `404`: an account it names does not exist.
  - `409`: it is refused because of the ledger's current state (the account exists, the funds are
    insufficient, the balance limit would be passed).
  - `400`: the request is not a well-formed command.
  - `5xx`: the server or the ledger has failed.
- **H11. Numbers in responses.** `b`, `B1…` and `t` are JSON strings holding exactly the base-10
  digits of the answer line, for example `"balance":"700"` (H-D2). They are copied as text and
  never converted to a number. They are exact at every size, including a balance of `MAX` and a
  total above 2⁶³ − 1 (R5). Example E21 has `"9223372036854776507"`. Any client, in any language,
  reads them without losing precision.
- **H12. Format.** Every response has `Content-Type: application/json` and a `Content-Length`.
  The body is compact JSON: keys in the order shown, no spaces, no trailing newline. Node.js also
  sends `Date`, `Connection` and `Keep-Alive` headers. These are not part of the contract, and the
  literal examples leave them out.

## 5. Order, concurrency and durability
- **H13. One at a time, in arrival order.** The server sends requests to the ledger one at a time,
  in the order their bodies finished arriving, across all connections. It sends the next line only
  after the previous answer has come back. Each response is made from the answer to its own
  request's line. So the API behaves as if the commands ran one after another, in that order. This
  is exactly the sequence the model runs.
- **H14. Durability.** The server sends a response that came from the ledger only after the ledger
  has written the answer line. For a change, the ledger writes that line only after the change is
  durable (R14, R18). So R15 and R16 hold for HTTP: a command answered `2xx` survives any crash. If
  the connection drops before the response arrives, the command may or may not have been applied,
  like the in-flight command of R16. Retrying it can apply it twice (see §9).
- **H15. Exclusive use.** While the server runs, nothing else may use `<dir>`. That includes no
  `ledger <dir> …` CLI command. This is trusted, not enforced (R18, §6).
- **H16. Names in answers.** In `UNKNOWN_ACCOUNT n` and `ACCOUNTS …`, every name is a valid name
  (R2), so it is ASCII without spaces. The server copies it into a JSON string as it is.

## 6. Literal examples
Each example is one HTTP exchange against a server started on a **new, empty** `<dir>`. E1–E35
run in order on the same server, so the ledger carries over from one to the next. E1–E18 are
Ledger's model examples 1–18 (§3 of `../REQUIREMENTS.md`), in the same order. E19–E35 add the
balance limit on a transfer, a total above 2⁶³ − 1, and every response the server makes itself.

Each example says which protocol line the server sends to the ledger, and the ledger's answer.
Some say "answered by the server alone": nothing is sent, and the ledger does not change. The
replay test (V4) sends each request **byte for byte** as shown, with CRLF line endings on the wire.
The one exception is the port in the `Host` header, which is the test server's actual port. The
server ignores `Host`. The test requires the exact status line, the exact `Content-Type`, `Content-Length` and (E33) `Allow`
headers, and the exact body.

Two cases cannot be shown literally. They are tested in V5:
- A body of 65,537 bytes or more: `413` `{"error":"TOO_LARGE"}`.
- `ERR IO` from the ledger: `500` `{"error":"IO"}`, then H4.

**E1** (model example 1). Protocol line `open alice` → `OK`.

```http
POST /open HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 16

{"name":"alice"}
```
```http
HTTP/1.1 201 Created
Content-Type: application/json
Content-Length: 11

{"ok":true}
```

**E2** (model example 2). Protocol line `open alice` → `ERR ACCOUNT_EXISTS`.

```http
POST /open HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 16

{"name":"alice"}
```
```http
HTTP/1.1 409 Conflict
Content-Type: application/json
Content-Length: 26

{"error":"ACCOUNT_EXISTS"}
```

**E3** (model example 3). Protocol line `open bob` → `OK`.

```http
POST /open HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 14

{"name":"bob"}
```
```http
HTTP/1.1 201 Created
Content-Type: application/json
Content-Length: 11

{"ok":true}
```

**E4** (model example 4). Protocol line `deposit alice 1000` → `BALANCE 1000`.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 32

{"name":"alice","amount":"1000"}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 18

{"balance":"1000"}
```

**E5** (model example 5). Protocol line `transfer alice bob 300` → `OK`.

```http
POST /transfer HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 42

{"from":"alice","to":"bob","amount":"300"}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 11

{"ok":true}
```

**E6** (model example 6). Protocol line `balance alice` → `BALANCE 700`.

```http
POST /balance HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 16

{"name":"alice"}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 17

{"balance":"700"}
```

**E7** (model example 7). Protocol line `balance bob` → `BALANCE 300`.

```http
POST /balance HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 14

{"name":"bob"}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 17

{"balance":"300"}
```

**E8** (model example 8). Protocol line `transfer bob alice 301` → `ERR INSUFFICIENT_FUNDS`.

```http
POST /transfer HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 42

{"from":"bob","to":"alice","amount":"301"}
```
```http
HTTP/1.1 409 Conflict
Content-Type: application/json
Content-Length: 30

{"error":"INSUFFICIENT_FUNDS"}
```

**E9** (model example 9). Protocol line `transfer alice carol 1` → `ERR UNKNOWN_ACCOUNT carol`.

```http
POST /transfer HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 42

{"from":"alice","to":"carol","amount":"1"}
```
```http
HTTP/1.1 404 Not Found
Content-Type: application/json
Content-Length: 45

{"error":"UNKNOWN_ACCOUNT","account":"carol"}
```

**E10** (model example 10). Protocol line `transfer alice bob 0` → `ERR BAD_AMOUNT`.

```http
POST /transfer HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 40

{"from":"alice","to":"bob","amount":"0"}
```
```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json
Content-Length: 22

{"error":"BAD_AMOUNT"}
```

**E11** (model example 11). Protocol line `transfer alice alice 5` → `ERR SAME_ACCOUNT`.

```http
POST /transfer HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 42

{"from":"alice","to":"alice","amount":"5"}
```
```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json
Content-Length: 24

{"error":"SAME_ACCOUNT"}
```

**E12** (model example 12). Protocol line `withdraw bob 300` → `BALANCE 0`.

```http
POST /withdraw HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 29

{"name":"bob","amount":"300"}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15

{"balance":"0"}
```

**E13** (model example 13). Protocol line `withdraw bob 1` → `ERR INSUFFICIENT_FUNDS`.

```http
POST /withdraw HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 27

{"name":"bob","amount":"1"}
```
```http
HTTP/1.1 409 Conflict
Content-Type: application/json
Content-Length: 30

{"error":"INSUFFICIENT_FUNDS"}
```

**E14** (model example 14). Protocol line `deposit carol 5` → `ERR UNKNOWN_ACCOUNT carol`.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 29

{"name":"carol","amount":"5"}
```
```http
HTTP/1.1 404 Not Found
Content-Type: application/json
Content-Length: 45

{"error":"UNKNOWN_ACCOUNT","account":"carol"}
```

**E15** (model example 15). Protocol line `open bad/name` → `ERR BAD_NAME`.

```http
POST /open HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 19

{"name":"bad/name"}
```
```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json
Content-Length: 20

{"error":"BAD_NAME"}
```

**E16** (model example 16). Protocol line `deposit alice 9223372036854775807` → `ERR BALANCE_LIMIT`.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 47

{"name":"alice","amount":"9223372036854775807"}
```
```http
HTTP/1.1 409 Conflict
Content-Type: application/json
Content-Length: 25

{"error":"BALANCE_LIMIT"}
```

**E17** (model example 17). Protocol line `accounts` → `ACCOUNTS 2 alice 700 bob 0`.

```http
POST /accounts HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 2

{}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 76

{"accounts":[{"name":"alice","balance":"700"},{"name":"bob","balance":"0"}]}
```

**E18** (model example 18). Protocol line `total` → `TOTAL 700`.

```http
POST /total HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 2

{}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15

{"total":"700"}
```

**E19**. Protocol line `deposit bob 9223372036854775807` → `BALANCE 9223372036854775807`.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 45

{"name":"bob","amount":"9223372036854775807"}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 33

{"balance":"9223372036854775807"}
```

**E20**. Protocol line `transfer alice bob 1` → `ERR BALANCE_LIMIT`.

```http
POST /transfer HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 40

{"from":"alice","to":"bob","amount":"1"}
```
```http
HTTP/1.1 409 Conflict
Content-Type: application/json
Content-Length: 25

{"error":"BALANCE_LIMIT"}
```

**E21**. Protocol line `total` → `TOTAL 9223372036854776507`.

```http
POST /total HTTP/1.1
Host: 127.0.0.1:8080

```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 31

{"total":"9223372036854776507"}
```

**E22**. Protocol line `accounts` → `ACCOUNTS 2 alice 700 bob 9223372036854775807`.

```http
POST /accounts HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 2

{}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 94

{"accounts":[{"name":"alice","balance":"700"},{"name":"bob","balance":"9223372036854775807"}]}
```

**E23**. Protocol line `deposit alice 9223372036854775808` → `ERR BAD_AMOUNT`.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 47

{"name":"alice","amount":"9223372036854775808"}
```
```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json
Content-Length: 22

{"error":"BAD_AMOUNT"}
```

**E24**. Protocol line `open ?` → `ERR BAD_NAME`.

```http
POST /open HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 14

{"name":"a b"}
```
```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json
Content-Length: 20

{"error":"BAD_NAME"}
```

**E25**. Protocol line `open ?` → `ERR BAD_NAME`.

```http
POST /open HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 11

{"name":""}
```
```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json
Content-Length: 20

{"error":"BAD_NAME"}
```

**E26**. Protocol line `deposit alice 12.50` → `ERR USAGE`.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 33

{"name":"alice","amount":"12.50"}
```
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 17

{"error":"USAGE"}
```

**E27**. Answered by the server alone; nothing is sent to the ledger.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 27

{"name":"alice","amount":5}
```
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 17

{"error":"USAGE"}
```

**E28**. Protocol line `withdraw alice ?` → `ERR USAGE`.

```http
POST /withdraw HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 33

{"name":"alice","amount":"1 000"}
```
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 17

{"error":"USAGE"}
```

**E29**. Answered by the server alone; nothing is sent to the ledger.

```http
POST /deposit HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 16

{"name":"alice"}
```
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 17

{"error":"USAGE"}
```

**E30**. Answered by the server alone; nothing is sent to the ledger.

```http
POST /balance HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 26

{"name":"alice","extra":1}
```
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 17

{"error":"USAGE"}
```

**E31**. Answered by the server alone; nothing is sent to the ledger.

```http
POST /balance HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 10

{"name":7}
```
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 17

{"error":"USAGE"}
```

**E32**. Answered by the server alone; nothing is sent to the ledger.

```http
POST /balance HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 8

{"name":
```
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Content-Length: 17

{"error":"USAGE"}
```

**E33**. Answered by the server alone; nothing is sent to the ledger.

```http
GET /total HTTP/1.1
Host: 127.0.0.1:8080

```
```http
HTTP/1.1 405 Method Not Allowed
Allow: POST
Content-Type: application/json
Content-Length: 30

{"error":"METHOD_NOT_ALLOWED"}
```

**E34**. Answered by the server alone; nothing is sent to the ledger.

```http
POST /close HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 16

{"name":"alice"}
```
```http
HTTP/1.1 404 Not Found
Content-Type: application/json
Content-Length: 21

{"error":"NOT_FOUND"}
```

**E35**. Protocol line `balance alice` → `BALANCE 700`.

```http
POST /balance HTTP/1.1
Host: 127.0.0.1:8080
Content-Type: application/json
Content-Length: 16

{"name":"alice"}
```
```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 17

{"balance":"700"}
```

## 7. Ledger-side pieces this needs (no change to the frozen spec)
- `ledger <dir> serve` (R18) and `ledger-oracle` (R19), built by `examples/ledger/impl/` next to
  the existing `ledger` executable.
- One shared module for the line protocol (parse a line, print an answer), used by the CLI, serve
  and the oracle. The CLI's output must stay byte for byte as it is. `impl/test.sh` (74 CLI
  checks and the kill tests) must pass unchanged.
- `impl/tests/gen_commands.py`: random protocol lines for the differential tests (V1, V2). It must
  reach every command, every error code, `ERR USAGE` (amounts `12.50`, `-5`, `1e3`, `+5`, wrong
  word counts), and the limits: amounts `0`, `1`, `MAX`, `MAX+1`; names of 1, 64 and 65 bytes; a
  balance at `MAX`; a total above `MAX`.
- The frozen files in `spec.lock` (`ledger-v1`) are not touched, and `mil.json` is not changed.

## 8. Verification: proven, tested, trusted
- **Proven** (unchanged from Ledger v2): the reference model R1–R13, the layout and refinement,
  fast `pick` = `pickRef`, and crash consistency on LeanKV's model file system
  (`LedgerImpl.crash_consistent`). Nothing in serve mode or in the HTTP server is proven.
- **V1. Serve against the model.**
  `python3 tools/difftest.py --sut 'ledger {dir} serve' --oracle ledger-oracle --gen
  impl/tests/gen_commands.py` with at least 30 runs × 200 commands. Every answer must be equal.
- **V2. HTTP against the model.** Run the same differential test with `--sut` set to an
  **adapter** (`http/adapter.ts`). For each run, the adapter starts the HTTP server on the fresh
  directory with `--port 0`. It turns each protocol line into the HTTP request of H5–H8 (each
  amount word becomes a JSON string with the same text) and the response back into an answer
  line (the inverse of H10). At least 30 runs × 200 commands,
  reaching every route and every ledger answer.
- **V3. Planted bug.** A deliberately wrong mapping in the server makes V2 fail. For example,
  `/transfer` with `from` and `to` swapped, or `INSUFFICIENT_FUNDS` reported as `BALANCE_LIMIT`.
  This shows the test can fail.
- **V4. Literal replay.** E1–E35 are replayed verbatim against a fresh server, and the exact
  status, headers and body of each are checked. This catches a mapping bug that is mirrored in
  both the server and the adapter, which V2 alone would miss.
- **V5. HTTP-only cases:** a body over the limit (`413`); startup on a corrupt directory (exit 3,
  no file changed); `ERR IO` handling (H4), where the test can arrange it; shutdown (H3).
- **V6. HTTP kill test** (H-D9). Send random requests, `kill -9` the server and the ledger at a
  random moment, restart on the same directory, and check that the ledger equals the model after
  the `2xx`-acknowledged commands, plus possibly the one in flight.
- **V7. Ledger unchanged.** `impl/test.sh` passes, and `mil audit examples/ledger/mil.json` prints
  AUDIT PASSED under the unchanged `ledger-v1` lock.
- **V8. No dependencies.** The server, adapter and tests import only `node:` modules. There is no
  `node_modules` and no npm install.

**What this does not show (stated in `TRUST.md`).** The differential tests (V1, V2) compare only
what a protocol line can express. The model never sees the HTTP-only cases: routes, methods, body
size, malformed JSON and wrong JSON types (an amount sent as a number), and the `?` stand-in for
names and amount strings that cannot be written on a line. Those are covered by the literal
examples and V5 only.

The line parser/printer is shared by serve mode and the oracle (R19). A bug in it, for example
reading an amount wrongly, would be the same on both sides and invisible to V1 and V2. The CLI
tests (`impl/test.sh`) and the literal examples (V4), whose expected answers were written from the
requirements, are what cover it. The planned `TRUST.md` statuses:

| Component | Status |
|---|---|
| Lean core | Proven (unchanged rows) |
| Serve mode | Tested against the model (V1) |
| HTTP API | Tested against the model (V2, V3, V4) |
| HTTP-only behaviour, the TypeScript server, the adapter, Node.js and its HTTP parser, the line parser/printer, OS sockets, exclusive use of `<dir>` | Trusted |

None of these is ever "Proven".

## 9. Non-goals
- Authentication, TLS, CORS, rate limiting. The default address is `127.0.0.1`. Exposing the
  server beyond this machine is the operator's choice and risk.
- Idempotency keys or safe retries. A retried request after a dropped connection can apply twice
  (H14).
- `GET` routes, URLs that name accounts, pagination of `/accounts`, HTTP/2, streaming.
- Several ledgers per server, or several servers on one `<dir>`.
- Restarting the ledger process automatically after a failure (H4).
- Performance targets. Requests are serialised (H13), and nothing is benchmarked.

## 10. Decisions (user, 2026-11-22)
- **Decided H-D1: one `POST` route per command** (H5), with every argument in the JSON body. It
  needs no URL decoding and reaches every valid name, including `.` and `..`. Resource-style URLs
  were rejected.
- **Decided H-D2: amounts, balances and totals are JSON strings of base-10 digits**
  (`"amount":"1000"`, `"balance":"700"`; H8, H11). This avoids JavaScript's 53-bit precision loss
  at every size up to `MAX` (2⁶³ − 1) and beyond for totals. It also means the transport layer
  never has to parse a JSON number's raw source text. A JSON number in place of an amount is
  `400` `USAGE`. (The recommendation had been JSON numbers.)
- **Decided H-D3:** the status rule of H10. `422` for a request that can never succeed, `404` for
  a missing account, `409` for a refusal caused by the current state, `400` for a malformed
  request, `5xx` for failures.
- **Decided H-D4:** a name (and, by the same rule, an amount string; H8) that cannot be written as
  one word is sent as the stand-in word `?`. The ledger still makes the decision.
- **Decided H-D5:** an unknown extra field is `400` `USAGE`.
- **Decided H-D6:** error bodies carry the code only, plus `account` for `UNKNOWN_ACCOUNT`.
- **Decided H-D7:** fail-stop after an I/O or internal failure (H4). The server never restarts
  the ledger itself.
- **Decided H-D8:** listen on `127.0.0.1:8080` by default, with no authentication.
- **Decided H-D9:** include the HTTP kill test (V6), with 2 runs × 300 requests.
- **Decided H-D10:** `/open` answers `201 Created` on success.
- **Decided, `TRUST.md` boundary:** as planned in §8. It separates three things: the Lean-proven
  core, model and substrate guarantees; the differential and literal tests against the model; and
  the trusted components. The trusted components include the TypeScript transport layer and the
  shared line-protocol parser/printer, which every comparison with the oracle also uses (a blind
  spot, §8).
