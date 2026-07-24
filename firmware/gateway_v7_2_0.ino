/*
 * ═══════════════════════════════════════════════════════════════════════
 *  ASSA SHUTTLE SERVICE — GATEWAY FIRMWARE v7.2.0
 *  MCU     : ESP32-S3
 *  Version : 7.2.0  (Shuttle LCD Integration, Fixed Offline Broadcasts)
 * ═══════════════════════════════════════════════════════════════════════
 */

#include <SPI.h>
#include <RadioLib.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <SD.h>
#include <FS.h>
#include <EEPROM.h>

struct RequestEntry;
struct ShuttleInfo;

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 1: CONFIGURATION & CONSTANTS
// ═══════════════════════════════════════════════════════════════════════

#define WIFI_SSID        "SMART8"
#define WIFI_PASSWORD    "AbduL322"

#define FB_PROJECT       "afit-shuttle-system"
#define FB_API_KEY       "AIzaSyAF_BdwMdTDqUd1_A5WxotigT2byEz49U4"
#define FB_RTDB_URL      "https://afit-shuttle-system-default-rtdb.firebaseio.com"
#define FB_GW_EMAIL      "gateway@afit-shuttle.app"
#define FB_GW_PASSWORD   "GatewaySecret123!"

#define FS_BASE          "https://firestore.googleapis.com/v1/projects/" FB_PROJECT "/databases/(default)/documents"
#define FB_AUTH_URL      "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" FB_API_KEY

#define PIN_LORA_NSS     10
#define PIN_LORA_RST     14
#define PIN_LORA_DIO0     4
#define PIN_LORA_SCK     12
#define PIN_LORA_MISO    13
#define PIN_LORA_MOSI    11
#define PIN_SD_CS         5
#define PIN_LED           2

#define EEPROM_SZ        64
#define EE_SEQ           0

#define HB_MS             30000UL
#define FB_POLL_MS        12000UL
#define WIFI_CHK_MS       45000UL
#define STATUS_MS         60000UL
#define TOKEN_REFRESH_MS  3300000UL
#define ASSIGN_TIMEOUT_MS 120000UL  
#define FB_RETRY_MS       5000UL
#define CLEANUP_MS        600000UL

#define RACE_WINDOW_MS    240000UL   // 4 minutes

#define ADDR_GTW    0x00
#define ADDR_AP1    0x01
#define ADDR_AP2    0x02
#define ADDR_AP3    0x03
#define ADDR_REP    0x04
#define ADDR_SH1    0x11
#define ADDR_SH2    0x12
#define ADDR_SH3    0x13
#define ADDR_SH4    0x14
#define ADDR_SH5    0x15
#define ADDR_BCAST  0xFF

#define NUM_SHUTTLES  5
#define QUEUE_SIZE    30

#define PKT_REQ   "REQ"
#define PKT_ASN   "ASN"
#define PKT_RSP   "RSP"
#define PKT_ACK   "ACK"
#define PKT_STS   "STS"
#define PKT_HBT   "HBT"
#define PKT_GHB   "GHB"
#define PKT_CAN   "CAN"
#define PKT_CONF  "CONF"

#define STATUS_PENDING    0
#define STATUS_ASSIGNED   1
#define STATUS_ACCEPTED   2
#define STATUS_REJECTED   4
#define STATUS_TAKEN      5

#define SD_REQ_LOG    "/requests.csv"
#define SD_EVENT_LOG  "/events.log"
#define SD_STATUS     "/status.txt"

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 2: DATA STRUCTURES
// ═══════════════════════════════════════════════════════════════════════

static const char* const LOC_NAMES[13] = {
  "", "AFIT Gates", "45x1 Hostel", "Old Girls Hostel", "TETFUND Hostel",
  "BK", "Boys Hostel", "Alfa Hall", "EED", "AFIT Mosque",
  "New Mechanical", "Centre of Entrepreneurship", "Hall A"
};

inline const char* locName(uint8_t c) {
  return (c >= 1 && c <= 12) ? LOC_NAMES[c] : "Unknown";
}

struct ShuttleInfo {
  uint8_t  addr;
  char     id[5];
  bool     available;
  uint32_t lastSeenMs;
  uint32_t handledCount;
  char     currentReq[40];
};

struct RequestEntry {
  char     bookingId[40];
  char     pickupId[6];
  char     userName[32];
  uint8_t  pickupCode;
  uint8_t  destCode;
  uint8_t  rideType;
  uint8_t  passengerCount;
  uint8_t  sourceAddr;
  char     requestType[10];

  uint8_t  acceptedByAddr;     
  char     acceptedById[5];      
  uint32_t broadcastMs;        
  uint32_t acceptedMs;         
  char     status[16];           

  uint8_t  winnerShuttleAddr;  
  uint32_t raceStartMs;        
  bool     raceClosed;         

  uint32_t createdMs;
  uint32_t lastRetryMs;
  uint8_t  retryCount;
  bool     firebaseWritten;
  bool     firebaseUpdated;
  bool     winnerNotified;
  bool     losersNotified;
};

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 3: GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════

static ShuttleInfo g_shuttles[NUM_SHUTTLES] = {
  {ADDR_SH1, "A001", true, 0, 0, ""},
  {ADDR_SH2, "A002", true, 0, 0, ""},
  {ADDR_SH3, "A003", true, 0, 0, ""},
  {ADDR_SH4, "A004", true, 0, 0, ""},
  {ADDR_SH5, "A005", true, 0, 0, ""},
};

static RequestEntry g_queue[QUEUE_SIZE];
static uint8_t     g_queueLength = 0;

static bool     g_radioOK = false;
static bool     g_sdOK    = false;
static bool     g_wifiOK  = false;
static uint16_t g_sequenceNum = 0;
static uint32_t g_rxCount = 0;
static uint32_t g_txCount = 0;

static char     g_firebaseToken[1200] = {0};
static uint32_t g_tokenTimestampMs = 0;

static uint32_t g_lastHeartbeatMs = 0;
static uint32_t g_lastPollMs = 0;
static uint32_t g_lastWifiCheckMs = 0;
static uint32_t g_lastStatusMs = 0;

static SPIClass loraSPI(FSPI);
static SX1278   radio(new Module(PIN_LORA_NSS, PIN_LORA_DIO0, PIN_LORA_RST, RADIOLIB_NC, loraSPI));

volatile bool packetReceived = false;
void IRAM_ATTR setFlag() {
  packetReceived = true;
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 4: PROTOCOL HELPERS
// ═══════════════════════════════════════════════════════════════════════

uint8_t calcCRC(const char* d) {
  uint8_t c = 0;
  while (*d) c ^= (uint8_t)(*d++);
  return c;
}

int buildPacket(char* buf, size_t blen, const char* type,
                uint8_t src, uint8_t dst, const char* sid,
                uint16_t seq, uint8_t hop, float vbat, const char* pay) {
  int n = snprintf(buf, blen,
    "{\"t\":\"%s\",\"src\":%u,\"dst\":%u,\"sid\":\"GTW\","
    "\"seq\":%u,\"hop\":%u,\"vbat\":%.1f,\"pay\":\"%s\"",
    type, src, dst, seq, hop, vbat, pay);
  if (n <= 0 || (size_t)n >= blen - 16) return 0;
  uint8_t crc = calcCRC(buf);
  int m = snprintf(buf + n, blen - n, ",\"crc\":%u}", crc);
  return (m > 0) ? n + m : 0;
}

bool validateCRC(const char* rawJson, uint8_t rxCRC) {
  const char* crcPos = strstr(rawJson, ",\"crc\"");
  if (!crcPos) return false;
  size_t len = (size_t)(crcPos - rawJson);
  static char tempBuf[300];
  if (len >= sizeof(tempBuf)) return false;
  memcpy(tempBuf, rawJson, len);
  tempBuf[len] = '\0';
  return calcCRC(tempBuf) == rxCRC;
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 5: FIREBASE AUTH
// ═══════════════════════════════════════════════════════════════════════

bool firebaseSignIn() {
  if (!g_wifiOK) {
    Serial.println(F("[FB-AUTH] Skipped: WiFi down"));
    return false;
  }
  Serial.println(F("[FB-AUTH] Signing in..."));

  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(10000);
  HTTPClient http;
  http.begin(client, FB_AUTH_URL);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(10000);

  char body[256];
  snprintf(body, sizeof(body),
    "{\"email\":\"%s\",\"password\":\"%s\",\"returnSecureToken\":true}",
    FB_GW_EMAIL, FB_GW_PASSWORD);

  int code = http.POST(String(body));
  String resp = http.getString();
  http.end();

  if (code != 200) {
    Serial.printf("[FB-AUTH] FAIL HTTP %d\n", code);
    return false;
  }

  StaticJsonDocument<2048> doc;
  if (deserializeJson(doc, resp.c_str())) return false;

  const char* tok = doc["idToken"];
  if (!tok || strlen(tok) == 0) return false;

  size_t len = strlen(tok);
  if (len >= sizeof(g_firebaseToken)) len = sizeof(g_firebaseToken) - 1;
  memcpy(g_firebaseToken, tok, len);
  g_firebaseToken[len] = '\0';
  g_tokenTimestampMs = millis();
  Serial.printf("[FB-AUTH] Success (%zu chars)\n", len);
  return true;
}

void ensureFirebaseToken() {
  bool need = false;
  if (g_firebaseToken[0] == '\0') {
    need = true;
  } else {
    uint32_t now = millis();
    if (now < g_tokenTimestampMs || (now - g_tokenTimestampMs) > TOKEN_REFRESH_MS) {
      need = true;
    }
  }
  if (need) {
    if (!firebaseSignIn()) Serial.println(F("[FB-AUTH] Refresh failed"));
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 6: HTTP HELPERS
// ═══════════════════════════════════════════════════════════════════════

bool httpPost(const char* url, const String& body, String& resp, bool retryOnAuthFail) {
  if (!g_wifiOK || g_firebaseToken[0] == '\0') return false;
  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(10000);
  HTTPClient http;
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", String("Bearer ") + g_firebaseToken);
  http.setTimeout(10000);
  int code = http.POST(body);
  resp = http.getString();
  http.end();
  
  if (code == 200 || code == 201) return true;
  if (code == 401 && retryOnAuthFail) {
    if (!firebaseSignIn()) return false;
    http.begin(client, url);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("Authorization", String("Bearer ") + g_firebaseToken);
    code = http.POST(body);
    resp = http.getString();
    http.end();
    return (code == 200 || code == 201);
  }
  return false;
}

bool httpPatch(const char* url, const String& body, String& resp, bool retryOnAuthFail) {
  if (!g_wifiOK || g_firebaseToken[0] == '\0') return false;
  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(10000);
  HTTPClient http;
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", String("Bearer ") + g_firebaseToken);
  http.setTimeout(10000);
  int code = http.PATCH(body);
  resp = http.getString();
  http.end();
  
  if (code == 200) return true;
  if (code == 401 && retryOnAuthFail) {
    if (!firebaseSignIn()) return false;
    http.begin(client, url);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("Authorization", String("Bearer ") + g_firebaseToken);
    code = http.PATCH(body);
    resp = http.getString();
    http.end();
    return (code == 200);
  }
  return false;
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 7: FIREBASE WRITE OPERATIONS
// ═══════════════════════════════════════════════════════════════════════

String fsStrF(const char* n, const char* v) { return String("\"") + n + "\":{\"stringValue\":\"" + v + "\"}"; }
String fsIntF(const char* n, int v) { return String("\"") + n + "\":{\"integerValue\":\"" + v + "\"}"; }
String fsBoolF(const char* n, bool v) { return String("\"") + n + "\":{\"booleanValue\":" + (v ? "true" : "false") + "}"; }
String fsNullF(const char* n) { return String("\"") + n + "\":{\"nullValue\":null}"; }

void firebasePushRTDB(const char* bookingId, int statusCode, const char* statusName) {
  if (!g_wifiOK || g_firebaseToken[0] == '\0') return;
  String url = String(FB_RTDB_URL) + "/rides/" + bookingId + ".json?auth=" + g_firebaseToken;
  char body[180];
  snprintf(body, sizeof(body),
    "{\"status\":%d,\"statusName\":\"%s\",\"gw\":\"GTW\"}", statusCode, statusName);
  
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, url);
  http.addHeader("Content-Type","application/json");
  http.PUT(String(body));
  http.end();
}

bool firebaseWriteOfflineRequest(RequestEntry& req) {
  ensureFirebaseToken();
  if (g_firebaseToken[0] == '\0') return false;

  char groupKey[16];
  snprintf(groupKey, sizeof(groupKey), "%u_%u", req.pickupCode, req.destCode);
  char srcLabel[8];
  snprintf(srcLabel, sizeof(srcLabel), "AP%u", req.sourceAddr);

  String body = "{\"fields\":{";
  body += fsStrF("bookingId", req.bookingId) + ",";
  body += fsStrF("userId", "offline") + ",";
  body += fsStrF("userName", req.userName) + ",";
  body += fsStrF("pickupId", req.pickupId) + ",";
  body += fsStrF("pickupLocation", locName(req.pickupCode)) + ",";
  body += fsStrF("destination", locName(req.destCode)) + ",";
  body += fsStrF("rideTypeName", req.rideType == 1 ? "Chartered" : "Shared") + ",";
  body += fsIntF("pickup_code", req.pickupCode) + ",";
  body += fsIntF("destination_code", req.destCode) + ",";
  body += fsIntF("ride_type", req.rideType) + ",";
  body += fsIntF("passengerCount", req.passengerCount) + ",";
  body += fsIntF("pax", req.passengerCount) + ",";
  body += fsIntF("status", STATUS_PENDING) + ",";
  body += fsStrF("statusName", "Pending") + ",";
  body += fsIntF("shuttle_id", 0) + ",";
  body += fsStrF("shuttleIdFeedback", "") + ",";
  body += fsStrF("requestType", "offline") + ",";
  body += fsStrF("groupKey", groupKey) + ",";
  body += fsStrF("srcNodeId", srcLabel) + ",";
  body += fsStrF("gatewayId", "GTW") + ",";
  body += fsBoolF("gatewayForwarded", true) + ",";
  body += fsBoolF("isSynced", false) + ",";
  body += fsStrF("intentStatus", "none") + ",";
  body += fsNullF("assignedAt") + ",";
  body += fsStrF("driverName", "") + ",";
  body += fsStrF("driverId", "");
  body += "}}";

  String url = String(FS_BASE) + "/ride_requests/" + req.bookingId + "?key=" + FB_API_KEY;
  String resp;
  bool ok = httpPost(url.c_str(), body, resp, true);

  if (ok) {
    req.firebaseWritten = true;
    firebasePushRTDB(req.bookingId, STATUS_PENDING, "Pending");
    Serial.printf("[FB] Written: %s\n", req.bookingId);
  }
  return ok;
}

bool firebaseUpdateStatus(const char* bookingId, int statusCode,
                          const char* statusName, const char* shuttleId,
                          const char* driverName, const char* driverId) {
  ensureFirebaseToken();
  if (g_firebaseToken[0] == '\0') return false;

  int shInt = 0;
  if (shuttleId && strlen(shuttleId) > 0) {
    const char* p = shuttleId;
    while (*p && !isdigit(*p)) p++;
    shInt = atoi(p);
  }

  String body = "{\"fields\":{";
  body += fsIntF("status", statusCode) + ",";
  body += fsStrF("statusName", statusName) + ",";
  body += fsIntF("shuttle_id", shInt) + ",";
  body += fsStrF("shuttleIdFeedback", shuttleId ? shuttleId : "") + ",";
  body += fsStrF("driverName", driverName ? driverName : "") + ",";
  body += fsStrF("driverId", driverId ? driverId : "") + ",";
  body += fsBoolF("gatewayForwarded", true) + ",";
  body += fsStrF("gatewayId", "GTW");
  body += "}}";

  String updateMask = "updateMask.fieldPaths=status&updateMask.fieldPaths=statusName&updateMask.fieldPaths=shuttle_id&updateMask.fieldPaths=shuttleIdFeedback&updateMask.fieldPaths=driverName&updateMask.fieldPaths=driverId&updateMask.fieldPaths=gatewayForwarded&updateMask.fieldPaths=gatewayId";

  String url = String(FS_BASE) + "/ride_requests/" + bookingId + "?" + updateMask + "&key=" + FB_API_KEY;
  String resp;
  bool ok = httpPatch(url.c_str(), body, resp, true);

  firebasePushRTDB(bookingId, statusCode, statusName);

  if (ok) Serial.printf("[FB] Updated: %s -> %s\n", bookingId, statusName);
  return ok;
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 8: FIREBASE POLL
// ═══════════════════════════════════════════════════════════════════════

void handleOnlineRequest(const char* bookingId, const char* userName, const char* pickupId, uint8_t pc, uint8_t dc, uint8_t rt, uint8_t pax);

void firebasePollOnlineRequests() {
  ensureFirebaseToken();
  if (g_firebaseToken[0] == '\0') return;

  String qUrl = String("https://firestore.googleapis.com/v1/projects/") + FB_PROJECT + "/databases/(default)/documents:runQuery?key=" + FB_API_KEY;
  String body = "{\"structuredQuery\":{\"from\":[{\"collectionId\":\"ride_requests\"}],\"where\":{\"compositeFilter\":{\"op\":\"AND\",\"filters\":[{\"fieldFilter\":{\"field\":{\"fieldPath\":\"gatewayForwarded\"},\"op\":\"EQUAL\",\"value\":{\"booleanValue\":false}}},{\"fieldFilter\":{\"field\":{\"fieldPath\":\"status\"},\"op\":\"EQUAL\",\"value\":{\"integerValue\":\"0\"}}}]}},\"limit\":10}}";

  String resp;
  if (!httpPost(qUrl.c_str(), body, resp, true)) return;
  if (resp.indexOf("\"error\"") >= 0) return;

  DynamicJsonDocument doc(8192);
  if (deserializeJson(doc, resp)) return;
  JsonArray results = doc.as<JsonArray>();
  if (results.isNull()) return;

  for (JsonObject result : results) {
    if (!result.containsKey("document")) continue;
    JsonObject document = result["document"];
    JsonObject fields = document["fields"];
    const char* docName = document["name"] | "";

    String docId = String(docName);
    int sl = docId.lastIndexOf('/');
    if (sl >= 0) docId = docId.substring(sl+1);
    if (docId.isEmpty()) continue;

    int pc = fields["pickup_code"]["integerValue"].as<int>();
    int dc = fields["destination_code"]["integerValue"].as<int>();
    int rt = fields["ride_type"]["integerValue"].as<int>();
    int pax = fields["pax"]["integerValue"].as<int>();

    if (docId.length() > 0 && pc > 0 && dc > 0) {
      if (g_queueLength >= QUEUE_SIZE) break;

      // Mark forwarded
      String markUrl = String(FS_BASE) + "/ride_requests/" + docId + "?updateMask.fieldPaths=gatewayForwarded&key=" + FB_API_KEY;
      String markBody = "{\"fields\":{" + fsBoolF("gatewayForwarded", true) + "}}";
      String markResp;
      if (!httpPatch(markUrl.c_str(), markBody, markResp, true)) continue;

      handleOnlineRequest(docId.c_str(), fields["userName"]["stringValue"] | "Passenger", fields["pickupId"]["stringValue"] | "", (uint8_t)pc, (uint8_t)dc, (uint8_t)rt, (uint8_t)pax);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 9: LORA TRANSMIT & REQUEST HANDLING
// ═══════════════════════════════════════════════════════════════════════

bool sendLoRaPacket(const char* type, uint8_t dst, const char* payload) {
  if (!g_radioOK) return false;
  g_sequenceNum++;
  static char pkt[300];
  if (buildPacket(pkt, sizeof(pkt), type, ADDR_GTW, dst, "GTW", g_sequenceNum, 0, 3.3f, payload) <= 0) return false;
  
  int s = radio.transmit(pkt);
  radio.startReceive();
  
  if (s != RADIOLIB_ERR_NONE) return false;
  g_txCount++;
  Serial.printf("[GTW] TX->0x%02X: %s\n", dst, pkt);
  return true;
}

RequestEntry* findRequest(const char* bookingId) {
  for (uint8_t i = 0; i < g_queueLength; i++) {
    if (strcmp(g_queue[i].bookingId, bookingId) == 0) return &g_queue[i];
  }
  return nullptr;
}

ShuttleInfo* findShuttle(uint8_t addr) {
  for (int i = 0; i < NUM_SHUTTLES; i++) {
    if (g_shuttles[i].addr == addr) return &g_shuttles[i];
  }
  return nullptr;
}

void broadcastToAllShuttles(RequestEntry& req) {
  char payload[100];
  
  char typeCh = (req.rideType == 1) ? 'C' : 'S';
  
  // ── FIX: REFORMATTED PAYLOAD FOR SHUTTLE V5.3.0 LCD COMPATIBILITY ──
  // Format: ID|PC|DEST|PAX|TYPE 
  snprintf(payload, sizeof(payload), "%s|%u|%u|%u|%c",
    (req.pickupId[0] != '\0') ? req.pickupId : "0", // Fallback to 0 if ID is empty
    req.pickupCode, 
    req.destCode, 
    req.passengerCount, 
    typeCh);

  for (int i = 0; i < NUM_SHUTTLES; i++) {
    if (g_shuttles[i].lastSeenMs > 0) {  
      g_shuttles[i].available = false;
      strlcpy(g_shuttles[i].currentReq, req.bookingId, sizeof(g_shuttles[i].currentReq));
    }
  }

  sendLoRaPacket(PKT_ASN, ADDR_BCAST, payload);

  req.raceStartMs = millis();
  strlcpy(req.status, "RACING", sizeof(req.status));
  req.winnerShuttleAddr = 0;
  req.raceClosed = false;

  Serial.printf("[GTW] RACE STARTED: %s\n", req.bookingId);
}

void handleRaceWinner(RequestEntry& req, ShuttleInfo* winner) {
  req.winnerShuttleAddr = winner->addr;
  req.raceClosed = true;
  strlcpy(req.status, "ACCEPTED", sizeof(req.status));
  winner->handledCount++;
  winner->available = false;

  char cfmPayload[220];
  snprintf(cfmPayload, sizeof(cfmPayload), "%s|%s|%s|%u|%u|%u|%u|%s|CONFIRMED",
    req.bookingId, req.userName, req.pickupId, req.pickupCode, req.destCode, req.rideType, req.passengerCount, req.requestType);
  sendLoRaPacket(PKT_CONF, winner->addr, cfmPayload);

  char takPayload[16];
  snprintf(takPayload, sizeof(takPayload), "%u", req.pickupCode); // Sends just the ID/PC back to cancel
  
  for (int i = 0; i < NUM_SHUTTLES; i++) {
    if (g_shuttles[i].addr != winner->addr && strcmp(g_shuttles[i].currentReq, req.bookingId) == 0) {
      sendLoRaPacket(PKT_CAN, g_shuttles[i].addr, takPayload);
      g_shuttles[i].available = true;
      g_shuttles[i].currentReq[0] = '\0';
    }
  }

  if (req.sourceAddr > 0) {
    char stsPayload[64];
    snprintf(stsPayload, sizeof(stsPayload), "%s|%d|Accepted|%s", req.bookingId, STATUS_ACCEPTED, winner->id);
    sendLoRaPacket(PKT_STS, req.sourceAddr, stsPayload);
  }

  if (g_wifiOK) {
    firebaseUpdateStatus(req.bookingId, STATUS_ACCEPTED, "Assigned", winner->id, req.userName, "");
  }
}

void handleRaceTimeout(RequestEntry& req) {
  req.raceClosed = true;
  strlcpy(req.status, "REJECTED", sizeof(req.status));

  for (int i = 0; i < NUM_SHUTTLES; i++) {
    if (strcmp(g_shuttles[i].currentReq, req.bookingId) == 0) {
      g_shuttles[i].available = true;
      g_shuttles[i].currentReq[0] = '\0';
    }
  }

  if (req.sourceAddr > 0) {
    char stsPayload[48];
    snprintf(stsPayload, sizeof(stsPayload), "%s|%d|No shuttle", req.bookingId, STATUS_REJECTED);
    sendLoRaPacket(PKT_STS, req.sourceAddr, stsPayload);
  }

  if (g_wifiOK) {
    firebaseUpdateStatus(req.bookingId, STATUS_REJECTED, "Rejected", "0", "", "");
  }
}

void handleShuttleResponse(const char* bookingId, const char* response, uint8_t shuttleAddr) {
  // In the new format, bookingId passed from the shuttle is actually just the Pickup ID
  // Let's find the matching ride by searching for pickupId instead of bookingId
  RequestEntry* req = nullptr;
  for (uint8_t i = 0; i < g_queueLength; i++) {
    if (strcmp(g_queue[i].pickupId, bookingId) == 0 || strcmp(g_queue[i].bookingId, bookingId) == 0) {
      req = &g_queue[i];
      break;
    }
  }
  
  ShuttleInfo* shuttle = findShuttle(shuttleAddr);

  if (!req || strcmp(req->status, "RACING") != 0 || req->raceClosed) return;

  if (strcmp(response, "ACCEPTED") == 0 && shuttle) {
    handleRaceWinner(*req, shuttle);
  } else if (shuttle) {
    shuttle->available = true;
    shuttle->currentReq[0] = '\0';
  }
}

void handleOfflineRequest(const char* bookingId, const char* userName, const char* pickupId, uint8_t pc, uint8_t dc, uint8_t rt, uint8_t pax, uint8_t srcAddr) {
  if (findRequest(bookingId) || g_queueLength >= QUEUE_SIZE) return;

  RequestEntry& r = g_queue[g_queueLength++];
  memset(&r, 0, sizeof(r));
  strlcpy(r.bookingId, bookingId, sizeof(r.bookingId));
  strlcpy(r.userName,  userName,  sizeof(r.userName));
  strlcpy(r.pickupId,  pickupId ? pickupId : "", sizeof(r.pickupId));
  
  if (r.pickupId[0] == '\0') {
    uint16_t shortId = 0;
    for (int i=0; r.bookingId[i]; i++) shortId = (shortId * 31) + r.bookingId[i];
    snprintf(r.pickupId, sizeof(r.pickupId), "%u", shortId % 10000);
  }

  r.pickupCode = pc; r.destCode = dc; r.rideType = rt; r.passengerCount = pax;
  r.sourceAddr = srcAddr;
  strlcpy(r.requestType, "offline", sizeof(r.requestType));
  strlcpy(r.status, "PENDING", sizeof(r.status));
  r.createdMs = millis();

  // ── FIX: BROADCAST BEFORE BLOCKING FIREBASE CALL ─────────────────
  // This completely prevents offline requests from timing out or being 
  // delayed by slow HTTP calls to Firebase!
  broadcastToAllShuttles(r);

  if (g_wifiOK) firebaseWriteOfflineRequest(r);
}

void handleOnlineRequest(const char* bookingId, const char* userName, const char* pickupId, uint8_t pc, uint8_t dc, uint8_t rt, uint8_t pax) {
  if (findRequest(bookingId) || g_queueLength >= QUEUE_SIZE) return;

  RequestEntry& r = g_queue[g_queueLength++];
  memset(&r, 0, sizeof(r));
  strlcpy(r.bookingId, bookingId, sizeof(r.bookingId));
  strlcpy(r.userName,  userName,  sizeof(r.userName));
  strlcpy(r.pickupId,  pickupId ? pickupId : "", sizeof(r.pickupId));
  r.pickupCode = pc; r.destCode = dc; r.rideType = rt; r.passengerCount = pax;
  r.sourceAddr = 0;
  strlcpy(r.requestType, "online", sizeof(r.requestType));
  strlcpy(r.status, "PENDING", sizeof(r.status));
  r.createdMs = millis();
  r.firebaseWritten = true;
  
  broadcastToAllShuttles(r);
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 10: LORA RX PROCESSING
// ═══════════════════════════════════════════════════════════════════════

void processReceivedPacket(const String& rawStr, int rssi) {
  const char* raw = rawStr.c_str();

  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, raw) != DeserializationError::Ok) return;

  uint8_t rxCRC = doc["crc"] | 0;
  if (!validateCRC(raw, rxCRC)) return;

  const char* type = doc["t"] | "";
  uint8_t src = doc["src"] | 0xFF;
  const char* sid = doc["sid"] | "UNK";
  const char* pay = doc["pay"] | "";

  if (strcmp(type, PKT_REQ) == 0) {
    char buf[220]; 
    strlcpy(buf, pay, sizeof(buf));

    char* bkId  = strtok(buf, "|");
    char* uname = strtok(NULL, "|");
    char* pid   = strtok(NULL, "|");
    char* pcStr = strtok(NULL, "|");
    char* dcStr = strtok(NULL, "|");
    char* rtStr = strtok(NULL, "|");
    char* paxS  = strtok(NULL, "|");

    if (!bkId || !uname || !pcStr || !dcStr) return;

    char ack[48]; snprintf(ack, sizeof(ack), "%s|OK", bkId);
    sendLoRaPacket(PKT_ACK, src, ack);

    // ── FIX: DELAY BEFORE ASN BROADCAST TO PREVENT REPEATER COLLISION ──
    // The Gateway sends an ACK to the AP node, and immediately sends an ASN. 
    // The Repeater is busy relaying the ACK and completely misses the ASN!
    // This 1500ms delay ensures the Repeater is ready to receive the ASN.
    delay(1500);

    handleOfflineRequest(bkId, uname, pid ? pid : "",
                         pcStr ? (uint8_t)atoi(pcStr) : 0,
                         dcStr ? (uint8_t)atoi(dcStr) : 0,
                         rtStr ? (uint8_t)atoi(rtStr) : 0,
                         paxS ? (uint8_t)atoi(paxS) : 1,
                         src);
  }
  else if (strcmp(type, PKT_RSP) == 0) {
    char buf[60]; strlcpy(buf, pay, sizeof(buf));
    char* idStr = strtok(buf, "|");
    char* resp = strtok(NULL, "|");
    if (idStr && resp) handleShuttleResponse(idStr, resp, src);
  }
  else if (strcmp(type, PKT_HBT) == 0) {
    ShuttleInfo* sh = findShuttle(src);
    if (sh) {
      sh->lastSeenMs = millis();
      if (!sh->available && sh->currentReq[0] == '\0') sh->available = true;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION 11: SETUP & LOOP
// ═══════════════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  delay(600);
  Serial.println(F("\n╔═══════════════════════════════════════╗"));
  Serial.println(F("║  ASSA GATEWAY  v7.2.0  (ESP32-S3)    ║"));
  Serial.println(F("║  Optimized Offline Broadcasts        ║"));
  Serial.println(F("╚═══════════════════════════════════════╝\n"));

  pinMode(PIN_LED, OUTPUT);
  EEPROM.begin(EEPROM_SZ);
  memset(g_queue, 0, sizeof(g_queue));

  loraSPI.begin(PIN_LORA_SCK, PIN_LORA_MISO, PIN_LORA_MOSI, PIN_LORA_NSS);
  int s = radio.begin(433.0, 125.0, 10, 7, 0x34, 15);
  if (s == RADIOLIB_ERR_NONE) {
    radio.setCRC(true);
    radio.setPreambleLength(8);
    g_radioOK = true;
    
    radio.setPacketReceivedAction(setFlag);
    radio.startReceive();
    Serial.println(F("[LoRa] Non-Blocking mode started"));
  }

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 20) { delay(500); retry++; }
  g_wifiOK = (WiFi.status() == WL_CONNECTED);
  
  if (g_wifiOK) firebaseSignIn();
}

void loop() {
  uint32_t now = millis();

  if (now - g_lastHeartbeatMs >= HB_MS) {
    g_lastHeartbeatMs = now;
    char pay[64];
    snprintf(pay, sizeof(pay), "GTW|3.3|q=%u|wifi=%s", g_queueLength, g_wifiOK ? "Y" : "N");
    sendLoRaPacket(PKT_GHB, ADDR_BCAST, pay);
  }

  if (g_wifiOK && (now - g_lastPollMs >= FB_POLL_MS)) {
    g_lastPollMs = now;
    firebasePollOnlineRequests();
  }

  uint32_t cleanNow = millis();
  for (int i = 0; i < g_queueLength; i++) {
    RequestEntry& req = g_queue[i];
    if (strcmp(req.status, "RACING") == 0 && !req.raceClosed && (cleanNow - req.raceStartMs) >= RACE_WINDOW_MS) {
      handleRaceTimeout(req);
    }
  }

  for (int i = (int)g_queueLength - 1; i >= 0; i--) {
    if ((strcmp(g_queue[i].status, "ACCEPTED") == 0 || strcmp(g_queue[i].status, "REJECTED") == 0) &&
        (cleanNow - g_queue[i].createdMs) > CLEANUP_MS) {
      for (int j = i; j < (int)g_queueLength - 1; j++) g_queue[j] = g_queue[j + 1];
      g_queueLength--;
    }
  }

  if (packetReceived) {
    packetReceived = false;
    String rxStr;
    int state = radio.readData(rxStr);
    
    if (state == RADIOLIB_ERR_NONE) {
      g_rxCount++;
      processReceivedPacket(rxStr, radio.getRSSI());
    }
    
    radio.startReceive(); 
  }

  delay(5);
}
