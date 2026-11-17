# Authentication

What is worth taking from João Angelo, *Authentication Survival Guide* (Auth0, 2017), for
strata's control plane and the tenant token. Index: [README.md](README.md).

## Verdict

**A short primer (43 pages), written for web applications that log users in through a browser.**
It gives the vocabulary and a handful of rules that hold for any token system. It does not tell
you how to build an issuer, and it says so: its advice for that is "use something that exists".

| Part of the guide | For strata |
|---|---|
| Concepts, glossary | **Take the vocabulary**, mapped to strata's parts below |
| OAuth 2.0, OpenID Connect | **Take the roles and the split**: OAuth 2.0 is for access to an API, OpenID Connect is for logging a person in |
| SAML, WS-Federation, OpenID, OAuth 1.0a | Know the names. They matter only if a customer needs enterprise single sign-on, and then through an identity provider, not our own code |
| Tokens: formats and types | **Take the rules**: by-value and by-reference, access and refresh and ID tokens, lifetimes, audience |
| Token storage in browsers and mobile apps | Applies only to a web console, if strata gets one. One line below is general: the issuer stores hashes |
| Cookies | Applies only to a web console |
| Troubleshooting, tools | Take one point: captured traffic contains credentials |
| Pitfalls | TLS everywhere; logout with a delegated login |

What the guide does **not** cover, and strata needs. Each needs another source and a design
before code:

- signing keys: algorithm choice, rotation, how verifiers learn of a new or withdrawn key
- revoking a by-value token before it expires
- machine callers: a tenant's program is not a person at a browser
- authorization: what a token's permissions mean and where they are checked
- tenant isolation: that a token for one tenant can never reach another tenant's data
- how a token travels with Valkey commands, which is not HTTP
- storing secrets and credentials on the server side
- rate limits on login and token requests

## Vocabulary, in strata's terms

| Term | Meaning | In strata |
|---|---|---|
| Authentication | Proving who is calling | The control plane does it |
| Authorization | Deciding what the caller may do | The control plane decides and writes it into the token; the gateway and the owner enforce it |
| Identity provider | The authoritative source of identities | The control plane, or an external provider it delegates to for people |
| Authorization server | Issues access tokens | The control plane's token issuer |
| Resource server | Accepts access tokens and serves the resource | The gateway (and the owner behind it); the control plane's own API |
| Client application | Asks for access | A tenant's program; an operator's tool |
| Bearer token | Whoever holds it can use it | The tenant token |
| By-value token | Carries its claims; verified with a signature and no lookup | The tenant token (a JWT) |
| By-reference token | A random string; the issuer looks it up | A refresh token or an API key |
| Digital signature | Proves who made a message and that it was not changed | What the gateway checks with the control plane's public keys |

## Decide before you build

| Question | Notes |
|---|---|
| Who are the callers: people, programs, or both? | They need different flows. The guide covers people. |
| Do we build the issuer, or run an existing one? | The guide's advice is to use an existing one. Building one means reading the OAuth 2.0 threat model (RFC 6819) first. |
| How does a person log in to manage a tenant? | OpenID Connect against an identity provider, not passwords we store. |
| What does a program present to get a tenant token? | A long-lived credential, used only at the issuer. |
| How long does a tenant token live? | Short: minutes to hours. It is the only limit on a leaked token until revocation exists. |
| What is the audience of each token? | One per resource server. A verifier rejects any other. |
| What claims does the token carry? | Identity and permissions; nothing secret. |
| What happens to live tokens when access is withdrawn? | Wait for expiry, or a revocation path. Decide which, and what it costs. |
| Is an API key enough for this caller? | If all we need is to know who is calling, it is far simpler than OAuth 2.0. |

## Rules

**Protocols**

- **Do not invent a protocol or a token format.** Use OAuth 2.0 for access to APIs and OpenID
  Connect for logging people in.
- **OAuth 2.0 is a framework, not a protocol.** It leaves choices open. For anything we
  integrate with, read the provider's documentation as well as RFC 6749.
- **Prefer an existing authorization server to writing one.** If we write one, it is a design
  with its own threat model.
- **All of it runs over TLS.** No token or credential ever crosses a connection without it.

**Token types**

- **An access token is for one API.** The client treats it as opaque; only the resource server
  reads it.
- **An access token is not proof of login.** It says "the holder may call this API", not "this
  application just authenticated this person". Logging a person in uses an ID token.
- **Every token names its audience, and every verifier rejects a token issued for a different
  audience.** Without this, a token issued for one service can be replayed at another.
- **Access tokens are short-lived.** A bearer token cannot be told apart from a stolen copy, so
  its lifetime is the size of a leak.
- **The long-lived credential goes only to the issuer.** A refresh token (or an API key used to
  get tokens) is issued and consumed by the authorization server alone. That keeps it off every
  other connection, and gives the issuer the one place where it can refuse: revocation.
- **Do not replace the pair with one long-lived access token.** It is simpler and it removes
  both protections above.
- **A long-lived credential is given only to a client that can store it safely.** Not to code
  running in a browser.

**Validation**

- **Validate a token with a maintained library, completely.** JWT looks simple enough to parse by
  hand; it is not. For an ID token the checks are the list in OpenID Connect Core §3.1.3.7:
  issuer, audience, signature, algorithm, expiry, and the rest.
- **By-value where the verifier must not call the issuer; by-reference where issuer and verifier
  are the same service.** A by-value token costs no lookup and cannot be withdrawn early. A
  by-reference token is smaller and can be withdrawn at once.
- **A token's claims are readable by anyone who holds it.** Signed is not encrypted. Put no
  secret in a claim.

**Storage**

- **The issuer stores a hash of each credential it issues, never the value.** It only needs to
  check that a presented value matches.
- **Captured requests contain credentials.** A network trace, a HAR file or a debug log of an
  auth flow holds tokens and may hold passwords. Never ask for one without saying so, and never
  log a token or an `Authorization` header.

**Delegated login**

- **Delegating login removes work and adds some.** Password policy, reset and brute-force
  defence become the provider's. Logout gets harder: ending our session does not end the
  session at the provider, so the next login may need no password. Say what "log out" does.

**If strata gets a web console**

- Token storage in a browser is a choice between exposures: web storage is open to script
  injection; a cookie is sent automatically and so needs request-forgery protection. The guide
  prefers web storage with the `Authorization` header, because script injection must be
  prevented in any case. Read its storage section when the console is designed.

## In strata

Already decided, in [the container diagram](../diagrams/02-containers.md) and
[the gateway diagram](../diagrams/03-components-gateway.md): the control plane owns auth and
issues the tenant token, a JWT. The gateway holds no credentials; it verifies the signature and
the expiry with public keys it caches from the control plane, and reads the tenant and its
permissions from the claims. If the control plane is down, tokens stay verifiable until they
expire.

In the guide's terms:

- **The tenant token is a by-value bearer access token.** That is the right kind: the gateway
  must not call the control plane per request. The cost is that it cannot be withdrawn before it
  expires, so its lifetime is the main security setting. The lifetime is **(not set yet)**.
- **Audience.** The tenant token's audience is the data plane. The control plane's own API is a
  different audience and does not accept tenant tokens, and the gateway does not accept tokens
  issued for the control plane API. Claim names and values are **(not set yet)**.
- **Getting a tenant token.** A tenant's program is a machine caller. It presents a long-lived
  credential to the control plane over HTTPS and receives a short-lived tenant token. The
  long-lived credential never goes to the gateway. Its form (an API key, or OAuth 2.0 client
  credentials) is **(not set yet)**.
- **The control plane stores only hashes** of the long-lived credentials it issues, and shows a
  credential's value once, when it is created.
- **Operators and tenant admins are people.** They log in through OpenID Connect against an
  identity provider. strata stores no passwords. Which provider, and whether the control plane
  runs an existing authorization server or its own issuer, is **(not set yet)**.
- **Revocation.** Withdrawing a credential stops new tokens at once; tokens already issued live
  until they expire. Whether the gateway also needs a deny list is **(not set yet)**.
- **Expiry needs a clock.** The gateway checks expiry with the injected clock
  ([simulation-testing.md](simulation-testing.md)). The allowance for clock difference between
  the control plane and a gateway is **(not set yet)**.
- **A token is input.** It is validated at the edge and never asserted on
  ([rules.md §2](rules.md)). A bad token is a client error and never counts against a breaker.
- **Tokens and credentials are never logged** and never used as a metric label. Log the tenant
  and a token identifier.
- **Signing keys, rotation and the token's place on the Valkey protocol** are outside the guide
  and are **(not set yet)**. Formats and claims carry a version
  ([production-readiness.md](production-readiness.md)).

## Tests

- A token with a wrong signature, a wrong issuer, a wrong audience or a past expiry is refused,
  each with the documented error. On and off points for the expiry, with the injected clock.
- A token signed with an algorithm the verifier does not expect is refused, including "none".
- A control plane API token is refused at the gateway, and a tenant token is refused at the
  control plane API.
- A tenant token for one tenant cannot reach another tenant's data, whatever the command.
- The long-lived credential is refused at the gateway.
- After a credential is withdrawn, no new token is issued for it.
- The credential store holds no credential value (search it after issuing).
- Tokens and credentials do not appear in logs, errors or metrics (search the captured output).
- Fuzz the token parser: no input panics, and nothing malformed is accepted.
- With the control plane down, a gateway keeps accepting valid tokens and refuses expired ones.

## Smells

- A token parsed or verified with our own code.
- A verifier that does not check the audience.
- One long-lived token used on every request.
- A credential stored in a form that can be shown again.
- An access token used as proof of who logged in.
- A secret in a claim.
- A token in a log line, a URL or a metric label.
- A password stored by strata.
- "Log out" that only deletes the local session.
- An auth endpoint reachable without TLS.
