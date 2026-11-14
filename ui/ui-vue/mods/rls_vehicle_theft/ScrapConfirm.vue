<template>
  <div class="scrap-overlay">
    <section class="scrap-panel" role="alertdialog" aria-modal="true" aria-labelledby="scrap-title">
      <h1 id="scrap-title">No free garage slot</h1>

      <template v-if="state">
        <p>Every slot in your garages is taken, so this car cannot be stored. Have a crew strip it for parts instead?</p>
        <ul class="scrap-facts">
          <li><span>Payment</span><strong>{{ state.rate }}% of its value</strong></li>
          <li><span>Time</span><strong>{{ state.seconds }} s</strong></li>
          <li><span>Theft report</span><strong :class="{ hot: state.hot }">{{ state.heatLabel }}</strong></li>
        </ul>
        <p class="note">
          The crew takes the car away. You are paid when they finish, and you can follow it in the Underground app.
          A hot car pays less. If you decline, the car stays with you.
        </p>
        <footer class="scrap-actions">
          <BngButton class="primary" @click="send('accept')">Strip for parts</BngButton>
          <BngButton accent="secondary" @click="send('decline')">Keep the car</BngButton>
        </footer>
      </template>

      <template v-else>
        <p role="status">{{ unavailable ? "There is nothing to confirm." : "Loading…" }}</p>
        <BngButton accent="secondary" @click="close">Return to driving</BngButton>
      </template>
    </section>
  </div>
</template>

<script setup>
import { onMounted, onUnmounted, shallowRef } from "vue"
import { BngButton } from "@/common/components/base"
import { useBridge } from "@/bridge"

const { api } = useBridge()
const state = shallowRef(null)
const unavailable = shallowRef(false)
let mounted = false

function send(action) {
  const token = state.value?.token
  if (!Number.isSafeInteger(token)) return
  api.engineLua(`rlsVehicleTheft.scrapInput(${token}, "${action}")`)
}

function close() {
  if (state.value) send("decline")
  else api.engineLua('extensions.ui_router.navigate("play")')
}

function onKeyDown(event) {
  if (event.repeat || event.code !== "Escape") return
  event.preventDefault()
  close()
}

onMounted(() => {
  mounted = true
  window.addEventListener("keydown", onKeyDown)
  api.engineLua("rlsVehicleTheft and rlsVehicleTheft.getScrapState()", next => {
    if (!mounted) return
    if (next && Number.isSafeInteger(next.token)) state.value = next
    else unavailable.value = true
  })
})

onUnmounted(() => {
  mounted = false
  window.removeEventListener("keydown", onKeyDown)
  send("leave")
})
</script>

<style scoped>
.scrap-overlay {
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

.scrap-panel {
  box-sizing: border-box;
  width: min(100%, 30rem);
  max-height: 100%;
  overflow: auto;
  padding: clamp(1.25rem, 3vw, 2rem);
  border: 1px solid #464e58;
  border-top: 3px solid #f79040;
  border-radius: 0.8rem;
  background: #1b2026;
  box-shadow: 0 1.25rem 4rem rgb(0 0 0 / 45%);
}

h1 {
  margin: 0;
  font-size: clamp(1.4rem, 4vw, 1.8rem);
  line-height: 1.15;
}

p {
  margin: 0.7rem 0 0;
  color: #c7cfd8;
  line-height: 1.4;
}

.note {
  font-size: 0.88rem;
  color: #b5bfca;
}

.scrap-facts {
  margin: 1rem 0 0;
  padding: 0;
  list-style: none;
  border: 1px solid #3d454f;
  border-radius: 0.5rem;
}

.scrap-facts li {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.55rem 0.8rem;
}

.scrap-facts li + li {
  border-top: 1px solid #3d454f;
}

.scrap-facts span {
  color: #b5bfca;
}

.scrap-facts .hot {
  color: #ff847d;
}

.scrap-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
  margin-top: 1.1rem;
}

.scrap-actions .primary {
  flex: 1;
}
</style>
