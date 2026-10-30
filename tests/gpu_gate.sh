#!/usr/bin/env bash
# The GPU side of the performance gate (GAME_PLAN.md, "Performance budget"). Runs tests/gpu_probe.tscn
# with a real renderer (Mesa's llvmpipe under Xvfb, its shader cache off so every compile costs what
# a browser session pays) and fails when, after the warm-up:
#   - an event's worst frame is more than THRESHOLD over its own median: under llvmpipe a shader
#     compile is an LLVM build of tens to hundreds of milliseconds, so this is a material the
#     warm-up did not draw (or did not draw lit by the muzzle light), or a mesh or texture upload.
#     THRESHOLD is 40 ms, or 0.8 of the idle median on a slower machine. The load marked "heavy"
#     (a crowd under automatic fire) is long by nature and is not timed. A timing failure is
#     retried once and must repeat; a scheduling hiccup does not fail the build.
#   - an event that already happened once in the run ("repeat") allocates GPU buffer or texture
#     memory: something is built per event.
#   tests/gpu_gate.sh [path/to/godot]
# Needs xvfb-run and Mesa (any Ubuntu with xvfb and libgl1-mesa-dri).
set -uo pipefail
godot="${1:-godot}"
project="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Runs the probe once; prints the table; fills FAILS (hard failures) and SLOW (timing suspects).
probe() {
	local log="$1"
	MESA_SHADER_CACHE_DISABLE=true xvfb-run -a -s "-screen 0 640x360x24" "$godot" --path "$project" \
		--rendering-driver opengl3 --resolution 640x360 res://tests/gpu_probe.tscn >"$log" 2>&1
	local status=$?
	grep -v "ALSA lib\|snd_func\|ERR_CANT_OPEN\|^GPU_EVENT|" "$log"
	FAILS=()
	SLOW=()
	if [ "$status" -ne 0 ]; then
		FAILS+=("the probe exited with $status")
	fi
	if grep -q "SCRIPT ERROR" "$log"; then
		FAILS+=("the probe hit a script error")
	fi
	if ! grep -q "^GPU_EVENT|" "$log"; then
		FAILS+=("the probe reported no events")
		return
	fi
	local idle_median
	idle_median="$(grep "^GPU_EVENT|" "$log" | awk -F'|' '$8 ~ /idle/ { print $4 }' | head -1)"
	idle_median="${idle_median:-50}"
	local threshold
	threshold="$(awk -v m="$idle_median" 'BEGIN { t = m * 0.8; if (t < 40) t = 40; printf "%.1f", t }')"
	echo "GPU GATE  idle median ${idle_median} ms; a frame more than ${threshold} ms over its event's median counts as a compile or upload"
	while IFS='|' read -r _ label worst median frames buffers textures flags; do
		case ",$flags," in *,heavy,*) ;; *)
			if awk -v w="$worst" -v m="$median" -v t="$threshold" 'BEGIN { exit !(w - m > t) }'; then
				SLOW+=("'$label': worst frame $worst ms against a median of $median ms")
			fi
			;;
		esac
		case ",$flags," in *,repeat,*)
			if [ "$buffers" -gt 0 ] || [ "$textures" -gt 0 ]; then
				FAILS+=("'$label' allocated $buffers bytes of GPU buffers and $textures of textures although it had happened before: something is built per event")
			fi
			;;
		esac
	done < <(grep "^GPU_EVENT|" "$log")
}

probe "$work/run1.log"
first_fails=("${FAILS[@]}")
first_slow=("${SLOW[@]}")
confirmed_slow=()
if [ "${#first_slow[@]}" -gt 0 ]; then
	echo "GPU GATE  ${#first_slow[@]} event(s) had a slow frame; running the probe again to tell a compile from a hiccup"
	probe "$work/run2.log"
	for slow in "${first_slow[@]}"; do
		event="${slow%%:*}"
		for again in "${SLOW[@]}"; do
			if [ "${again%%:*}" = "$event" ]; then
				confirmed_slow+=("$slow (and again: ${again#*: })")
			fi
		done
	done
	for fail in "${FAILS[@]}"; do
		first_fails+=("$fail")
	done
fi
failures=0
for fail in "${first_fails[@]}"; do
	echo "GPU GATE  FAIL  $fail"
	failures=$((failures + 1))
done
for slow in "${confirmed_slow[@]}"; do
	echo "GPU GATE  FAIL  $slow: a shader compile or an upload after the warm-up. Add what the event draws to FxPool.warm_up (lit and unlit) or pool what it builds."
	failures=$((failures + 1))
done
if [ "$failures" -eq 0 ]; then
	echo "GPU GATE  PASS  no event after the warm-up compiled a shader or uploaded a mesh; repeated events allocated nothing"
	exit 0
fi
echo "GPU GATE  $failures failure(s)"
exit 1
