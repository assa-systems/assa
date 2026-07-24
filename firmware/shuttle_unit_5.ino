/*
 * ═══════════════════════════════════════════════════════════════════════
 *  ASSA SHUTTLE SERVICE — SHUTTLE UNIT FIRMWARE (16×2 LCD VERSION)
 *  MCU     : Arduino Nano (ATmega328P)
 *  Display : 16×2 LCD via I2C PCF8574 backpack
 *  Version : 5.3.0  (Added 4-Ride Stacking, Abbreviations, Ride Types)
 * ═══════════════════════════════════════════════════════════════════════
 *
 *  ⚠ NEW GATEWAY PAYLOAD REQUIREMENT (PKT_ASN):
 *  To support the new LCD features, the Gateway must send assignments as:
 *  "ID|PC|DEST|PAX|TYPE"
 *  Example: "1024|2|8|2|S"
 *    - ID   = Pickup ID (e.g., 1024)
 *    - PC   = Pickup Location Index (1-12)
 *    - DEST = Destination Location Index (1-12)
 *    - PAX  = Passengers requested
 *    - TYPE = 'S' (Shared) or 'C' (Chartered)
 *
 *  ─── TO FLASH EACH SHUTTLE UNIT, CHANGE THESE TWO LINES ────────────
 *  Shuttle 1 (AFIT-001):  #define THIS_SH_ADDR  0x15   #define THIS_SH_ID    "A005"
 *  ...
 *  Shuttle 5 (AFIT-005):  #define THIS_SH_ADDR  0x15   #define THIS_SH_ID    "A005"
 * ═══════════════════════════════════════════════════════════════════════
 */

#include <SPI.h>
#include <LoRa.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <EEPROM.h>

// ── CHANGE THESE TWO LINES FOR EACH SHUTTLE UNIT ──────────────────
#define THIS_SH_ADDR  0x15    
#define THIS_SH_ID    "A005"   
// ──────────────────────────────────────────────────────────────────

// ── Protocol constants ────────────────────────────────────────────
#define ADDR_GATEWAY  0x00
#define ADDR_BCAST    0xFF
#define LORA_SF       10
#define LORA_BW       125E3
#define LORA_CR       7
#define LORA_SYNC     0x34
#define LORA_PWR      15
#define LORA_PRE      8

#define PKT_ASN  "ASN"
#define PKT_RSP  "RSP"
#define PKT_ACK  "ACK"
#define PKT_HBT  "HBT"
#define PKT_GHB  "GHB"
#define PKT_CMD  "CMD"
#define PKT_CAN  "CAN"

#define HB_MS    30000UL

// ── Pins ──────────────────────────────────────────────────────────
#define LORA_CS    10
#define LORA_RST    9
#define LORA_IRQ    2
#define PIN_BLUE    5
#define PIN_RED     6
#define PIN_BUZZ    7
#define PIN_ACCEPT  3   // Accept pending ride, or "Reply" back to app
#define PIN_REJECT  4   // Reject pending ride, or "Complete" top ride in queue

// ── EEPROM ────────────────────────────────────────────────────────
#define EE_SEQ  0
#define EE_HDL  2

// ── Timing ────────────────────────────────────────────────────────
#define AUTO_REJ_MS   55000UL   // 55 seconds - matches Gateway
#define SCROLL_MS      3500UL
#define CONFIRM_MS     4000UL
#define DEBOUNCE_MS      50UL
#define BLINK_MS        600UL
#define CAN_DISPLAY_MS  2500UL
#define LCD_CYCLE_MS   3000UL   // 3 seconds between stacked/detail view

// ── LCD ───────────────────────────────────────────────────────────
#define LCD_ADDR   0x27 // Change to 0x3F if screen is blank
#define LCD_COLS   16
#define LCD_ROWS    2

// ── Location names & Abbreviations ────────────────────────────────
static const char* const LOCS[13] = {
  "",
  "AFIT Gates",
  "45x1 Hostel",
  "Old Girls Hos",
  "TETFUND Hos",
  "BK",
  "Boys Hostel",
  "Alfa Hall",
  "EED",
  "AFIT Mosque",
  "New Mechanical",
  "Entrepreneur",
  "Hall A",
};

static const char* const ABBR[13] = {
  "---",
  "AGT", // 1
  "45H", // 2
  "OGH", // 3
  "TFH", // 4
  "BKG", // 5
  "BYH", // 6
  "AFH", // 7
  "EED", // 8
  "MSQ", // 9
  "NME", // 10
  "EPC", // 11
  "HLA"  // 12
};

inline const char* locN(uint8_t c) { return (c >= 1 && c <= 12) ? LOCS[c] : "Unknown"; }
inline const char* locA(uint8_t c) { return (c >= 1 && c <= 12) ? ABBR[c] : "---"; }

// ── Objects ───────────────────────────────────────────────────────
LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);

// ── Queue & State machine ─────────────────────────────────────────
typedef enum : uint8_t {
  ST_IDLE,       // No queue, no pending request
  ST_QUEUE,      // Queue active, cycling screens
  ST_REQ,        // Incoming assignment waiting for ACCEPT/REJECT
  ST_CONFIRM,    // Temporary "ACCEPTED" / "REJECTED" message
  ST_CANCELLED   // Temporary "CANCELLED" message
} State_t;

#define MAX_QUEUE 4

struct Ride {
  uint16_t id;
  uint8_t  pc;
  uint8_t  dest;
  uint8_t  pax;
  char     type; // 'S' or 'C'
};

static Ride g_queue[MAX_QUEUE];
static uint8_t g_qCount = 0;

// Temporary struct for incoming unaccepted rides
struct Req {
  uint16_t id;
  uint8_t  pc;
  uint8_t  dest;
  uint8_t  pax;
  char     type;
  uint32_t rxT;
  bool     valid;
};

static char WB[140];
static char PAY[24];

static State_t  g_st     = ST_IDLE;
static Req      g_req    = {0};
static uint16_t g_seq    = 0;
static uint32_t g_hd     = 0;
static bool     g_gwOK   = false;
static int      g_rssi   = 0;
static uint32_t g_lastHB = 0;
static uint32_t g_confAt = 0;
static uint32_t g_lastBl = 0;
static bool     g_blSt   = false;
static bool     g_pAcc   = true, g_pRej = true;
static uint32_t g_tAcc   = 0,   g_tRej = 0;

static bool g_lcdShowDetails = false;
static uint32_t g_lastLcdCycle = 0;

// ════════════════════════════════════════════════════════════════
//  QUEUE HELPERS
// ════════════════════════════════════════════════════════════════
bool enqueueRide(uint16_t id, uint8_t pc, uint8_t dest, uint8_t pax, char type) {
  if (g_qCount >= MAX_QUEUE) return false;
  if (type == 'C') pax = 4; // Chartered forces 4 passengers
  
  g_queue[g_qCount].id = id;
  g_queue[g_qCount].pc = pc;
  g_queue[g_qCount].dest = dest;
  g_queue[g_qCount].pax = pax;
  g_queue[g_qCount].type = type;
  g_qCount++;
  
  if (g_st == ST_IDLE) g_st = ST_QUEUE;
  return true;
}

void dequeueRide() {
  if (g_qCount == 0) return;
  for (uint8_t i = 1; i < g_qCount; i++) {
    g_queue[i - 1] = g_queue[i];
  }
  g_qCount--;
  if (g_qCount == 0 && g_st == ST_QUEUE) g_st = ST_IDLE;
}

// ════════════════════════════════════════════════════════════════
//  PROTOCOL HELPERS
// ════════════════════════════════════════════════════════════════
uint8_t calcCRC(const char* d) {
  uint8_t c = 0;
  while (*d) c ^= (uint8_t)(*d++);
  return c;
}

int buildPacket(char* buf, size_t blen, const char* type,
                uint8_t src, uint8_t dst, const char* sid,
                uint16_t seq, uint8_t hop, float vbat, const char* pay) {
  int n = snprintf(buf, blen,
    "{\"t\":\"%s\",\"src\":%u,\"dst\":%u,\"sid\":\"%s\","
    "\"seq\":%u,\"hop\":%u,\"vbat\":%.1f,\"pay\":\"%s\"",
    type, src, dst, sid, seq, hop, vbat, pay);
  if (n <= 0 || (size_t)n >= blen - 14) return 0;
  uint8_t crc = calcCRC(buf);
  int m = snprintf(buf + n, blen - n, ",\"crc\":%u}", crc);
  return (m > 0) ? n + m : 0;
}

bool validateCRC(const char* raw, uint8_t rxCRC) {
  const char* cp = strstr(raw, ",\"crc\"");
  if (!cp) return false;
  size_t len = (size_t)(cp - raw);
  if (len >= sizeof(WB)) return false;
  memcpy(WB, raw, len);
  WB[len] = '\0';
  return calcCRC(WB) == rxCRC;
}

bool jGet(const char* json, const char* key, char* out, uint8_t ol) {
  char pat[18];
  snprintf(pat, sizeof(pat), "\"%s\":", key);
  const char* p = strstr(json, pat);
  if (!p) { out[0] = '\0'; return false; }
  p += strlen(pat);
  bool q = (*p == '"');
  if (q) p++;
  uint8_t i = 0;
  while (*p && i < ol - 1) {
    char e = q ? '"' : ',';
    char e2 = q ? '"' : '}';
    if (*p == e || *p == e2) break;
    out[i++] = *p++;
  }
  out[i] = '\0';
  return true;
}

// ════════════════════════════════════════════════════════════════
//  LCD HELPERS
// ════════════════════════════════════════════════════════════════
void lcdRow(uint8_t row, const char* str) {
  lcd.setCursor(0, row);
  uint8_t len = (uint8_t)strnlen(str, LCD_COLS);
  for (uint8_t i = 0; i < LCD_COLS; i++) {
    lcd.write(i < len ? (uint8_t)str[i] : ' ');
  }
}

void lcdRowF(uint8_t row, const char* fmt, ...) {
  char buf[17];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  lcdRow(row, buf);
}

void drawIdle() {
  lcdRowF(0, "%-4s AVAILABLE", THIS_SH_ID);
  int rssiAbs = (g_rssi < 0) ? -g_rssi : g_rssi;
  lcdRowF(1, "%s R:-%d H:%lu", g_gwOK ? "GW:OK" : "GW:--", rssiAbs, g_hd);
}

void drawQueue() {
  if (g_lcdShowDetails) {
    // Top Ride Details View
    lcdRowF(0, "#%u %s->%s", g_queue[0].id, locA(g_queue[0].pc), locA(g_queue[0].dest));
    if (g_queue[0].type == 'C') {
      lcdRowF(1, "Pax:%u (Charter)", g_queue[0].pax);
    } else {
      lcdRowF(1, "Pax:%u (Shared)", g_queue[0].pax);
    }
  } else {
    // Stacked 4-Ride View
    char r0[17] = "                ";
    char r1[17] = "                ";
    
    if (g_qCount >= 1) snprintf(r0, sizeof(r0), "%u %s", g_queue[0].id, locA(g_queue[0].pc));
    if (g_qCount >= 2) {
      int len = strlen(r0);
      snprintf(r0 + len, sizeof(r0) - len, "|%u %s", g_queue[1].id, locA(g_queue[1].pc));
    }
    
    if (g_qCount >= 3) snprintf(r1, sizeof(r1), "%u %s", g_queue[2].id, locA(g_queue[2].pc));
    if (g_qCount >= 4) {
      int len = strlen(r1);
      snprintf(r1 + len, sizeof(r1) - len, "|%u %s", g_queue[3].id, locA(g_queue[3].pc));
    }
    
    lcdRow(0, r0);
    lcdRow(1, r1);
  }
}

void drawReqPage() {
  lcdRow(0, "NEW REQUEST!    ");
  lcdRowF(1, "#%u %s->%s", g_req.id, locA(g_req.pc), locA(g_req.dest));
}

void drawConfirm(bool acc) {
  if (acc) {
    lcdRow(0, "  ** ACCEPTED **");
    lcdRowF(1, "Added to Queue! ");
  } else {
    lcdRow(0, "  -- REJECTED --");
    lcdRow(1, "Next rider...   ");
  }
}

void drawCancelled() {
  lcdRow(0, "  -- CANCELLED --");
  lcdRow(1, "Taken by other SH");
}

void drawError(const char* line0, const char* line1) {
  lcdRow(0, line0);
  lcdRow(1, line1 ? line1 : "                ");
}

// ════════════════════════════════════════════════════════════════
//  LORA HELPERS
// ════════════════════════════════════════════════════════════════
bool txPkt(const char* type, uint8_t dst, const char* pay) {
  g_seq++;
  if (buildPacket(WB, sizeof(WB), type, THIS_SH_ADDR, dst, THIS_SH_ID,
                  g_seq, 0, 5.0f, pay) <= 0)
    return false;
  LoRa.beginPacket();
  LoRa.print(WB);
  bool ok = LoRa.endPacket();
  Serial.print(ok ? F("TX OK ") : F("TX FAIL "));
  Serial.println(type);
  return ok;
}

void sendHB() {
  snprintf(PAY, sizeof(PAY), "%s|5.0|%lu", THIS_SH_ID, g_hd);
  txPkt(PKT_HBT, ADDR_GATEWAY, PAY);
}

void sendResp(uint16_t id, const char* r) {
  snprintf(PAY, sizeof(PAY), "%u|%s", id, r);
  txPkt(PKT_RSP, ADDR_GATEWAY, PAY);
}

// ════════════════════════════════════════════════════════════════
//  BUZZER & LED
// ════════════════════════════════════════════════════════════════
void bz(uint16_t ms) {
  digitalWrite(PIN_BUZZ, HIGH);
  delay(ms);
  digitalWrite(PIN_BUZZ, LOW);
}

void bzN(uint8_t n, uint16_t on, uint16_t off) {
  for (uint8_t i = 0; i < n; i++) {
    bz(on);
    delay(off);
  }
}

// ════════════════════════════════════════════════════════════════
//  BUTTON READ
// ════════════════════════════════════════════════════════════════
bool readBtn(uint8_t pin, bool& prev, uint32_t& lt) {
  bool cur = digitalRead(pin);
  if (cur != prev && (millis() - lt > DEBOUNCE_MS)) {
    lt = millis();
    prev = cur;
    if (cur == LOW) return true;
  }
  return false;
}

// ════════════════════════════════════════════════════════════════
//  EEPROM
// ════════════════════════════════════════════════════════════════
void loadEE() {
  EEPROM.get(EE_SEQ, g_seq);
  EEPROM.get(EE_HDL, g_hd);
  if (g_seq == 0xFFFFU) g_seq = 0;
  if (g_hd == 0xFFFFFFFFUL) g_hd = 0;
}

void saveEE() {
  EEPROM.put(EE_SEQ, g_seq);
  EEPROM.put(EE_HDL, g_hd);
}

// ════════════════════════════════════════════════════════════════
//  LORA RX HANDLER
// ════════════════════════════════════════════════════════════════
void checkLoRa() {
  int sz = LoRa.parsePacket();
  if (sz <= 0) return;

  uint8_t i = 0;
  while (LoRa.available() && i < sizeof(WB) - 1)
    WB[i++] = (char)LoRa.read();
  WB[i] = '\0';
  g_rssi = LoRa.packetRssi();

  Serial.print(F("RX: "));
  Serial.println(WB);

  char vT[4], vD[4], vP[32], vC[5];
  jGet(WB, "t",   vT, sizeof(vT));
  jGet(WB, "dst", vD, sizeof(vD));
  jGet(WB, "crc", vC, sizeof(vC));
  jGet(WB, "pay", vP, sizeof(vP));

  uint8_t dst = (uint8_t)atoi(vD);
  if (dst != THIS_SH_ADDR && dst != ADDR_BCAST) return;
  if (!validateCRC(WB, (uint8_t)atoi(vC))) {
    Serial.println(F("CRC fail"));
    return;
  }

  // ── RIDE ASSIGNMENT (ASN) ─────────────────────────────────────
  if (strcmp(vT, PKT_ASN) == 0) {
    char* idStr  = strtok(vP, "|");
    char* pcStr  = strtok(NULL, "|");
    char* destStr= strtok(NULL, "|");
    char* paxStr = strtok(NULL, "|");
    char* typeStr= strtok(NULL, "|");

    if (!idStr || !pcStr || !destStr || !paxStr || !typeStr) return;
    
    uint16_t id = (uint16_t)atoi(idStr);
    uint8_t pc  = (uint8_t)atoi(pcStr);
    uint8_t dest= (uint8_t)atoi(destStr);
    uint8_t pax = (uint8_t)atoi(paxStr);
    char type = typeStr[0];

    // Reject if queue is full or we are already answering one
    if (g_qCount >= MAX_QUEUE || g_st == ST_REQ) {
      sendResp(id, "REJECTED");
      return;
    }

    g_req.id    = id;
    g_req.pc    = pc;
    g_req.dest  = dest;
    g_req.pax   = pax;
    g_req.type  = type;
    g_req.rxT   = millis();
    g_req.valid = true;
    
    // Store old state to return to
    g_st = ST_REQ;

    digitalWrite(PIN_BLUE, LOW);
    digitalWrite(PIN_RED,  HIGH);
    bzN(2, 380, 140);

    drawReqPage();

    Serial.println(F("ASN Received"));
  }

  // ── CANCEL from Gateway ──────────────────────────────────────
  else if (strcmp(vT, PKT_CAN) == 0) {
    uint16_t canId = (uint16_t)atoi(vP);

    // If it cancels the incoming prompt
    if (g_req.valid && canId == g_req.id) {
      g_req.valid = false;
      g_st = ST_CANCELLED;
      g_confAt = millis();
      digitalWrite(PIN_RED,  LOW);
      digitalWrite(PIN_BLUE, HIGH);
      bzN(2, 100, 100);
      lcd.clear();
      drawCancelled();
      return;
    }
    
    // Check if it cancels a ride already in queue
    for (uint8_t i = 0; i < g_qCount; i++) {
      if (g_queue[i].id == canId) {
        Serial.println(F("Ride cancelled from queue"));
        // Remove from queue array
        for (uint8_t j = i + 1; j < g_qCount; j++) g_queue[j - 1] = g_queue[j];
        g_qCount--;
        if (g_qCount == 0) g_st = ST_IDLE;
        
        bzN(2, 100, 100);
        lcd.clear();
        drawCancelled();
        g_st = ST_CANCELLED; // Temporarily show message
        g_confAt = millis();
        break;
      }
    }
  }

  // ── GATEWAY HEARTBEAT ────────────────────────────────────────
  else if (strcmp(vT, PKT_GHB) == 0) {
    g_gwOK = true;
    digitalWrite(PIN_BLUE, LOW);
    delay(60);
    if (g_st == ST_IDLE || g_st == ST_QUEUE) digitalWrite(PIN_BLUE, HIGH);
  }
}

// ════════════════════════════════════════════════════════════════
//  SETUP
// ════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  Serial.println(F("ASSA Shuttle LCD v5.3.0"));
  Serial.print(F("Unit: "));
  Serial.println(F(THIS_SH_ID));

  pinMode(PIN_BLUE,   OUTPUT);
  pinMode(PIN_RED,    OUTPUT);
  pinMode(PIN_BUZZ,   OUTPUT);
  pinMode(PIN_ACCEPT, INPUT_PULLUP);
  pinMode(PIN_REJECT, INPUT_PULLUP);
  digitalWrite(PIN_BLUE, HIGH);
  digitalWrite(PIN_RED,  LOW);
  digitalWrite(PIN_BUZZ, LOW);

  loadEE();

  Wire.begin();
  lcd.init();
  lcd.backlight();
  lcd.clear();

  lcdRowF(0, "ASSA  Unit %-4s", THIS_SH_ID);
  lcdRow (1, " Firmware v5.3.0");
  delay(1500);

  LoRa.setPins(LORA_CS, LORA_RST, LORA_IRQ);
  if (!LoRa.begin(433E6)) {
    Serial.println(F("LoRa FAIL"));
    drawError("LoRa FAILED!", "Check SPI wiring");
    while (true) {
      digitalWrite(PIN_RED, HIGH); delay(400);
      digitalWrite(PIN_RED, LOW);  delay(400);
    }
  }
  LoRa.setSpreadingFactor(LORA_SF);
  LoRa.setSignalBandwidth(LORA_BW);
  LoRa.setCodingRate4(LORA_CR);
  LoRa.setSyncWord(LORA_SYNC);
  LoRa.setTxPower(LORA_PWR);
  LoRa.enableCrc();
  LoRa.setPreambleLength(LORA_PRE);

  digitalWrite(PIN_RED, HIGH);
  bz(200); delay(100); bz(200);
  digitalWrite(PIN_RED, LOW);

  lcd.clear();
  drawIdle();

  sendHB();
  g_lastHB = millis();
}

// ════════════════════════════════════════════════════════════════
//  LOOP
// ════════════════════════════════════════════════════════════════
void loop() {
  uint32_t now = millis();

  // Heartbeat
  if (now - g_lastHB >= HB_MS) {
    g_lastHB = now;
    sendHB();
  }

  // Auto-reject if driver ignores
  if (g_st == ST_REQ && g_req.valid && (now - g_req.rxT > AUTO_REJ_MS)) {
    Serial.println(F("Auto-reject (timeout)"));
    sendResp(g_req.id, "REJECTED");
    bzN(4, 140, 90);
    g_req.valid = false;
    
    g_st = (g_qCount > 0) ? ST_QUEUE : ST_IDLE;
    digitalWrite(PIN_RED,  LOW);
    digitalWrite(PIN_BLUE, HIGH);
    lcd.clear();
  }

  // Clear cancelled/confirm screen -> Return to IDLE or QUEUE
  if ((g_st == ST_CANCELLED && (now - g_confAt > CAN_DISPLAY_MS)) ||
      (g_st == ST_CONFIRM   && (now - g_confAt > CONFIRM_MS))) {
    g_st = (g_qCount > 0) ? ST_QUEUE : ST_IDLE;
    digitalWrite(PIN_BLUE, HIGH);
    digitalWrite(PIN_RED,  LOW);
    lcd.clear();
    if (g_st == ST_IDLE) drawIdle();
  }

  // Cycle Queue Screens every 3s
  if (g_st == ST_QUEUE && (now - g_lastLcdCycle > LCD_CYCLE_MS)) {
    g_lastLcdCycle = now;
    g_lcdShowDetails = !g_lcdShowDetails;
    drawQueue();
  }

  // Blink RED LED during active incoming request
  if (g_st == ST_REQ && (now - g_lastBl > BLINK_MS)) {
    g_lastBl = now;
    g_blSt   = !g_blSt;
    digitalWrite(PIN_RED, g_blSt ? HIGH : LOW);
  }

  // ── ACCEPT / REPLY BUTTON (Pin 3) ─────────────────────────────
  if (readBtn(PIN_ACCEPT, g_pAcc, g_tAcc)) {
    if (g_st == ST_REQ && g_req.valid) {
      // 1. Accepting a new incoming ride
      sendResp(g_req.id, "ACCEPTED");
      enqueueRide(g_req.id, g_req.pc, g_req.dest, g_req.pax, g_req.type);
      g_hd++;
      saveEE();

      digitalWrite(PIN_RED,  LOW);
      digitalWrite(PIN_BLUE, HIGH);
      bz(400);

      g_req.valid = false;
      g_st = ST_CONFIRM;
      g_confAt = now;
      lcd.clear();
      drawConfirm(true);

    } else if (g_st == ST_QUEUE) {
      // 2. Reply back to app for the top ride in the queue
      Serial.println(F("Reply sent to app for top ride"));
      sendResp(g_queue[0].id, "REPLY_MSG");
      bz(100);
      
    } else {
      // 3. Manual Ping
      sendHB();
    }
  }

  // ── REJECT / DONE BUTTON (Pin 4) ──────────────────────────────
  if (readBtn(PIN_REJECT, g_pRej, g_tRej)) {
    if (g_st == ST_REQ && g_req.valid) {
      // 1. Rejecting a new incoming ride
      sendResp(g_req.id, "REJECTED");
      bzN(3, 110, 80);

      g_req.valid = false;
      g_st = ST_CONFIRM;
      g_confAt = now;
      lcd.clear();
      drawConfirm(false);

    } else if (g_st == ST_QUEUE) {
      // 2. Completing the top ride in the queue!
      Serial.println(F("Top ride completed! Removing from queue."));
      sendResp(g_queue[0].id, "COMPLETED");
      dequeueRide();
      
      bzN(2, 200, 100);
      
      if (g_st == ST_IDLE) {
        lcd.clear();
        drawIdle();
      } else {
        lcd.clear();
        drawQueue();
      }
    }
  }

  checkLoRa();

  // Refresh idle display ~1 Hz
  static uint32_t lastDrw = 0;
  if (g_st == ST_IDLE && (now - lastDrw > 1000UL)) {
    lastDrw = now;
    drawIdle();
  }

  delay(10);
}

