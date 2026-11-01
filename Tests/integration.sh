#!/bin/sh
# Integration tests against the installed app. Run after ./build.sh.
# They start and stop real sessions, so they refuse to run while a session or caffeinate is active.
# Lid tests run only when the lid permission is granted.
set -u
L="$HOME/.local/bin/lidless"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   $1"; }
bad()  { fail=$((fail+1)); echo "FAIL $1"; }
expect() { # expect <description> <want exit> <command...>
  d=$1; want=$2; shift 2
  out=$("$@" 2>&1); got=$?
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (exit $got, want $want): $out"; fi
}
sd() { pmset -g | awk '/SleepDisabled/{print $2}'; }
wait_until() { n=0; while ! eval "$1" && [ $n -lt "$2" ]; do sleep 1; n=$((n+1)); done; eval "$1"; }

[ -x "$L" ] || { echo "Run ./build.sh first."; exit 1; }
if $L status --json | grep -qE '"(active|caffeinated)" : true'; then
  echo "A session or caffeinate is active. Stop it first: lidless stop; lidless caffeinate off"; exit 1
fi

expect "start with limits"              0 $L start --duration 1m --battery-floor 5 --thermal-stop critical --by t1
expect "second agent joins"             0 $L start --duration 2m --by t2
$L status --json | grep -q '"t2"' && ok "status lists both holders" || bad "status lists both holders"
expect "stop by someone else fails"     1 $L stop --by nobody
expect "first agent leaves"             0 $L stop --by t1
$L status --json | grep -q '"active" : true' && ok "session continues for t2" || bad "session continues for t2"
expect "last agent leaves"              0 $L stop --by t2
$L status --json | grep -q '"active" : false' && ok "session ended" || bad "session ended"
expect "stop when none is active"       0 $L stop
expect "duration above 24h refused"     2 $L start --duration 25h
expect "bad thermal refused"            2 $L start --thermal-stop lukewarm
expect "caffeinate on"                  0 $L caffeinate on --flags di --for 2s
pgrep -fq "caffeinate -di -t 2" && ok "caffeinate runs with the flags" || bad "caffeinate runs with the flags"
wait_until '! pgrep -x caffeinate >/dev/null' 10 && ok "caffeinate ends at its time limit" || bad "caffeinate ends at its time limit"
expect "bad caffeinate flags refused"   2 $L caffeinate on --flags xyz

if $L status --json | grep -q '"lidPermission" : true' && [ "$(sd)" = 0 ]; then
  expect "lid session"                  0 $L start --duration 1m --lid --by t1
  [ "$(sd)" = 1 ] && ok "SleepDisabled is 1 during the session" || bad "SleepDisabled is 1 during the session"
  pid=$($L status --json | awk -F': ' '/"pid"/{gsub(/,/,"",$2);print $2}')
  kill -9 "$pid"
  wait_until '[ "$(sd)" = 0 ]' 15 && ok "crash restores SleepDisabled 0" || bad "crash restores SleepDisabled 0"
  expect "app restarts on the next command" 0 $L stop
else
  echo "skip lid tests (no lid permission, or SleepDisabled is already 1)"
fi

# displays-on is the hidden command of the display watchdog. It must not change a display that is on,
# and it must accept an id that does not exist. It never turns a display off, so this test is safe.
before=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c Resolution)
expect "displays-on without ids"        0 $L displays-on
expect "displays-on with an unknown id" 0 $L displays-on 999999
after=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c Resolution)
[ "$before" = "$after" ] && ok "displays-on changes no display" || bad "displays-on changed the displays ($before -> $after)"
echo "$pass passed, $fail failed"
[ $fail = 0 ]
