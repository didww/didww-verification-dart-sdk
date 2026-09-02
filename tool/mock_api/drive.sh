#!/usr/bin/env bash
# Drives every route, every auth scheme and every callback outcome of the mock API
# with curl. Starts and stops its own server.
#
#   tool/mock_api/drive.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOCK="$ROOT/tool/mock_api/bin/mock_api.dart"
PUBLIC="Authorization: Application demo-key"
BASIC="Authorization: Basic $(printf 'demo-key:demo-secret' | base64)"

pass=0
fail=0
STATUS=""
BODY=""

start_mock() {
  local log ttl="${1:-300}"
  log="$(mktemp)"
  dart run "$MOCK" --port 0 --ttl "$ttl" >"$log" 2>&1 &
  MOCK_PID=$!
  for _ in $(seq 1 100); do
    BASE="$(sed -n 's#^mock api on \(http://[^/]*\).*#\1#p' "$log")"
    [ -n "$BASE" ] && break
    sleep 0.1
  done
  if [ -z "${BASE:-}" ]; then
    echo "the mock did not start:"; cat "$log"; exit 1
  fi
  API="$BASE/api/v1"
}

stop_mock() { [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null; }
trap stop_mock EXIT

req() { # method url [header] [body]
  local out
  if [ -n "${4:-}" ]; then
    out="$(curl -s -w '\n%{http_code}' -X "$1" "$2" -H "${3:-X-None: 1}" \
      -H 'Content-Type: application/json' -d "$4")"
  else
    out="$(curl -s -w '\n%{http_code}' -X "$1" "$2" -H "${3:-X-None: 1}")"
  fi
  STATUS="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

expect() { # label status [pattern]
  if [ "$STATUS" != "$2" ] || { [ -n "${3:-}" ] && ! grep -q "$3" <<<"$BODY"; }; then
    printf 'FAIL %-52s status=%s want=%s %s\n     %s\n' "$1" "$STATUS" "$2" "${3:-}" "$BODY"
    fail=$((fail + 1))
  else
    printf 'ok   %s\n' "$1"
    pass=$((pass + 1))
  fi
}

id_of() { sed -n 's/.*"id":"\([^"]*\)".*/\1/p' <<<"$BODY"; }

start_mock

echo "--- health and routing"
req GET "$BASE/_health"; expect 'health' 200 '"ok":true'
req GET "$BASE/api/v1/nope" "$PUBLIC"; expect 'unknown path is not_found' 404 'not_found'

echo "--- the three auth dispatch rules"
req GET "$API/verifications/x"; expect 'no credentials' 401 'unauthorized'
req GET "$API/verifications/x" "Authorization: Application demo-key:signature"
expect 'a colon after the key selects request signing' 401 'unauthorized'
req GET "$API/verifications/x" "Authorization: Basic $(printf 'demo-key:wrong' | base64)"
expect 'wrong basic secret' 401 'unauthorized'
req GET "$API/verifications/x" "Authorization: Bearer demo-key"; expect 'unknown scheme' 401 'unauthorized'
req GET "$API/verifications/no-such-id" "$PUBLIC"; expect 'public auth reaches the route' 404 'not_found'
req GET "$API/verifications/no-such-id" "$BASIC"; expect 'basic auth reaches the route' 404 'not_found'

echo "--- validation"
req POST "$API/verifications" "$PUBLIC" '{}'
expect 'missing data object' 400 'parameter_missing'
req POST "$API/verifications" "$PUBLIC" '{"data":{}}'
expect 'two failures yield two elements' 422 'destination_blank.*delivery_method_blank'
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"12","delivery_method":"sms"}}'
expect 'short destination' 422 'destination_invalid'
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491511234567","delivery_method":"telepathy"}}'
expect 'unknown channel' 422 'delivery_method_inclusion'
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491511234567","delivery_method":"sms","sms":{"app_hash":"tooshort"}}}'
expect 'malformed app hash' 422 'app_hash_invalid'
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491511234567","delivery_method":"sms","sms":{"languages":["not a tag"]}}}'
expect 'malformed language tag' 422 'languages_invalid'

echo "--- sms: start, read, report"
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491511111111","delivery_method":"sms","sms":{"languages":["en-US"],"app_hash":"A1b2C3d4E5f"}}}'
expect 'sms start' 201 '"status":"pending"'
expect 'the sms block names the chosen language' 201 '"language":"en-US"'
grep -q '"app_hash":"A1b2C3d4E5f"' <<<"$BODY" && echo 'ok   the app hash is echoed' && pass=$((pass + 1))
SMS_ID="$(id_of)"
req GET "$API/verifications/$SMS_ID" "$PUBLIC"; expect 'read by id' 200 '"status":"pending"'
req GET "$API/verifications/by_number/491511111111" "$PUBLIC"; expect 'read by number' 200 "$SMS_ID"
req PUT "$API/verifications/$SMS_ID" "$PUBLIC" '{"data":{"delivery_method":"sms","code":""}}'
expect 'a blank code' 422 'code_blank'
req PUT "$API/verifications/$SMS_ID" "$PUBLIC" '{"data":{"delivery_method":"callout","code":"123456"}}'
expect 'the wrong channel' 422 'delivery_method_invalid'
req PUT "$API/verifications/$SMS_ID" "$PUBLIC" '{"data":{"delivery_method":"sms","code":"000000"}}'
expect 'a wrong code' 422 'code_invalid'
req PUT "$API/verifications/$SMS_ID" "$PUBLIC" '{"data":{"delivery_method":"sms","code":"123456"}}'
expect 'the right code' 200 '"status":"verified"'
req PUT "$API/verifications/$SMS_ID" "$PUBLIC" '{"data":{"delivery_method":"sms","code":"123456"}}'
expect 'reporting a verified verification' 422 'already_verified'

echo "--- callout"
req POST "$API/verifications" "$BASIC" '{"data":{"destination":"491512222222","delivery_method":"callout"}}'
expect 'a callout start carries no sms block' 201 '"status":"pending"'
grep -q '"sms"' <<<"$BODY" && { echo 'FAIL callout must carry no sms block'; fail=$((fail + 1)); } \
  || { echo 'ok   callout carries no sms block'; pass=$((pass + 1)); }
req PUT "$API/verifications/by_number/491512222222" "$BASIC" '{"data":{"delivery_method":"callout","code":"123456"}}'
expect 'report by number' 200 '"status":"verified"'

req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491513333333","delivery_method":"callout"}}'
expect 'callout start' 201 '"delivery_method":"callout"'
expect 'a callout with no languages gets the default' 201 '"callout":{"language":"en-US"}'
req PATCH "$API/verifications/by_number/491513333333" "$PUBLIC" '{"data":{"delivery_method":"callout","code":"123456"}}'
expect 'PATCH is accepted as well as PUT' 200 '"status":"verified"'

echo "--- callout: language choice"
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491513333001","delivery_method":"callout","callout":{"languages":["pt-BR"]}}}'
expect 'a servable tag is used' 201 '"callout":{"language":"pt-BR"}'
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491513333002","delivery_method":"callout","callout":{"languages":["pt-br"]}}}'
expect 'the echoed tag is canonical, not the spelling sent' 201 '"callout":{"language":"pt-BR"}'
# The whole point of the echo: an unservable tag is accepted, so nothing but
# this field says the announcement is in another language than the one asked for.
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491513333003","delivery_method":"callout","callout":{"languages":["sq-AL","de-DE"]}}}'
expect 'the first servable tag wins over an earlier unservable one' 201 '"callout":{"language":"de-DE"}'
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491513333004","delivery_method":"callout","callout":{"languages":["sq-AL"]}}}'
expect 'an unservable tag falls back rather than failing' 201 '"callout":{"language":"en-US"}'
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491513333005","delivery_method":"callout","callout":{"languages":["not a tag"]}}}'
expect 'a malformed callout tag is rejected' 422 'languages_invalid'
# Only the block named after the delivery method is read, so a broken block for
# another channel is ignored rather than failing a paid start.
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491513333006","delivery_method":"callout","sms":{"languages":["not a tag"],"app_hash":"tooshort"},"callout":{"languages":["de-DE"]}}}'
expect 'a broken sms block on a callout start is ignored' 201 '"callout":{"language":"de-DE"}'

echo "--- supersede on a second start"
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491514444444","delivery_method":"sms"}}'
FIRST="$(id_of)"
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491514444444","delivery_method":"sms"}}'
expect 'the second start is live' 201 '"status":"pending"'
req GET "$API/verifications/$FIRST" "$PUBLIC"
expect 'the first start was superseded' 200 '"status":"failed".*"error_code":"superseded"'

echo "--- attempts are the server's decision"
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491515555555","delivery_method":"sms"}}'
ATTEMPTS="$(id_of)"
for _ in 1 2; do
  req PUT "$API/verifications/$ATTEMPTS" "$PUBLIC" '{"data":{"delivery_method":"sms","code":"000000"}}'
done
expect 'the second wrong code' 422 'code_invalid'
req PUT "$API/verifications/$ATTEMPTS" "$PUBLIC" '{"data":{"delivery_method":"sms","code":"000000"}}'
expect 'the third wrong code exhausts the attempts' 422 'too_many_attempts'
req GET "$API/verifications/$ATTEMPTS" "$PUBLIC"
expect 'and the verification is terminal' 200 '"status":"failed".*"error_code":"too_many_attempts"'

echo "--- the callback decides"
req POST "$API/verifications" "Authorization: Application demo-key" '{"data":{"destination":"491516666666","delivery_method":"sms"}}'
expect 'an allowing callback' 201 '"status":"pending"'
req POST "$API/verifications" "Authorization: Application deny-key" '{"data":{"destination":"491516666667","delivery_method":"sms"}}'
expect 'a refusing callback' 201 '"status":"denied".*"error_code":"denied_by_callback"'
req POST "$API/verifications" "Authorization: Application broken-key" '{"data":{"destination":"491516666668","delivery_method":"sms"}}'
expect 'a callback that answers badly' 201 '"status":"denied".*denied_invalid_callback_response'
req POST "$API/verifications" "Authorization: Application no-callback-key" '{"data":{"destination":"491516666669","delivery_method":"sms"}}'
expect 'an application with no callback url' 201 '"status":"denied".*denied_missing_callback_url'

echo "--- expiry is synthesised on read"
stop_mock
start_mock 1
req POST "$API/verifications" "$PUBLIC" '{"data":{"destination":"491517777777","delivery_method":"sms"}}'
EXPIRING="$(id_of)"
sleep 2
req GET "$API/verifications/$EXPIRING" "$PUBLIC"
expect 'a lapsed deadline reads as expired' 200 '"status":"expired".*"error_code":"expired"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
