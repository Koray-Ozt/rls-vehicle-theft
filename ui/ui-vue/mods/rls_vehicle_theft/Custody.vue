<template>
  <!-- The custody screen (custody.lua). It only draws the view Lua sends: BUSTED, the sentencing choice, the
       sentence passing, and the fade-out before Lua navigates back to play. -->
  <div class="custody-overlay" :class="{ leaving: stage === 'leaving' }">
    <h1 v-if="stage === 'busted' || stage === 'leaving' && !shown" class="busted-title" role="alert">BUSTED</h1>

    <section v-else-if="stage === 'sentencing'" class="court" role="dialog" aria-modal="true" aria-labelledby="court-title">
      <p class="kicker">Busted</p>
      <h1 id="court-title">Sentencing</h1>
      <p class="lead">
        {{ view.place ? `You were booked at ${view.place}.` : "You were booked." }} Choose who represents you.
      </p>
      <h2 class="section">{{ (view.counts?.length ?? 0) > 1 ? `Charges: ${view.counts.length} stolen cars` : "Charge" }}</h2>
      <ul class="facts counts">
        <li v-for="(count, index) in view.counts ?? []" :key="index">
          <span>
            {{ count.charge }}
            <small v-if="count.name || !count.arrested">{{ [count.name, count.arrested ? "" : "found in the search"].filter(Boolean).join(" · ") }}</small>
          </span>
          <strong>{{ money(count.fine) }}</strong>
        </li>
        <li v-if="view.investigations > 0">
          <span>Dealership investigations<small>closed by the court</small></span>
          <strong>{{ money(view.investigations) }}</strong>
        </li>
      </ul>
      <ul class="facts">
        <li><span>Prior arrests</span><strong :class="{ hot: view.priors > 0 }">{{ view.priors }}</strong></li>
        <li v-if="view.evades > 0"><span>Got away from the police</span><strong class="hot">{{ view.evades }}×</strong></li>
      </ul>
      <div class="options">
        <article v-for="option in view.options" :key="option.id" class="option" :class="option.id">
          <h2>{{ option.label }}</h2>
          <p class="note">{{ option.note }}</p>
          <dl>
            <div><dt>Sentence</dt><dd>{{ duration(option.hours) }}</dd></div>
            <div><dt>Fine</dt><dd>{{ money(option.fine) }}</dd></div>
            <div><dt>Lawyer's fee</dt><dd>{{ option.fee > 0 ? money(option.fee) : "None" }}</dd></div>
          </dl>
          <BngButton :class="{ primary: option.id === 'public' }" :accent="option.id === 'public' ? undefined : 'secondary'"
            :disabled="chosen || !option.affordable" @click="choose(option.id)">
            {{ option.id === "public" ? "Take the public defender" : "Hire the lawyer" }}
          </BngButton>
          <p v-if="!option.affordable" class="warn">You cannot afford this lawyer's fee.</p>
        </article>
      </div>
    </section>

    <section v-else-if="stage === 'serving' || stage === 'leaving'" class="serving" role="status">
      <p class="kicker">Serving the sentence</p>
      <h1>{{ duration(view.hours ?? 0) }}</h1>
      <div class="bar"><span :style="{ animationDuration: `${view.seconds ?? 5}s` }"></span></div>
      <p class="lead">{{ view.place ? `Held at ${view.place}.` : "Held in custody." }} Time passes.</p>
    </section>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, shallowRef } from "vue"
import { BngButton } from "@/common/components/base"
import { useBridge } from "@/bridge"

const { api, events } = useBridge()
const view = shallowRef({ stage: "busted" })
const chosen = shallowRef(false)
// Once the sentence has been on screen, the fade-out keeps it instead of flashing back to BUSTED.
const shown = shallowRef(false)
let mounted = false
const eventName = "RlsTheftCustody"

const stage = computed(() => view.value?.stage ?? "busted")

function apply(next) {
  if (!next || !next.stage) return
  if (next.stage === "serving") {
    shown.value = true
  }
  if (next.stage === "sentencing" && view.value?.stage !== "sentencing") chosen.value = false
  view.value = next.stage === "leaving" ? { ...view.value, stage: "leaving" } : next
}

function duration(hours) {
  const days = Math.floor(hours / 24)
  const rest = hours % 24
  if (days === 0) return `${hours} h`
  return rest === 0 ? `${days} d` : `${days} d ${rest} h`
}

function money(amount) {
  return `$${Math.round(amount).toLocaleString("en-US")}`
}

function token() {
  const value = view.value?.token
  return Number.isSafeInteger(value) ? value : null
}

function choose(id) {
  const current = token()
  if (current === null || chosen.value) return
  chosen.value = true
  api.engineLua(`rlsVehicleTheft.custodyChoose(${current}, "${id}")`, accepted => {
    if (mounted && accepted !== true) chosen.value = false
  })
}

// Custody cannot be left from the keyboard; the choice is still due.
function onKeyDown(event) {
  if (event.code === "Escape") event.preventDefault()
}

onMounted(() => {
  mounted = true
  window.addEventListener("keydown", onKeyDown)
  events.on(eventName, apply)
  api.engineLua("rlsVehicleTheft and rlsVehicleTheft.getCustodyView()", next => {
    if (mounted) apply(next)
  })
})

onUnmounted(() => {
  mounted = false
  window.removeEventListener("keydown", onKeyDown)
  events.off(eventName, apply)
  const current = token()
  if (current !== null) api.engineLua(`rlsVehicleTheft.custodyScreenLeft(${current})`)
})
</script>

<style scoped>
.custody-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  display: grid;
  place-items: center;
  overflow: auto;
  padding: 1.25rem;
  background: #000;
  color: #f2f5f7;
  pointer-events: auto;
  animation: custody-fade-in 0.5s ease-out both;
}

.custody-overlay.leaving {
  animation: custody-fade-out 0.5s ease-in both;
}

.busted-title {
  margin: 0;
  color: #e8202a;
  font-size: clamp(4rem, 14vw, 11rem);
  font-weight: 900;
  letter-spacing: 0.08em;
  line-height: 1;
  text-shadow: 0 0 2.5rem rgb(232 32 42 / 45%);
  animation: busted-stamp 0.6s cubic-bezier(0.2, 1.4, 0.4, 1) 0.35s both;
}

.kicker {
  margin: 0;
  color: #e8202a;
  font-size: 0.85rem;
  font-weight: 800;
  letter-spacing: 0.2em;
  text-transform: uppercase;
}

.court,
.serving {
  box-sizing: border-box;
  width: min(100%, 44rem);
  animation: custody-rise 0.35s ease-out both;
}

.court h1,
.serving h1 {
  margin: 0.25rem 0 0;
  font-size: clamp(1.8rem, 5vw, 2.6rem);
  line-height: 1.1;
}

.lead {
  margin: 0.6rem 0 0;
  color: #c7cfd8;
  line-height: 1.4;
}

.facts {
  margin: 1.1rem 0 0;
  padding: 0;
  list-style: none;
  border: 1px solid #333a43;
  border-radius: 0.5rem;
}

.facts li {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.55rem 0.8rem;
}

.facts li + li {
  border-top: 1px solid #333a43;
}

.section {
  margin: 1.1rem 0 0;
  color: #a9b3be;
  font-size: 0.8rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.section + .facts {
  margin-top: 0.4rem;
}

.facts small {
  display: block;
  margin-top: 0.15rem;
  color: #8e99a5;
  font-size: 0.8rem;
}

.counts {
  max-height: 12rem;
  overflow: auto;
}

.facts span,
.option dt {
  color: #a9b3be;
}

.hot {
  color: #ff847d;
}

.options {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
  gap: 0.9rem;
  margin-top: 1.1rem;
}

.option {
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  padding: 1rem 1.1rem 1.1rem;
  border: 1px solid #3d454f;
  border-top: 3px solid #6b7682;
  border-radius: 0.7rem;
  background: #14181d;
}

.option.private {
  border-top-color: #f0b44c;
}

.option h2 {
  margin: 0;
  font-size: 1.2rem;
}

.option .note {
  margin: 0;
  color: #b5bfca;
  font-size: 0.88rem;
  line-height: 1.35;
}

.option dl {
  margin: 0;
}

.option dl div {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.3rem 0;
}

.option dd {
  margin: 0;
  font-weight: 700;
}

.option .warn {
  margin: 0;
  color: #ff847d;
  font-size: 0.85rem;
}

.option dl {
  flex: 1;
}

.bar {
  height: 0.5rem;
  margin-top: 1.2rem;
  overflow: hidden;
  border-radius: 999px;
  background: #22282f;
}

.bar span {
  display: block;
  height: 100%;
  background: #e8202a;
  transform-origin: left;
  animation: custody-serve linear both;
}

@keyframes custody-fade-in {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes custody-fade-out {
  from { opacity: 1; }
  to { opacity: 0; }
}

@keyframes busted-stamp {
  from { opacity: 0; transform: scale(1.6); }
  to { opacity: 1; transform: scale(1); }
}

@keyframes custody-rise {
  from { opacity: 0; transform: translateY(0.75rem); }
  to { opacity: 1; transform: none; }
}

@keyframes custody-serve {
  from { transform: scaleX(0); }
  to { transform: scaleX(1); }
}
</style>
