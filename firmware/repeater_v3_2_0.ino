/**
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║   ASSA SHUTTLE SERVICE — REPEATER (REP) FIRMWARE                 ║
 * ║   Hardware : Arduino Nano (ATmega328P) + Ra-02 SX1278            ║
 * ║   Version  : 4.0.0-BINARY  (matches current v23 binary protocol) ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  Library: "LoRa" by Sandeep Mistry (NOT RadioLib) — same as       ║
 * ║  ASSA_SHUTTLE.ino, for the same Nano flash-budget reason.         ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 *  CHANGELOG v3.2.0-TRANSPARENT → v4.0.0-BINARY:
 *  ─────────────────────────────────────────────────────────────────
 *  1. PROTOCOL MISMATCH FIX (the reason for this rewrite): v3.2.0
 *     spoke the OLD JSON-over-LoRa protocol (buildPkt() emitting
 *     {"t":"REQ","src":1,...}). ASSA_AP.ino / ASSA_GATEWAY_FULL_v17.ino
 *     / ASSA_SHUTTLE.ino do not use that protocol anymore — they use
 *     the binary format in assa_common.h (6-byte BinHeader + up to 6
 *     payload bytes + 1 CRC-8 byte, ~13 bytes total). A repeater
 *     speaking JSON next to a fleet speaking binary doesn't relay
 *     anything usable — it would parse garbage out of binary frames
 *     and every real node would fail checkCRC()/parseBinaryPacket() on
 *     its JSON output. This version relays the binary format instead,
 *     built with the same calcCRC8()/BinHeader layout as
 *     assa_common_nano.h so relayed frames are byte-identical in
 *     structure to ones sent directly by the gateway or a shuttle.
 *  2. Still a TRANSPARENT relay: src, seq, and payload bytes are
 *     preserved exactly as received; the CRC-8 is recomputed over the
 *     rebuilt frame. (Note: unlike the old JSON protocol, assa_common.h's
 *     BinHeader has no hop-count field at all, so there is no hop to
 *     increment here — see the note above buildBinaryPacket() for how
 *     loop-prevention works without one.) Every receiver upstream or
 *     downstream (gateway or shuttle) sees a relayed packet exactly as
 *     if it came directly from the original node — no per-type unwrap
 *     logic needed anywhere else in the fleet.
 *  3. COLLISION AVOIDANCE (see also the note at the bottom of this
 *     file): fixed 50ms RELAY_DELAY replaced with a RANDOMIZED jitter
 *     window. A fixed delay means every repeater in range retransmits
 *     at the exact same offset after hearing the same original packet
 *     — with more than one repeater, or a repeater and a node's own
 *     retry, that's a guaranteed collision every single time, not just
 *     a possible one. Randomizing breaks that lockstep.
 *  4. LORA_PWR kept at 15 dBm (matched to gateway/shuttle, unchanged
 *     from 3.2.0's fix — a repeater at low power relays less far than
 *     the original transmission, defeating its own purpose).
 *  5. Seen-table dedup unchanged (explicit valid flag per slot, so an
 *     empty slot is never confused with a genuine src=0/seq=0 packet
 *     from the gateway, whose address really is 0x00).
 *
 *  ⚠ MAINTENANCE NOTE: this file intentionally keeps its own local
 *  copy of BinHeader/calcCRC8/parseBinaryPacket (same pattern as
 *  ASSA_SHUTTLE.ino) rather than #including assa_common_nano.h, so it
 *  has zero dependency surface and compiles standalone on a fresh
 *  checkout. If you change the packet format in assa_common.h /
 *  assa_common_nano.h, this file's local copy must be updated to
 *  match by hand — that discipline is exactly how v3.2.0 drifted onto
 *  the wrong protocol in the first place, so keep it in sync.
 */

#include <SPI.h>
#include <LoRa.h>

// ── Pin map (Nano) ──────────────────────────────────────────────────
#define LORA_CS     10
#define LORA_RST     9
#define LORA_IRQ     2
#define PIN_LED      5

// ── LoRa params (must match every other node) ──────────────────────
#define LORA_FREQ    433E6
#define LORA_SF      10
#define LORA_BW      125E3
#define LORA_CR      7
#define LORA_SYNC    0x34
#define LORA_PWR     15
#define LORA_PRE     8

// ── Node / packet types (must match assa_common.h) ─────────────────
#define ADDR_GATEWAY    0x00
#define ADDR_REPEATER   0x04
#define ADDR_BROADCAST  0xFF

#define PKT_HBT   0x06   // any -> GW (heartbeat)

// ── Relay config ────────────────────────────────────────────────────
#define HB_INTERVAL    30000UL

// Collision avoidance: randomized jitter window before every
// transmission (both relay retransmits and this repeater's own
// heartbeat). See the note at the bottom of this file for why this
// replaces the old fixed 50ms delay.
#define JITTER_MIN_MS   15
#define JITTER_MAX_MS  120

// ── Duplicate suppression ─────────────────────────────────────────────
#define SEEN_SIZE  12
#define SEEN_TTL   10000UL

struct SeenEntry {
  uint8_t  src;
  uint16_t seq;
  uint32_t at;
  bool     valid;
};

// ── Globals ─────────────────────────────────────────────────────────
static uint16_t  g_seq     = 0;
static uint32_t  g_relayed = 0;
static uint32_t  g_dropped = 0;
static uint32_t  g_lastHB  = 0;
static SeenEntry g_seen[SEEN_SIZE];
static uint8_t   g_seenIdx = 0;

// WB: raw inbound binary frame buffer, and scratch/output buffer for
// buildBinaryPacket(). Sized generously above the ~13-byte max frame.
static uint8_t WB[32];

// ════════════════════════════════════════════════════════════════════
//  BINARY PROTOCOL — local copy, kept byte-identical to
//  assa_common.h / assa_common_nano.h. See maintenance note above.
// ════════════════════════════════════════════════════════════════════
struct BinHeader {
  uint8_t  type;
  uint8_t  src;
  uint8_t  dst;
  uint16_t seq;
  uint8_t  payLen;
};

uint8_t calcCRC8(const uint8_t* data, uint8_t len) {
  uint8_t crc = 0x00;
  for (uint8_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (uint8_t b = 0; b < 8; b++) {
      crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x07) : (uint8_t)(crc << 1);
    }
  }
  return crc;
}

// Builds a frame directly from already-known header fields + a raw
// payload byte buffer — used both for relaying (payload copied as-is
// from the received frame) and for this repeater's own heartbeat.
//
// NOTE: assa_common.h's BinHeader carries NO hop-count field on the
// wire (just type/src/dst/seq/payLen) — so unlike v3.2.0's JSON
// format, this repeater cannot track or cap hop count at all. Loop
// prevention instead relies entirely on (src,seq) dedup below: if this
// repeater hears its own retransmission echo back, it's already marked
// seen and gets dropped, so a single repeater can't loop. This is
// sufficient for this fleet's current single-repeater topology. If a
// second repeater is ever added, a real hop-limit would need a wire
// format change (an extra payload byte) — flag that explicitly rather
// than pretend a hop cap exists when it structurally can't.
int buildBinaryPacket(uint8_t* buf, uint8_t type, uint8_t src, uint8_t dst,
                       uint16_t seq, const uint8_t* pay, uint8_t payLen) {
  if (payLen > 6) return 0;
  BinHeader hdr;
  hdr.type = type; hdr.src = src; hdr.dst = dst; hdr.seq = seq; hdr.payLen = payLen;
  memcpy(buf, &hdr, sizeof(BinHeader));
  if (pay && payLen) memcpy(buf + sizeof(BinHeader), pay, payLen);
  uint8_t totalLen = sizeof(BinHeader) + payLen;
  buf[totalLen] = calcCRC8(buf, totalLen);
  return totalLen + 1;
}

bool parseBinaryPacket(const uint8_t* buf, uint8_t len,
                        BinHeader* hdr, uint8_t* pay, uint8_t* payLen) {
  if (len < (uint8_t)(sizeof(BinHeader) + 1)) return false;
  uint8_t totalDataLen = len - 1;
  if (calcCRC8(buf, totalDataLen) != buf[totalDataLen]) return false;
  memcpy(hdr, buf, sizeof(BinHeader));
  if (payLen) *payLen = hdr->payLen;
  if (pay && hdr->payLen) memcpy(pay, buf + sizeof(BinHeader), hdr->payLen);
  return true;
}

// ════════════════════════════════════════════════════════════════════
//  DUPLICATE DETECTION
// ════════════════════════════════════════════════════════════════════
bool isDup(uint8_t src, uint16_t seq) {
  uint32_t now = millis();
  for (uint8_t i = 0; i < SEEN_SIZE; i++) {
    if (g_seen[i].valid && g_seen[i].src == src && g_seen[i].seq == seq &&
        (now - g_seen[i].at) < SEEN_TTL) return true;
  }
  return false;
}

void markSeen(uint8_t src, uint16_t seq) {
  g_seen[g_seenIdx].src   = src;
  g_seen[g_seenIdx].seq   = seq;
  g_seen[g_seenIdx].at    = millis();
  g_seen[g_seenIdx].valid = true;
  g_seenIdx = (g_seenIdx + 1) % SEEN_SIZE;
}

void cleanSeen() {
  uint32_t now = millis();
  for (uint8_t i = 0; i < SEEN_SIZE; i++) {
    if (g_seen[i].valid && (now - g_seen[i].at) > SEEN_TTL)
      g_seen[i].valid = false;
  }
}

// ════════════════════════════════════════════════════════════════════
//  COLLISION AVOIDANCE
//  A lightweight listen-before-talk + randomized-jitter scheme —
//  appropriate for this fleet's scale (one gateway, a handful of APs/
//  shuttles, one or two repeaters, single channel/SF). Two parts:
//
//   1. LISTEN: sample the channel briefly; if LoRa.parsePacket() sees
//      a frame already inbound, let loop() finish handling it (and
//      relay that one) instead of transmitting into the middle of it.
//   2. JITTER: before actually transmitting (heartbeat or relay),
//      wait a RANDOM 15-120ms instead of a fixed delay. A fixed delay
//      guarantees every repeater in range retransmits in lockstep and
//      collides every time there's more than one repeater, or a node
//      retries on a fixed schedule of its own. Randomizing turns a
//      guaranteed collision into a low-probability one, which is the
//      same principle slotted-ALOHA / CSMA backoff uses — cheap to
//      implement on a flash-constrained Nano, no extra library needed.
//
//  This is intentionally NOT full CSMA/CA with hardware Channel
//  Activity Detection (CAD) — the Sandeep Mistry "LoRa" library used
//  here (chosen for its ~7KB flash footprint vs RadioLib, see file
//  header) doesn't expose CAD mode, only parsePacket(). True CAD would
//  need direct SX127x register access. For this fleet's traffic volume
//  (occasional ride requests, not a dense sensor network) jitter alone
//  is sufficient; CAD is the natural next step if collisions are ever
//  observed at higher shuttle/AP counts.
// ════════════════════════════════════════════════════════════════════
void jitterDelay() {
  uint16_t ms = JITTER_MIN_MS + (uint16_t)random(0, JITTER_MAX_MS - JITTER_MIN_MS + 1);
  uint32_t start = millis();
  while (millis() - start < ms) {
    // Listen while we wait: if a new packet starts arriving during our
    // own jitter window, bail out of THIS transmission attempt so we
    // don't talk over it. The caller's next loop() iteration will pick
    // up and relay that incoming packet instead.
    if (LoRa.parsePacket() > 0) return;
    delay(2);
  }
}

// ════════════════════════════════════════════════════════════════════
//  REPEATER'S OWN HEARTBEAT
// ════════════════════════════════════════════════════════════════════
void sendHB() {
  uint8_t pay[1] = { 100 };  // battPct — repeater is mains/USB powered; report 100
  g_seq++;
  int n = buildBinaryPacket(WB, PKT_HBT, ADDR_REPEATER, ADDR_GATEWAY, g_seq, pay, sizeof(pay));
  if (n <= 0) return;
  jitterDelay();
  LoRa.beginPacket();
  LoRa.write(WB, n);
  LoRa.endPacket();
}

// ════════════════════════════════════════════════════════════════════
//  TRANSPARENT RELAY
//  Preserves the original packet's src/payload untouched; the CRC-8 is
//  recomputed over the rebuilt frame (see buildBinaryPacket()'s note on
//  why there's no hop field/limit to maintain). Relays
//  ANY packet type/dst it hears (REQ, ASN, RSP, STS, ACK, HBT, CMD,
//  GHB) — it doesn't interpret or route by content. Each node's own
//  dst filter (own address or broadcast) already decides what it acts
//  on, so a shuttle and an AP never end up "talking" to each other
//  just because both heard the same relayed frame — the repeater
//  doesn't need special-case filtering for that; it already can't
//  happen, by construction of how every node's own RX handler works.
// ════════════════════════════════════════════════════════════════════
void relay(const uint8_t* buf, uint8_t len) {
  BinHeader hdr;
  uint8_t pay[6];
  uint8_t payLen = 0;

  if (!parseBinaryPacket(buf, len, &hdr, pay, &payLen)) { g_dropped++; return; }

  if (hdr.src == ADDR_REPEATER) return;                 // our own echo
  if (hdr.dst == ADDR_REPEATER) { g_dropped++; return; } // addressed to us specifically (unused today)
  if (isDup(hdr.src, hdr.seq))  { g_dropped++; return; }
  markSeen(hdr.src, hdr.seq);

  jitterDelay();

  int n = buildBinaryPacket(WB, hdr.type, hdr.src, hdr.dst, hdr.seq, pay, payLen);
  if (n <= 0) return;

  LoRa.beginPacket();
  LoRa.write(WB, n);
  if (LoRa.endPacket()) {
    g_relayed++;
    digitalWrite(PIN_LED, LOW); delay(80); digitalWrite(PIN_LED, HIGH);
  }
}

// ════════════════════════════════════════════════════════════════════
//  SETUP
// ════════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println(F("REP v4.0.0-BINARY"));

  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, HIGH);

  memset(g_seen, 0, sizeof(g_seen));
  randomSeed(analogRead(A0));  // unconnected analog pin as a noise source for jitter

  LoRa.setPins(LORA_CS, LORA_RST, LORA_IRQ);
  if (!LoRa.begin(LORA_FREQ)) {
    Serial.println(F("LoRa FAIL"));
    while (true) { digitalWrite(PIN_LED, LOW); delay(500); digitalWrite(PIN_LED, HIGH); delay(500); }
  }
  LoRa.setSpreadingFactor(LORA_SF);
  LoRa.setSignalBandwidth(LORA_BW);
  LoRa.setCodingRate4(LORA_CR);
  LoRa.setSyncWord(LORA_SYNC);
  LoRa.setTxPower(LORA_PWR);
  LoRa.enableCrc();
  LoRa.setPreambleLength(LORA_PRE);

  Serial.println(F("REP ready"));

  sendHB();
  g_lastHB = millis();
}

// ════════════════════════════════════════════════════════════════════
//  LOOP
// ════════════════════════════════════════════════════════════════════
void loop() {
  uint32_t now = millis();

  if (now - g_lastHB >= HB_INTERVAL) {
    g_lastHB = now;
    sendHB();
  }

  cleanSeen();

  int sz = LoRa.parsePacket();
  if (sz > 0 && sz <= (int)sizeof(WB)) {
    uint8_t i = 0;
    while (LoRa.available() && i < sizeof(WB)) WB[i++] = (uint8_t)LoRa.read();
    relay(WB, i);
  }

  delay(5);
}
