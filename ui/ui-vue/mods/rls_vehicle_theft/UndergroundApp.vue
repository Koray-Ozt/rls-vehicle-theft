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
      </header>

      <main class="ug-body">
        <div v-if="!state" class="ug-empty">Connecting…</div>
        <div v-else-if="!state.available" class="ug-empty">Only available in an RLS career.</div>

        <template v-else>
          <section v-if="state.result" class="ug-result" :class="state.result.kind">
            <strong v-if="state.result.kind === 'sold'">Sold for {{ money(state.result.price) }}</strong>
            <strong v-else>Police raided the handover</strong>
            <span v-if="state.result.kind === 'sold'">The money is in your account.</span>
            <span v-else>The vehicle was seized and the theft fine was charged.</span>
            <button class="ug-link" @click="call('undergroundDismissResult()')">Dismiss</button>
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
                  <span v-if="vehicle.hot" class="badge warn">Hot · lower prices</span>
                </div>
              </div>
            </section>

            <p v-if="vehicle.phase === 'transit'" class="ug-step">Store it first: park inside a garage you own and get out.</p>
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
                <div class="ug-actions">
                  <button class="ug-btn ghost" @click="setPrice(vehicle.suggestedPrice)">Suggested</button>
                  <button class="ug-btn primary" :disabled="!(price > 0)" @click="call(`undergroundList(${price})`)">List for sale</button>
                </div>
                <p v-if="vehicle.repainted === false" class="ug-warning">
                  The paint still matches the theft report. One in five handovers gets raided. Repaint it at the garage computer first.
                </p>
              </section>
            </template>

            <template v-else-if="vehicle.phase === 'listed'">
              <section class="ug-panel">
                <div class="ug-row"><span>Listed at</span><strong>{{ money(vehicle.listedPrice) }}</strong></div>
                <div class="ug-row"><span>Underground value</span><span>{{ money(vehicle.marketValue) }}</span></div>
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
                    <span :class="{ urgent: offer.expiresIn <= 30 }">{{ clock(offer.expiresIn) }}</span>
                  </div>
                </div>
                <p class="ug-quote">“{{ offer.quote }}”</p>
                <div class="ug-actions">
                  <button class="ug-btn ghost" @click="call(`undergroundDecline(${offer.id})`)">Decline</button>
                  <button class="ug-btn ghost" :disabled="offer.value >= vehicle.listedPrice" @click="call(`undergroundNegotiate(${offer.id})`)">Negotiate</button>
                  <button class="ug-btn primary" @click="call(`undergroundAccept(${offer.id})`)">Accept</button>
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
import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from "vue"
import { icons } from "@/common/components/base"
import { useBridge } from "@/bridge"
import NegotiationChatWindow from "../rls_career_overhaul/overhaul/modules/career/components/negotiation/NegotiationChatWindow.vue"
import { usePhoneScreen } from "../rls_career_overhaul/overhaul/modules/career/composables/usePhoneScreen.js"

const { api, events } = useBridge()
const eventName = "RlsTheftUnderground"
const state = shallowRef(null)
const thumbBroken = ref(false)
const editingPrice = ref(false)
const priceText = ref("")
let mounted = false

const vehicle = computed(() => state.value?.vehicle || null)
const offers = computed(() => state.value?.offers || [])
const negotiation = computed(() => state.value?.negotiation || null)

const money = value => `$${Math.round(Number(value) || 0).toLocaleString()}`
const clock = seconds => {
  const s = Math.max(0, Math.round(Number(seconds) || 0))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
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

const resolved = computed(() => {
  const n = negotiation.value
  const result = n?.result
  if (result?.kind === "sold") return { title: `Sold for ${money(result.price)}`, text: "The money is in your account.", tone: "ok" }
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
  events.on(eventName, applyState)
  call("undergroundSetOpen(true)")
  api.engineLua("rlsVehicleTheft and rlsVehicleTheft.getUndergroundState()", next => {
    if (next) applyState(next)
    else if (mounted) state.value = { available: false }
  })
})

onUnmounted(() => {
  mounted = false
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

.ug-head {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 50px 1rem 0.75rem;
  h1 { margin: 0; font-size: 1.25rem; letter-spacing: 0.02em; }
  p { margin: 0.1rem 0 0; color: var(--ug-muted); font-size: 0.75rem; }
}

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
.ug-wait { background: transparent; color: var(--ug-muted); padding: 0.2rem 0.1rem; }

.ug-row {
  display: flex;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.15rem 0;
  span { color: var(--ug-muted); }
}

.ug-label { display: block; margin: 0.6rem 0 0.3rem; color: var(--ug-muted); font-size: 0.75rem; }

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
  &.raided { border-color: rgba(255, 107, 99, 0.5); strong { color: var(--ug-bad); } }
  span { color: var(--ug-muted); }
}
</style>
