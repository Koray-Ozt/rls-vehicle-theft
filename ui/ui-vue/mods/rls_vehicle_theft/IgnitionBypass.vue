<template>
  <div class="ignition-overlay">
    <section class="ignition-panel" role="dialog" aria-modal="true" aria-labelledby="ignition-title">
      <header class="ignition-header">
        <div>
          <h1 id="ignition-title">Ignition bypass</h1>
          <p>Match three signals to start the engine.</p>
        </div>
        <div v-if="state" class="timer" :class="{ urgent: state.remaining <= 5 }">
          <span>TIME LEFT</span>
          <strong>{{ Math.ceil(state.remaining) }} s</strong>
        </div>
      </header>

      <template v-if="state">
        <div class="timer-track" aria-hidden="true">
          <div :style="{ width: percentage(state.remaining / state.duration) }"></div>
        </div>

        <div class="signal-count">
          <span>Signals matched</span>
          <strong>{{ state.matched }} / {{ state.stages }}</strong>
        </div>
        <div class="signal-steps" aria-hidden="true">
          <span v-for="step in state.stages" :key="step"
            :class="{ matched: step <= state.matched, current: step === state.matched + 1 }"></span>
        </div>

        <div class="signal-track" :class="{ aligned: state.inTarget && state.started }"
          :style="trackStyle" aria-hidden="true">
          <span class="target"></span>
          <span class="marker"></span>
        </div>
        <div class="track-caption">
          <span><i class="legend-marker"></i> Moving marker</span>
          <span><i class="legend-target"></i> Target zone</span>
        </div>

        <p class="instruction" :class="{
          missed: state.missed,
          aligned: state.started && !state.missed && (state.inTarget || state.feedback),
        }">
          {{ instruction }}
        </p>

        <footer class="ignition-actions">
          <BngButton class="primary" :disabled="state.feedback" @click="primaryAction">
            {{ state.started ? "Lock signal" : "Begin" }} <span class="key-hint">Space</span>
          </BngButton>
          <BngButton accent="secondary" @click="send('cancel')">Cancel</BngButton>
        </footer>
      </template>

      <template v-else>
        <p role="status">{{ unavailable ? "No ignition attempt is active." : "Reading ignition status…" }}</p>
        <BngButton accent="secondary" @click="returnToPlay">Return to driving</BngButton>
      </template>
    </section>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, shallowRef } from "vue"
import { BngButton } from "@/common/components/base"
import { useBridge } from "@/bridge"

const { api, events } = useBridge()
const state = shallowRef(null)
const unavailable = shallowRef(false)
const eventName = "RlsTheftIgnitionState"
let mounted = false

const percentage = value => `${Math.max(0, Math.min(1, value)) * 100}%`

const trackStyle = computed(() => ({
  "--marker": percentage(state.value.cursor),
  "--target-left": percentage(state.value.target - state.value.width / 2),
  "--target-width": percentage(state.value.width),
}))

const instruction = computed(() => {
  const attempt = state.value
  if (!attempt.started) return "Press Lock signal (or Space) when the white marker is in the green zone. A miss costs time. The timer starts when you click Begin."
  if (attempt.missed) return `Missed. −${attempt.penalty} s. Try again.`
  if (attempt.feedback) return "Signal matched."
  if (attempt.inTarget) return "In range. Lock the signal now."
  return "Wait for the white marker to enter the green zone."
})

function applyState(next) {
  if (!mounted || !Number.isSafeInteger(next?.token)) return
  if (state.value && next.token !== state.value.token) return
  state.value = next
}

function send(action) {
  const token = state.value?.token
  if (!Number.isSafeInteger(token)) return
  api.engineLua(`rlsVehicleTheft.ignitionInput(${token}, "${action}")`)
}

function primaryAction() {
  const attempt = state.value
  if (!attempt || attempt.feedback) return
  send(attempt.started ? "lock" : "begin")
}

function onKeyDown(event) {
  if (event.repeat || (event.code !== "Space" && event.code !== "Enter")) return
  event.preventDefault()
  primaryAction()
}

function returnToPlay() {
  if (state.value) send("cancel")
  else api.engineLua('extensions.ui_router.navigate("play")')
}

onMounted(() => {
  mounted = true
  events.on(eventName, applyState)
  window.addEventListener("keydown", onKeyDown)
  api.engineLua("rlsVehicleTheft and rlsVehicleTheft.getIgnitionState()", next => {
    if (!mounted) return
    if (next) applyState(next)
    else unavailable.value = true
  })
})

onUnmounted(() => {
  mounted = false
  events.off(eventName, applyState)
  window.removeEventListener("keydown", onKeyDown)
  send("leave")
})
</script>

<style scoped>
.ignition-overlay {
  position: fixed;
  inset: 0;
  z-index: 20;
  display: grid;
  place-items: center;
  padding: 1.25rem;
  background: rgb(8 11 14 / 68%);
  color: #f2f5f7;
  pointer-events: auto;
}

.ignition-panel {
  box-sizing: border-box;
  width: min(100%, 34rem);
  max-height: 100%;
  overflow: auto;
  padding: clamp(1.25rem, 3vw, 2rem);
  border: 1px solid #464e58;
  border-top: 3px solid #f79040;
  border-radius: 0.8rem;
  background: #1b2026;
  box-shadow: 0 1.25rem 4rem rgb(0 0 0 / 45%);
}

.ignition-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1rem;
}

h1 {
  margin: 0;
  font-size: clamp(1.5rem, 4vw, 2rem);
  line-height: 1.15;
}

p {
  margin: 0.45rem 0 0;
  color: #c7cfd8;
  line-height: 1.4;
}

.timer {
  flex: none;
  display: grid;
  text-align: right;
  color: #f9ab69;
}

.timer span, .track-caption {
  font-size: 0.78rem;
  color: #b5bfca;
}

.timer strong {
  font-size: 1.55rem;
  font-variant-numeric: tabular-nums;
}

.timer.urgent { color: #ff847d; }

.timer-track {
  margin: 1rem 0 1.25rem;
  height: 0.25rem;
  border-radius: 1rem;
  background: #3d454f;
  overflow: hidden;
}

.timer-track > div {
  height: 100%;
  background: #f79040;
}

.signal-count {
  display: flex;
  justify-content: space-between;
  font-size: 0.88rem;
}

.signal-steps {
  display: flex;
  gap: 0.35rem;
  margin-top: 0.45rem;
}

.signal-steps > span {
  flex: 1;
  height: 0.28rem;
  border-radius: 0.2rem;
  background: #414a53;
}

.signal-steps .matched { background: #66e6a7; }
.signal-steps .current { background: #f79040; }

.signal-track {
  position: relative;
  height: 3.5rem;
  margin: 1.15rem 0 0.65rem;
  border: 1px solid #4a5460;
  border-radius: 0.5rem;
  background: repeating-linear-gradient(90deg, #2c343d 0 1px, transparent 1px 10%), #232930;
}

.target, .marker { position: absolute; }

.target {
  inset-block: 0;
  left: var(--target-left);
  width: var(--target-width);
  box-sizing: border-box;
  border-inline: 2px solid #65e4a5;
  background: #205b45;
}

.signal-track.aligned .target { background: #2c805b; }

.marker {
  inset-block: -0.18rem;
  left: clamp(0.15rem, var(--marker), calc(100% - 0.15rem));
  width: 0.28rem;
  transform: translateX(-50%);
  border-radius: 0.25rem;
  background: #fff;
  box-shadow: 0 0 0.45rem #10151b;
  transition: left 34ms linear;
}

.track-caption {
  display: flex;
  flex-wrap: wrap;
  gap: 0.9rem;
}

.track-caption > span {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}

.track-caption i {
  width: 0.65rem;
  height: 0.65rem;
  border-radius: 0.13rem;
}

.legend-marker { background: #fff; }
.legend-target { background: #66e6a7; }

.instruction {
  min-height: 2.8em;
  margin: 1rem 0 0.65rem;
}

.instruction.aligned { color: #7bf1b7; }
.instruction.missed { color: #ff847d; }

.key-hint {
  margin-left: 0.4rem;
  padding: 0 0.3rem;
  border: 1px solid currentColor;
  border-radius: 0.2rem;
  font-size: 0.72em;
  opacity: 0.7;
}

.ignition-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
}

.ignition-actions .primary { flex: 1; }
</style>
