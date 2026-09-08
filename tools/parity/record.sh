#!/bin/zsh
# Records one scripted run: record.sh <native|flutter> <TestName> <out.mov> [PARITY_FLAT=1]
# The test is a method of ParityDriver in the native project's UI test target.
set -e
source "$(dirname "$0")/parity.env"
which=$1; test=$2; out=$3; flat=${4:-0}
# A loaded host drops frames from the recording; wait for it to calm down.
for i in $(seq 1 ${PARITY_WAIT_TICKS:-360}); do
  load=$(sysctl -n vm.loadavg | awk '{print int($2)}')
  [ "$load" -lt "${PARITY_MAX_LOAD:-10}" ] && break
  [ "$i" -eq 1 ] && echo "load average $load; waiting for < ${PARITY_MAX_LOAD:-10}"
  sleep 10
done
xcrun simctl io "$PARITY_SIM" recordVideo --codec h264 --force "$out" &
rec=$!
sleep 1
# xcodebuild forwards only TEST_RUNNER_-prefixed variables to the test runner.
TEST_RUNNER_PARITY_APP=$which TEST_RUNNER_PARITY_FLAT=$flat TEST_RUNNER_PARITY_SHOW_TOUCHES=1 \
  xcodebuild test-without-building \
    -xctestrun "$(ls -t "$NATIVE_DERIVED"/Build/Products/*.xctestrun | head -1)" \
    -destination "id=$PARITY_SIM" \
    -only-testing "ParityDriver/ParityDriver/$test" \
    > "${out%.mov}.log" 2>&1 || { echo "driver failed, see ${out%.mov}.log"; }
sleep 0.5
kill -INT $rec
wait $rec 2>/dev/null || true
echo "recorded $out ($(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$out") frames)"
