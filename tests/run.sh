#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo_dir/revenuecat-control
test_root=$(mktemp -d)

cleanup() {
  [[ -n ${test_root:-} && -d $test_root ]] && rm -rf -- "$test_root"
}
trap cleanup EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_jq() {
  local file=$1 expression=$2 message=$3
  jq -e "$expression" "$file" >/dev/null || fail_test "$message"
}

export HOME=$test_root/home
export XDG_CONFIG_HOME=$test_root/config
export XDG_CACHE_HOME=$test_root/cache
export TMPDIR=$test_root/tmp
export FAKE_SECRET_STATE=$test_root/secrets
export FAKE_CURL_LOG=$test_root/curl.log
export PATH=$repo_dir/tests/fake-bin:/usr/bin:/bin
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$TMPDIR" "$FAKE_SECRET_STATE"
: >"$FAKE_CURL_LOG"

export FAKE_PROJECTS_JSON
FAKE_PROJECTS_JSON=$(jq -cn \
  --arg unsafeName $'Café \033]0;spoof\007 \u202e <img src="http://127.0.0.1/probe"> & Project 😀' \
  '{items:[
    {id:"one",name:$unsafeName,icon_url:"file:///etc/passwd"},
    {id:"two",name:"Second Project",icon_url:"https://cdn.example.test/two.png"}
  ]}')

printf 'sk_one\n' | "$helper" configure one >/dev/null
printf 'sk_two\n' | "$helper" configure two >/dev/null

config_file=$XDG_CONFIG_HOME/revenue-pulse/config.json
cache_file=$XDG_CACHE_HOME/revenue-pulse/metrics.json
project_one_cache=$XDG_CACHE_HOME/revenue-pulse/projects/one.json

assert_jq "$config_file" '.projects[] | select(.id == "one") | (.name | contains("Café") and contains("😀"))' \
  'legitimate Unicode project-name content was not preserved'
assert_jq "$config_file" '[.projects[].name] | all(test("[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069]") | not)' \
  'unsafe terminal or bidi controls remained in configuration'
assert_jq "$config_file" '.projects[] | select(.id == "one") | .iconUrl == ""' \
  'non-HTTPS project icon was retained'
assert_jq "$config_file" '[.projects[].name] | all(test("[<>&]") | not)' \
  'project-name markup remained active'
assert_jq "$config_file" '[.projects[].iconUrl] | all(. == "")' \
  'remote project icon metadata remained active'

config_stat_before=$(stat -c '%Y:%Z:%s' "$config_file")
: >"$FAKE_CURL_LOG"
"$helper" fetch one >"$test_root/one.json"
config_stat_after=$(stat -c '%Y:%Z:%s' "$config_file")
[[ $config_stat_before == "$config_stat_after" ]] || fail_test 'unchanged metadata rewrote configuration'
request_count=$(wc -l <"$FAKE_CURL_LOG")
[[ $request_count -eq 7 ]] || fail_test "single-project refresh issued $request_count requests instead of overview plus six charts: $(tr '\n' ';' <"$FAKE_CURL_LOG")"
! grep -q '/projects/two/' "$FAKE_CURL_LOG" || fail_test 'single-project refresh contacted another project'
! grep -q '/v2/projects?' "$FAKE_CURL_LOG" || fail_test 'fresh metadata was fetched again before its TTL'
[[ -f $project_one_cache ]] || fail_test 'project cache was not written'
[[ -z $(find "$TMPDIR" -mindepth 1 -print -quit) ]] || fail_test 'temporary API workspace was not removed'

# A refresh that began with old metadata must not overwrite a later reconnect.
metadata_barrier=$test_root/metadata-fetch
FAKE_BLOCK_OVERVIEW_FILE=$metadata_barrier "$helper" fetch one >"$test_root/stale-metadata-fetch.json" &
metadata_fetch_pid=$!
for (( wait_index = 0; wait_index < 1000; wait_index++ )); do
  [[ -e $metadata_barrier.ready ]] && break
  sleep 0.01
done
[[ -e $metadata_barrier.ready ]] || fail_test 'metadata race fetch did not reach its barrier'
reconnected_projects=$(jq -cn '{items:[
  {id:"one",name:"Reconnected Name",icon_url:"https://cdn.example.test/one.png"},
  {id:"two",name:"Second Project",icon_url:"https://cdn.example.test/two.png"}
]}')
printf 'sk_one_new\n' | FAKE_PROJECTS_JSON=$reconnected_projects "$helper" configure one >/dev/null
: >"$metadata_barrier.release"
wait "$metadata_fetch_pid"
assert_jq "$config_file" '.projects[] | select(.id == "one") | .name == "Reconnected Name"' \
  'stale fetch metadata overwrote a concurrent reconnect'
export FAKE_PROJECTS_JSON=$reconnected_projects

"$helper" settings currency EUR >/dev/null
"$helper" cached >"$test_root/eur-cached.json"
assert_jq "$test_root/eur-cached.json" '.currency == "EUR" and .ok == false and ([.projects[].metrics | length] | add) == 0' \
  'old USD values were relabelled as EUR'
"$helper" settings currency USD >/dev/null

: >"$FAKE_CURL_LOG"
FAKE_RATE_LIMIT_CHART=1 "$helper" fetch one >"$test_root/rate-limited.json"
request_count=$(wc -l <"$FAKE_CURL_LOG")
[[ $request_count -eq 2 ]] || fail_test "rate-limited chart refresh issued $request_count requests instead of stopping after the first chart"
now_ms=$(( $(date +%s) * 1000 ))
assert_jq "$test_root/rate-limited.json" ".projects[] | select(.id == \"one\") | .retryAfterAt > $now_ms" \
  'Retry-After was not retained in the project snapshot'
: >"$FAKE_CURL_LOG"
"$helper" fetch one >"$test_root/retry-blocked.json"
[[ ! -s $FAKE_CURL_LOG ]] || fail_test 'a manual refresh ignored an active Retry-After window'

: >"$FAKE_CURL_LOG"
FAKE_RATE_LIMIT_OVERVIEW=1 "$helper" fetch two >"$test_root/overview-rate-limited.json"
request_count=$(wc -l <"$FAKE_CURL_LOG")
[[ $request_count -eq 1 ]] || fail_test "rate-limited overview issued $request_count requests instead of stopping immediately"

# Configure obeys the same stop policy and persists the server's full backoff.
: >"$FAKE_CURL_LOG"
limited_before_ms=$(( $(date +%s) * 1000 ))
printf 'sk_limited\n' | FAKE_RATE_LIMIT_OVERVIEW=1 FAKE_RETRY_AFTER=172800 \
  "$helper" configure limited >/dev/null 2>"$test_root/configure-limited.err"
request_count=$(wc -l <"$FAKE_CURL_LOG")
[[ $request_count -eq 1 ]] || fail_test "rate-limited configure issued $request_count requests instead of stopping immediately"
limited_retry_file=$XDG_CACHE_HOME/revenue-pulse/projects/limited.retry.json
assert_jq "$limited_retry_file" ".retryAfterAt >= ($limited_before_ms + 172790000)" \
  'a long Retry-After deadline was shortened'
: >"$FAKE_CURL_LOG"
"$helper" fetch limited >"$test_root/configure-retry-blocked.json"
[[ ! -s $FAKE_CURL_LOG ]] || fail_test 'configured project ignored its persisted Retry-After window'

# Retry state survives a concurrent currency/context change even though the
# metric result itself is intentionally incompatible with the new currency.
printf 'sk_context\n' | "$helper" configure context >/dev/null 2>&1
context_barrier=$test_root/context-fetch
: >"$FAKE_CURL_LOG"
FAKE_BLOCK_OVERVIEW_FILE=$context_barrier FAKE_RATE_LIMIT_OVERVIEW=1 \
  "$helper" fetch context >"$test_root/context-rate-limited.json" &
context_fetch_pid=$!
for (( wait_index = 0; wait_index < 1000; wait_index++ )); do
  [[ -e $context_barrier.ready ]] && break
  sleep 0.01
done
[[ -e $context_barrier.ready ]] || fail_test 'context race fetch did not reach its barrier'
"$helper" settings currency EUR >/dev/null
: >"$context_barrier.release"
wait "$context_fetch_pid"
: >"$FAKE_CURL_LOG"
"$helper" fetch context >"$test_root/context-retry-blocked.json"
[[ ! -s $FAKE_CURL_LOG ]] || fail_test 'currency change discarded an in-flight Retry-After deadline'
"$helper" settings currency USD >/dev/null

if printf 'y\n' | FAKE_CLEAR_FAIL=1 "$helper" project remove one >"$test_root/remove.out" 2>"$test_root/remove.err"; then
  fail_test 'project removal succeeded after keyring deletion failure'
fi
assert_jq "$config_file" '[.projects[].id] | index("one") != null' 'failed removal discarded the project identifier'
[[ -f $project_one_cache && -f $cache_file ]] || fail_test 'failed removal deleted cached state'
! grep -q '^Removed ' "$test_root/remove.out" || fail_test 'failed removal printed a success message'

printf 'y\n' | "$helper" project remove one >/dev/null
assert_jq "$config_file" '[.projects[].id] | index("one") == null' 'successful removal retained the project'
[[ ! -e $project_one_cache && ! -e $cache_file ]] || fail_test 'successful removal retained project/global cache data'

printf 'sk_one\n' | "$helper" configure one >/dev/null
rm -f -- "$FAKE_SECRET_STATE/io.github.endijs.revenue-pulse--one" "$FAKE_SECRET_STATE/io.github.endijs.revenue-pulse--one.label"
printf 'y\n' | "$helper" project remove one >/dev/null
assert_jq "$config_file" '[.projects[].id] | index("one") == null' 'project with an already-absent key could not be removed'

# The interactive manager catches removal errors without disabling fail-fast
# behavior inside the child removal transaction.
printf 'sk_manager\n' | "$helper" configure manager >/dev/null 2>&1
if ! printf 'r\nmanager\ny\nq\n' | FAKE_CONFIG_WRITE_FAIL=1 "$helper" manage \
  >"$test_root/manager-remove.out" 2>"$test_root/manager-remove.err"; then
  fail_test 'manager did not remain usable after a handled removal failure'
fi
assert_jq "$config_file" '[.projects[].id] | index("manager") != null' \
  'manager removal write failure discarded the project identifier'
! grep -q '^Removed ' "$test_root/manager-remove.out" || fail_test 'manager removal write failure printed success'
grep -q 'Project was not removed' "$test_root/manager-remove.out" || fail_test 'manager hid the removal failure'
printf 'y\n' | "$helper" project remove manager >/dev/null

"$helper" settings bar-metric revenue >/dev/null &
first_pid=$!
"$helper" settings bar-scope selected >/dev/null &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
assert_jq "$config_file" '.barMetric == "revenue" and .barScope == "selected"' \
  'concurrent settings updates lost one mutation'

secret_two=$FAKE_SECRET_STATE/io.github.endijs.revenue-pulse--two
old_secret=$(<"$secret_two")
config_before=$(<"$config_file")
if printf 'sk_replacement\n' | FAKE_CONFIG_WRITE_FAIL=1 "$helper" configure two >/dev/null 2>"$test_root/reconnect.err"; then
  fail_test 'reconnect succeeded even though configuration could not be written'
fi
[[ $(<"$secret_two") == "$old_secret" ]] || fail_test 'failed configuration write did not restore the previous key'
[[ $(<"$config_file") == "$config_before" ]] || fail_test 'failed reconnect changed configuration'

if FAKE_CLEAR_FAIL=1 "$helper" logout >"$test_root/logout.out" 2>"$test_root/logout.err"; then
  fail_test 'logout succeeded after keyring deletion failure'
fi
[[ -f $config_file ]] || fail_test 'failed logout discarded local credential coordinates'
! grep -q 'credentials and cached metrics removed' "$test_root/logout.out" || fail_test 'failed logout printed success'

"$helper" logout >/dev/null
[[ ! -e $config_file && ! -e $cache_file ]] || fail_test 'successful logout retained local state'
[[ -z $(find "$FAKE_SECRET_STATE" -type f -print -quit) ]] || fail_test 'service-scoped logout retained an orphaned credential'
[[ -e $XDG_CONFIG_HOME/revenue-pulse/.config.lock ]] || fail_test 'logout unlinked the persistent lock inode'

# Demo data should be screenshot-safe, internally coherent, and shaped like
# distinct real-world metrics instead of a shared monotonic ramp.
"$helper" demo >"$test_root/demo.json"
assert_jq "$test_root/demo.json" '
  .demo == true
  and .settings.barMetric == "revenue"
  and [.projects[].name] == ["Orbit Notes","Tiny Habits","Focus Garden"]
  and ([.projects[].charts[] | length == 28] | all)
' 'demo snapshot is missing its synthetic projects or complete chart series'
# The dollar-prefixed names below are jq variables, not shell expansions.
# shellcheck disable=SC2016
assert_jq "$test_root/demo.json" '
  [.projects[]
    | ((.metrics.revenue.value - ([.charts.revenue[].value] | add)) as $difference
      | $difference > -0.011 and $difference < 0.011)
    and .metrics.mrr.value == .charts.mrr[-1].value
    and .metrics.active_subscriptions.value == .charts.active_subscriptions[-1].value
    and .metrics.active_trials.value == .charts.active_trials[-1].value
    and .metrics.new_customers.value == ([.charts.new_customers[].value] | add)
  ] | all
' 'demo overview metrics disagree with their chart series'
# The dollar-prefixed names below are jq variables, not shell expansions.
# shellcheck disable=SC2016
assert_jq "$test_root/demo.json" '
  [.totals.charts[]
    | . as $points
    | [range(1; $points | length) as $i | $points[$i].value - $points[$i - 1].value]
    | (any(.[]; . > 0) and any(.[]; . < 0))
  ] | all
' 'a demo chart is still a monotonic ramp instead of a plausible series'

# Invalid existing configuration must never be silently replaced by a settings write.
mkdir -p "$(dirname -- "$config_file")"
printf '{broken json\n' >"$config_file"
invalid_before=$(<"$config_file")
if "$helper" settings bar-metric mrr >/dev/null 2>&1; then
  fail_test 'settings silently replaced invalid configuration'
fi
[[ $(<"$config_file") == "$invalid_before" ]] || fail_test 'invalid configuration was modified'

! grep -q 'Image {' "$repo_dir/Panel.qml" || fail_test 'panel still contains a metadata-selected image loader'
grep -q 'function currentIconUrl()' "$repo_dir/Service.qml" || fail_test 'icon defense-in-depth function is missing'
grep -q 'root.service.leaveDemo(false)' "$repo_dir/Panel.qml" || fail_test 'display settings still request a due network refresh'
grep -q 'invalid snapshot shape' "$repo_dir/Service.qml" || fail_test 'helper payload shape is not validated'
grep -q 'onStreamFinished: root.fetchOutput = text' "$repo_dir/Service.qml" || fail_test 'fetch output is still applied before exit status is known'
grep -q 'function leaveDemo(refreshAfterLoad)' "$repo_dir/Service.qml" || fail_test 'demo exit does not clear temporary view settings'
plugin_id=$(jq -r '.id' "$repo_dir/manifest.json")
[[ $plugin_id == io.github.endijs.pulse-for-revenuecat ]] || fail_test 'manifest contains the wrong permanent plugin ID'
grep -q "moduleName: \"$plugin_id\"" "$repo_dir/BarWidget.qml" || fail_test 'bar widget ID differs from the manifest'
grep -q "shell.hide(\"$plugin_id\")" "$repo_dir/Panel.qml" || fail_test 'panel lifecycle ID differs from the manifest'

printf 'All RevenueCat plugin tests passed.\n'
