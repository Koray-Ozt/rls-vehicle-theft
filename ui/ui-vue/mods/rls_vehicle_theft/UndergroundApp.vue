<!-- Underground phone app: list a re-identified stolen vehicle and sell it to off-the-books buyers.
     Offers and negotiation run in Lua (rlsVehicleTheft.lua, "Underground market"); the negotiation
     screen reuses RLS's NegotiationChatWindow so it looks and behaves like the marketplace one. -->
<template>
  <div class="ug">
    <template v-if="negotiation">
      <div class="ug-negotiate">
        <NegotiationChatWindow
          compact
          :show-close="false"
          :opponent-name="negotiation.opponentName"
          :subject-name="vehicle?.name || 'Vehicle'"
          :thumbnail="vehicle?.thumbnail"
          :fallback-icon="icons.car"
          :market-value="Number(negotiation.marketValue) || 0"
          :patience="Number(negotiation.patience) || 0"
          :quote="negotiation.quote"
          :history="negotiation.history || []"
          :status="negotiation.status"
          am-i-selling
          :their-offer="Number(negotiation.theirOffer) || 0"
          :my-offer="negotiation.myOffer != null ? Number(negotiation.myOffer) : null"
          :starting-price="Number(negotiation.startingPrice) || 0"
          :has-visible-their-offer="true"
          :step="50"
          :busy="false"
          :resolved-title="resolved.title"
          :resolved-text="resolved.text"
          :resolved-tone="resolved.tone"
          resolved-action="Back to offers"
          @send="price => call(`undergroundCounter(${Math.round(price)})`)"
          @accept="call('undergroundTakeOffer()')"
          @walk-away="call('undergroundCancelNegotiation()')"
          @resolve="call('undergroundDismissResult()')" />
      </div>
    </template>

    <template v-else>
      <header class="ug-head">
        <div class="ug-logo" aria-hidden="true"></div>
        <div>
          <h1>Underground</h1>
          <p>Off-the-books vehicle sales</p>
        </div>
        <button class="ug-settings-toggle" :class="{ on: settingsOpen }" :disabled="isCapturing"
          :title="settingsOpen ? 'Back to Underground' : 'Settings'"
          :aria-label="settingsOpen ? 'Back to Underground' : 'Settings'"
          @click="settingsOpen = !settingsOpen">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="3" />
            <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
          </svg>
        </button>
      </header>

      <main class="ug-body">
        <section v-if="settingsOpen" class="ug-settings">
          <h2>Mod settings</h2>
          <section class="ug-panel">
            <strong>Take or store vehicle</strong>
            <p class="ug-setting-copy">Choose a keyboard key, mouse button, or controller button. Mouse left-click, right-click and axis inputs are reserved. The action is available during gameplay; avoid an input already used by another game action.</p>
            <div class="ug-current-bindings">
              <span>Current binding</span>
              <strong v-if="shortcutBindings.length">{{ shortcutBindings.map(bindingLabel).join(" · ") }}</strong>
              <strong v-else>Loading binding…</strong>
            </div>
            <button class="ug-btn primary" :disabled="isCapturing" @click="captureShortcut">
              {{ isCapturing ? "Press a key or button…" : "Change binding" }}
            </button>
            <p v-if="isCapturing" class="ug-hint">Press Esc to cancel. Axis controls are not supported for this action.</p>
            <p v-if="bindingStatus" class="ug-binding-status" role="status">{{ bindingStatus }}</p>
          </section>
          <button class="ug-link" :disabled="isCapturing" @click="settingsOpen = false">Back to Underground</button>
        </section>

        <div v-else-if="!state" class="ug-empty">Connecting…</div>
        <div v-else-if="!state.available" class="ug-empty">Only available in an RLS career.</div>

        <template v-else>
          <section v-if="state.skill" class="ug-skill">
            <div class="ug-skill-row">
              <strong>Vehicle Theft · LV {{ state.skill.level }}</strong>
              <span>{{ state.skill.max ? 'MAX' : `${state.skill.xp} / ${state.skill.to} XP` }}</span>
            </div>
            <div class="ug-skill-bar"><div :style="{ width: skillPercent + '%' }"></div></div>
          </section>

          <section v-if="state.cases && state.cases.length" class="ug-cases">
            <button
              v-for="c in state.cases"
              :key="c.serial"
              class="ug-case"
              :class="{ on: c.selected }"
              @click="call(`undergroundSelect(${c.serial})`)">{{ c.name }} · {{ c.heatLabel }}</button>
            <span class="ug-cases-note">{{ state.cases.length }} / {{ state.limit }} cars</span>
          </section>

          <section v-if="state.result" class="ug-result" :class="state.result.kind">
            <strong v-if="state.result.kind === 'sold'">Sold for {{ money(state.result.price) }}</strong>
            <strong v-else-if="state.result.kind === 'sting'">The buyer was an undercover cop</strong>
            <strong v-else>Police raided the handover</strong>
            <span v-if="state.result.kind === 'sold'">The money is in your account. <span :class="['ug-net', netTone(state.result.price, state.result.expenses)]">Net {{ netText(state.result.price, state.result.expenses) }}{{ state.result.partial ? " · partial costs" : "" }}</span></span>
            <span v-else-if="state.result.kind === 'sting'">{{ stingText }}</span>
            <span v-else>The vehicle was seized and the theft fine was charged.</span>
            <button class="ug-link" @click="call('undergroundDismissResult()')">Dismiss</button>
          </section>

          <section v-if="state.sting && !(state.result && state.result.kind === 'sting')" class="ug-result sting">
            <strong>{{ state.sting.chasing ? "Undercover units are chasing you" : "Undercover units are looking for you" }}</strong>
            <span v-if="state.sting.chasing">Lose them. If they catch you, the stung car is seized and the theft fine is charged.</span>
            <span v-else>The next time you drive, expect a chase. The operation ends in {{ clock(state.sting.remaining) }}.</span>
          </section>

          <div v-if="!vehicle" class="ug-empty">
            <strong>Nothing to sell</strong>
            <span>Steal a vehicle, store it in your garage and change its identity. It shows up here once it is ready.</span>
          </div>

          <template v-else>
            <section class="ug-card">
              <div class="ug-thumb">
                <img v-if="vehicle.thumbnail && !thumbBroken" :src="vehicle.thumbnail" alt="" @error="thumbBroken = true" />
              </div>
              <div class="ug-card-info">
                <strong>{{ vehicle.name || "Stolen vehicle" }}</strong>
                <span v-if="vehicle.identity" class="ug-plate">{{ vehicle.identity }}</span>
                <div class="ug-badges">
                  <span v-if="vehicle.repainted === false" class="badge bad">Original paint · risky</span>
                  <span v-else-if="vehicle.repainted === true" class="badge good">Repainted</span>
                  <span v-if="vehicle.heat" class="badge has-tip" :class="`heat-${vehicle.heat.stage}`" tabindex="0">
                    {{ vehicle.heat.label }}
                    <template v-if="vehicle.heat.remaining > 0"> · {{ clock(vehicle.heat.remaining) }} to cool</template>
                    <span class="ug-tip" role="tooltip">
                      {{ vehicle.heat.detail }}
                      <template v-if="vehicle.heat.stage === 'hot'"> Hot cars sell for {{ rate('hot') }}% of the car's value, warm cars for {{ rate('warm') }}% and cold cars for {{ rate('cold') }}%.</template>
                      <template v-else-if="vehicle.heat.stage === 'warm'"> Warm cars sell for {{ rate('warm') }}% of the car's value. Stay clear of patrols to reach the full {{ rate('cold') }}%.</template>
                      <template v-else> This car sells for the full {{ rate('cold') }}% of its value.</template>
                    </span>
                  </span>
                </div>
              </div>
            </section>

            <p v-if="vehicle.phase === 'transit'" class="ug-step">Store it first: stop it inside a garage you own. You earn the theft XP once it is stored.</p>
            <p v-else-if="vehicle.phase === 'stored' && state.sting && state.sting.serial === vehicle.serial" class="ug-step">Police are after this car. No crew will touch it until you lose them.</p>
            <p v-else-if="vehicle.phase === 'stored'" class="ug-step">Change its identity at the garage computer before selling.</p>
            <p v-else-if="vehicle.phase === 'chopping'" class="ug-step">Being stripped for parts: {{ clock(vehicle.workshopRemaining) }} left.</p>
            <p v-else-if="vehicle.phase === 'workshop'" class="ug-step">Identity change in progress: {{ clock(vehicle.workshopRemaining) }} left.</p>

            <template v-else-if="vehicle.phase === 'ready'">
              <section class="ug-panel">
                <div class="ug-row"><span>Underground value</span><strong>{{ money(vehicle.marketValue) }}</strong></div>
                <label class="ug-label" for="ug-price">Asking price</label>
                <div class="ug-price">
                  <button @click="nudge(-500)">−</button>
                  <input id="ug-price" v-model="priceText" inputmode="numeric" @blur="normalizePrice" />
                  <button @click="nudge(500)">+</button>
                </div>
                <p class="ug-hint">{{ priceHint }}</p>
                <p v-if="price > 0" class="ug-net-row" :class="netTone(price, vehicle.expenses)">
                  Est. net after expenses: <strong>{{ netText(price, vehicle.expenses) }}</strong><span v-if="vehicle.expensesPartial"> · partial costs</span>
                  <span class="ug-net-sub">{{ expenseNote }}</span>
                </p>
                <div class="ug-actions">
                  <button class="ug-btn ghost" @click="setPrice(vehicle.suggestedPrice)">Suggested</button>
                  <button class="ug-btn primary" :disabled="!(price > 0)" @click="call(`undergroundList(${price})`)">List for sale</button>
                </div>
                <p v-if="vehicle.repainted === false" class="ug-warning">
                  The paint still matches the theft report: {{ state.raidChance }}% of handovers get raided. Repaint it at the garage computer first.
                </p>
              </section>
            </template>

            <template v-else-if="vehicle.phase === 'listed'">
              <section class="ug-panel">
                <div class="ug-row"><span>Listed at</span><strong>{{ money(vehicle.listedPrice) }}</strong></div>
                <div class="ug-row"><span>Underground value</span><span>{{ money(vehicle.marketValue) }}</span></div>
                <div class="ug-row" :class="netTone(vehicle.listedPrice, vehicle.expenses)">
                  <span>Est. net at this price<span v-if="vehicle.expensesPartial"> (partial costs)</span></span>
                  <strong>{{ netText(vehicle.listedPrice, vehicle.expenses) }}</strong>
                </div>
                <p class="ug-net-sub">{{ expenseNote }}</p>
                <div class="ug-actions">
                  <button class="ug-btn ghost" @click="editingPrice = !editingPrice">{{ editingPrice ? "Close" : "Change price" }}</button>
                  <button class="ug-btn ghost danger" @click="call('undergroundUnlist()')">Remove listing</button>
                </div>
                <div v-if="editingPrice" class="ug-edit">
                  <div class="ug-price">
                    <button @click="nudge(-500)">−</button>
                    <input v-model="priceText" inputmode="numeric" @blur="normalizePrice" />
                    <button @click="nudge(500)">+</button>
                  </div>
                  <button class="ug-btn primary" :disabled="!(price > 0)" @click="applyPrice">Update price</button>
                </div>
              </section>

              <p v-if="vehicle.repainted === false" class="ug-warning">
                The paint still matches the theft report: {{ state.raidChance }}% of handovers get raided.
              </p>
              <p v-if="vehicle.handoverBlocked" class="ug-warning">{{ vehicle.handoverBlocked }}</p>

              <h2 class="ug-section">Offers <span v-if="offers.length">({{ offers.length }})</span></h2>
              <p v-if="!offers.length" class="ug-wait">
                Waiting for buyers<template v-if="vehicle.nextOfferIn != null"> · next contact in ~{{ clock(vehicle.nextOfferIn) }}</template>
              </p>
              <article v-for="offer in offers" :key="offer.id" class="ug-offer">
                <div class="ug-offer-top">
                  <div>
                    <strong>{{ offer.buyer }}</strong>
                    <span class="ug-archetype">{{ offer.archetype }}</span>
                  </div>
                  <div class="ug-offer-value">
                    <strong>{{ money(offer.value) }}</strong>
                    <span class="ug-net" :class="netTone(offer.value, vehicle.expenses)">Net {{ netText(offer.value, vehicle.expenses) }}</span>
                    <span :class="{ urgent: offer.expiresIn <= 30 }">{{ clock(offer.expiresIn) }}</span>
                  </div>
                </div>
                <p class="ug-quote">“{{ offer.quote }}”</p>
                <div class="ug-actions">
                  <button class="ug-btn ghost" @click="call(`undergroundDecline(${offer.id})`)">Decline</button>
                  <button class="ug-btn ghost" :disabled="offer.value >= vehicle.listedPrice" @click="call(`undergroundNegotiate(${offer.id})`)">Negotiate</button>
                  <button class="ug-btn primary" :disabled="!!vehicle.handoverBlocked" @click="call(`undergroundAccept(${offer.id})`)">Accept</button>
                </div>
              </article>
            </template>
          </template>
        </template>
      </main>
    </template>
  </div>
</template>

<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, shallowRef, watch } from "vue"
import { icons } from "@/common/components/base"
import { useBridge } from "@/bridge"
import useControls from "@/services/controls"
import NegotiationChatWindow from "../rls_career_overhaul/overhaul/modules/career/components/negotiation/NegotiationChatWindow.vue"
import { usePhoneScreen } from "../rls_career_overhaul/overhaul/modules/career/composables/usePhoneScreen.js"

const { api, events } = useBridge()
const controls = useControls()
const theftAction = "rlsVehicleTheftAttempt"
const eventName = "RlsTheftUnderground"
const state = shallowRef(null)
const thumbBroken = ref(false)
const editingPrice = ref(false)
const priceText = ref("")
const settingsOpen = ref(false)
const shortcutBindings = shallowRef([])
const bindingStatus = ref("")
const isCapturing = ref(false)
let mounted = false
let shortcutRefreshTimers = []

const vehicle = computed(() => state.value?.vehicle || null)
const offers = computed(() => state.value?.offers || [])
const negotiation = computed(() => state.value?.negotiation || null)

const skillPercent = computed(() => {
  const s = state.value?.skill
  if (!s || s.max) return 100
  const span = Number(s.to) - Number(s.from)
  return span > 0 ? Math.max(0, Math.min(100, ((Number(s.xp) - Number(s.from)) / span) * 100)) : 0
})
const money = value => `$${Math.round(Number(value) || 0).toLocaleString()}`
// Underground rate per heat stage in percent of the car's value, with the player's perks (from Lua).
const rate = stage => Number(state.value?.rates?.[stage]) || 0
const clock = seconds => {
  const s = Math.max(0, Math.round(Number(seconds) || 0))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
}

function refreshShortcutBindings() {
  shortcutBindings.value = controls.findAllBindingsForAction(theftAction, undefined, true)
    .map(binding => ({ control: binding.control, devName: binding.devName }))
}

function bindingLabel(binding) {
  const device = binding.devName?.startsWith("mouse") ? "Mouse"
    : binding.devName?.startsWith("keyboard") ? "Keyboard" : binding.devName || "Controller"
  const control = String(binding.control || "").replace(/\bctrl\b/g, "Ctrl").replace(/\bshift\b/g, "Shift")
  return `${device}: ${control}`
}

function cancelCaptureOnEscape(data) {
  if (isCapturing.value && data.controlType === "key" && /^(esc|escape)$/.test(data.control) && data.value > 0) {
    controls.cancelCaptureBinding()
  }
}

async function captureShortcut() {
  bindingStatus.value = ""
  isCapturing.value = true
  await nextTick()
  await new Promise(resolve => setTimeout(resolve, 100)) // Ignore the click that started capture.
  events.on("RawInputChanged", cancelCaptureOnEscape)
  try {
    const captured = await controls.captureBinding(true, theftAction)
    if (captured.controlType === "axis") {
      bindingStatus.value = "That is an axis input. Choose a key or button instead."
      return
    }
    if (captured.devName?.startsWith("mouse") && captured.control === "button0") {
      bindingStatus.value = "Left-click is reserved for the interface. Choose a different mouse button."
      return
    }

    const existing = controls.findAllBindingsForAction(theftAction, undefined, true)
    if (!existing.length) {
      bindingStatus.value = "Could not find the current binding. Reopen the app and try again."
      return
    }
    if (!controls.getBindingDetails(captured.devName, captured.control, theftAction)) {
      bindingStatus.value = "That input device is unavailable. Reconnect it and try again."
      return
    }

    controls.deleteBindings(existing.map(binding => ({
      devname: binding.devName,
      control: binding.control,
      action: theftAction,
    })))
    controls.addNewBinding({
      devname: captured.devName,
      ...controls.defaultBindingEntry(theftAction, captured.control),
      action: theftAction,
      control: captured.control,
    })
    bindingStatus.value = "Binding saved."
    setTimeout(refreshShortcutBindings, 250)
  } catch {
    bindingStatus.value = "Binding change cancelled."
  } finally {
    events.off("RawInputChanged", cancelCaptureOnEscape)
    isCapturing.value = false
    refreshShortcutBindings()
  }
}

const price = computed(() => Math.max(0, Math.round(Number(String(priceText.value).replace(/[^\d]/g, "")) || 0)))
const setPrice = value => { priceText.value = String(Math.max(0, Math.round(Number(value) || 0))) }
const normalizePrice = () => setPrice(price.value)
const nudge = delta => setPrice(Math.max(50, price.value + delta))

const priceHint = computed(() => {
  const base = Number(vehicle.value?.marketValue) || 0
  if (!base || !price.value) return ""
  const ratio = price.value / base
  if (ratio < 0.9) return "Below value: buyers call quickly and may offer close to your price."
  if (ratio > 1.1) return "Above value: offers come slowly and stay near the underground value."
  return "Around value: offers arrive at a normal pace."
})

// Estimated net = sale price minus the expenses recorded for this car (identity change). Shown with a word
// as well as a sign so profit, loss and break-even never rely on colour alone.
const net = (value, spent) => Math.round(Number(value) || 0) - Math.round(Number(spent) || 0)
const netText = (value, spent) => {
  const n = net(value, spent)
  if (n > 0) return `+${money(n)} profit`
  if (n < 0) return `−${money(-n)} loss`
  return `${money(0)} break-even`
}
const netTone = (value, spent) => { const n = net(value, spent); return n > 0 ? "profit" : n < 0 ? "loss" : "even" }
const expenseNote = computed(() => {
  const spent = Number(vehicle.value?.expenses) || 0
  const base = spent > 0 ? `After ${money(spent)} identity change.` : "No recorded expenses yet."
  return vehicle.value?.expensesPartial ? `${base} Repaint costs are not included.` : base
})

const stingText = "The deal is off and the car's new plate is burned. Lose the police: if they catch you, the car is seized and the theft fine is charged. To sell it again, change its identity and repaint it once more."

const resolved = computed(() => {
  const n = negotiation.value
  const result = n?.result
  if (result?.kind === "sold") {
    const partial = result.partial ? " (partial costs)" : ""
    return { title: `Sold for ${money(result.price)}`, text: `The money is in your account. Net ${netText(result.price, result.expenses)}${partial}.`, tone: "ok" }
  }
  if (result?.kind === "sting") return { title: "Undercover cop", text: stingText, tone: "bad" }
  if (result?.kind === "raided") return { title: "Police raid", text: "The buyer's contact recognized the paint. The vehicle was seized and the theft fine was charged.", tone: "bad" }
  if (n?.status === "failed") return { title: "No deal", text: "The buyer lost patience and walked away.", tone: "bad" }
  return { title: "Deal", text: "", tone: "ok" }
})

function call(expression) {
  api.engineLua(`if rlsVehicleTheft then rlsVehicleTheft.${expression} end`)
}

function applyState(next) {
  if (!mounted || !next) return
  state.value = next
}

watch(() => vehicle.value?.phase, phase => {
  if (phase === "ready" && !price.value) setPrice(vehicle.value.suggestedPrice)
  if (phase === "listed") setPrice(vehicle.value.listedPrice)
  editingPrice.value = false
}, { immediate: true })
watch(() => vehicle.value?.thumbnail, () => { thumbBroken.value = false })

function applyPrice() {
  call(`undergroundSetPrice(${price.value})`)
  editingPrice.value = false
}

// Phone Back: leave a negotiation first, then let the phone go home.
usePhoneScreen({
  onBack: () => {
    if (!negotiation.value) return false
    call(negotiation.value.result ? "undergroundDismissResult()" : "undergroundCancelNegotiation()")
    return true
  },
})

onMounted(() => {
  mounted = true
  controls.setup()
  refreshShortcutBindings()
  events.on(eventName, applyState)
  shortcutRefreshTimers = [250, 1000].map(delay => setTimeout(refreshShortcutBindings, delay))
  call("undergroundSetOpen(true)")
  api.engineLua("rlsVehicleTheft and rlsVehicleTheft.getUndergroundState()", next => {
    if (next) applyState(next)
    else if (mounted) state.value = { available: false }
  })
})

onUnmounted(() => {
  mounted = false
  shortcutRefreshTimers.forEach(clearTimeout)
  if (isCapturing.value) controls.cancelCaptureBinding()
  events.off("RawInputChanged", cancelCaptureOnEscape)
  events.off(eventName, applyState)
  call("undergroundSetOpen(false)")
  if (negotiation.value && !negotiation.value.result) call("undergroundCancelNegotiation()")
})
</script>

<style scoped lang="scss">
.ug {
  --ug-bg: #121317;
  --ug-panel: #1d1f26;
  --ug-line: #2e313b;
  --ug-text: #eef0f4;
  --ug-muted: #9aa1ad;
  --ug-accent: #f79040;
  --ug-good: #5fd99a;
  --ug-bad: #ff6b63;
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  background: radial-gradient(120% 60% at 50% 0%, #2a1712 0%, var(--ug-bg) 60%);
  color: var(--ug-text);
  font-size: 0.85rem;
}

.ug-negotiate {
  --nego-head-top: 42px;
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}

.ug-cases { display: flex; flex-wrap: wrap; gap: 0.35rem; align-items: center; margin-bottom: 0.6rem; }
.ug-case { padding: 0.25rem 0.6rem; border-radius: 1rem; border: 1px solid rgba(255, 255, 255, 0.25); background: transparent; color: inherit; font-size: 0.8rem; cursor: pointer; }
.ug-case.on { background: #e85d04; border-color: #e85d04; color: #fff; }
.ug-cases-note { margin-left: auto; font-size: 0.75rem; opacity: 0.7; }
.ug-skill { margin-bottom: 0.6rem; }
.ug-skill-row { display: flex; justify-content: space-between; font-size: 0.85rem; margin-bottom: 0.25rem; }
.ug-skill-bar { height: 0.3rem; border-radius: 0.2rem; background: rgba(255, 255, 255, 0.15); overflow: hidden; }
.ug-skill-bar > div { height: 100%; background: #e85d04; }
.ug-head {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 50px 1rem 0.75rem;
  h1 { margin: 0; font-size: 1.25rem; letter-spacing: 0.02em; }
  p { margin: 0.1rem 0 0; color: var(--ug-muted); font-size: 0.75rem; }
}
.ug-settings-toggle {
  margin-left: auto;
  padding: 0.4rem 0.65rem;
  border: 1px solid var(--ug-line);
  border-radius: 0.5rem;
  background: #262932;
  color: var(--ug-text);
  font-size: 0.75rem;
  font-weight: 600;
  cursor: pointer;
  display: grid;
  place-items: center;
  &.on { background: var(--ug-accent); color: #14161b; border-color: var(--ug-accent); }
  &:disabled { opacity: 0.45; cursor: default; }
}
.ug-settings { display: grid; gap: 0.7rem; }
.ug-settings h2 { margin: 0; font-size: 1rem; }
.ug-setting-copy { margin: 0.4rem 0 0.7rem; color: var(--ug-muted); line-height: 1.4; }
.ug-current-bindings { display: grid; gap: 0.2rem; margin: 0.4rem 0; }
.ug-current-bindings span, .ug-binding-status { color: var(--ug-muted); font-size: 0.75rem; }
.ug-binding-status { margin: 0.5rem 0 0; }

.ug-logo {
  flex: none;
  width: 2.2rem;
  height: 2.2rem;
  border-radius: 0.6rem;
  background: url("/ui/images/rls_vehicle_theft/underground.png") center / cover, #2a1712;
}

.ug-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 0 0.85rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.7rem;
}

.ug-empty {
  display: grid;
  gap: 0.35rem;
  margin-top: 2rem;
  text-align: center;
  color: var(--ug-muted);
  strong { color: var(--ug-text); font-size: 1rem; }
}

.ug-card, .ug-panel, .ug-offer, .ug-result {
  border: 1px solid var(--ug-line);
  border-radius: 0.8rem;
  background: var(--ug-panel);
  padding: 0.75rem;
}

.ug-card {
  display: flex;
  gap: 0.7rem;
  align-items: center;
}

.ug-thumb {
  flex: none;
  width: 5.2rem;
  height: 3.4rem;
  border-radius: 0.5rem;
  overflow: hidden;
  background: #0d0e11;
  img { width: 100%; height: 100%; object-fit: cover; }
}

.ug-card-info {
  display: grid;
  gap: 0.25rem;
  min-width: 0;
  strong { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
}

.ug-plate {
  justify-self: start;
  padding: 0.05rem 0.4rem;
  border-radius: 0.25rem;
  background: #f2f2f2;
  color: #16181d;
  font-family: monospace;
  font-weight: 700;
  font-size: 0.75rem;
}

.ug-badges { display: flex; flex-wrap: wrap; gap: 0.3rem; }
.badge {
  padding: 0.05rem 0.45rem;
  border-radius: 1rem;
  font-size: 0.68rem;
  font-weight: 600;
  &.good { background: rgba(95, 217, 154, 0.15); color: var(--ug-good); }
  &.bad { background: rgba(255, 107, 99, 0.15); color: var(--ug-bad); }
  &.warn { background: rgba(247, 144, 64, 0.15); color: var(--ug-accent); }
}

.ug-step, .ug-wait {
  margin: 0;
  padding: 0.7rem 0.75rem;
  border-radius: 0.6rem;
  background: rgba(247, 144, 64, 0.1);
  color: #f6c7a1;
}
.has-tip { position: relative; cursor: help; }
.ug-tip {
  display: none;
  position: absolute;
  top: calc(100% + 0.4rem);
  right: 0;
  z-index: 10;
  width: 15rem;
  max-width: 70vw;
  padding: 0.55rem 0.7rem;
  border: 1px solid var(--ug-line);
  border-radius: 0.5rem;
  background: #1b1e25;
  color: var(--ug-text);
  font-size: 0.74rem;
  font-weight: 400;
  line-height: 1.4;
  white-space: normal;
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.5);
}
.has-tip:hover .ug-tip, .has-tip:focus .ug-tip { display: block; }
.badge.heat-hot { background: rgba(255, 107, 99, 0.15); color: var(--ug-bad); }
.badge.heat-warm { background: rgba(231, 196, 91, 0.15); color: #e9d99d; }
.badge.heat-cold { background: rgba(95, 217, 154, 0.15); color: var(--ug-good); }
.ug-wait { background: transparent; color: var(--ug-muted); padding: 0.2rem 0.1rem; }

.ug-row {
  display: flex;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.15rem 0;
  span { color: var(--ug-muted); }
}

.ug-label { display: block; margin: 0.6rem 0 0.3rem; color: var(--ug-muted); font-size: 0.75rem; }

.ug-net, .ug-net-row, .ug-net-sub { font-size: 12px; opacity: 0.85; }
.ug-net { display: block; }
.ug-net-row { margin: 6px 0 0; }
.ug-net-sub { display: block; opacity: 0.65; margin-top: 2px; }
.profit { color: var(--ug-good, #5fd38d); }
.loss { color: var(--ug-bad, #ff6b6b); }
.ug-price {
  display: flex;
  gap: 0.35rem;
  button {
    flex: none;
    width: 2.2rem;
    border: 1px solid var(--ug-line);
    border-radius: 0.5rem;
    background: #262932;
    color: var(--ug-text);
    font-size: 1.1rem;
    cursor: pointer;
  }
  input {
    flex: 1;
    min-width: 0;
    padding: 0.45rem 0.6rem;
    border: 1px solid var(--ug-line);
    border-radius: 0.5rem;
    background: #0f1014;
    color: var(--ug-text);
    font-size: 1rem;
    font-weight: 700;
    text-align: center;
  }
}

.ug-hint { margin: 0.4rem 0 0; color: var(--ug-muted); font-size: 0.72rem; min-height: 1em; }
.ug-warning { margin: 0.6rem 0 0; color: var(--ug-bad); font-size: 0.75rem; }

.ug-actions {
  display: flex;
  gap: 0.4rem;
  margin-top: 0.6rem;
  .ug-btn { flex: 1; }
}

.ug-edit { display: grid; gap: 0.5rem; margin-top: 0.6rem; }

.ug-btn {
  padding: 0.5rem 0.6rem;
  border: 1px solid var(--ug-line);
  border-radius: 0.55rem;
  background: #262932;
  color: var(--ug-text);
  font-weight: 600;
  cursor: pointer;
  &.primary { border-color: var(--ug-accent); background: var(--ug-accent); color: #1b1006; }
  &.danger { color: var(--ug-bad); }
  &:disabled { opacity: 0.45; cursor: default; }
}

.ug-link {
  justify-self: start;
  padding: 0;
  border: 0;
  background: none;
  color: inherit;
  text-decoration: underline;
  cursor: pointer;
}

.ug-section {
  margin: 0.3rem 0 0;
  font-size: 0.95rem;
  span { color: var(--ug-muted); font-weight: 400; }
}

.ug-offer-top {
  display: flex;
  justify-content: space-between;
  gap: 0.5rem;
  > div { display: grid; gap: 0.1rem; }
}
.ug-archetype { color: var(--ug-muted); font-size: 0.72rem; }
.ug-offer-value {
  text-align: right;
  strong { font-size: 1.05rem; color: var(--ug-good); }
  span { color: var(--ug-muted); font-size: 0.72rem; font-variant-numeric: tabular-nums; }
  .urgent { color: var(--ug-bad); }
}
.ug-quote { margin: 0.45rem 0 0; color: #c9ced7; font-style: italic; }

.ug-result {
  display: grid;
  gap: 0.25rem;
  &.sold { border-color: rgba(95, 217, 154, 0.5); strong { color: var(--ug-good); } }
  &.raided, &.sting { border-color: rgba(255, 107, 99, 0.5); strong { color: var(--ug-bad); } }
  span { color: var(--ug-muted); }
}
</style>
