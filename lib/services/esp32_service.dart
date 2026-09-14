import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ASSA Campus Locations & Lookup Service
/// (WiFi-scanning/ESP32 network methods removed — static lookups only)
/// ═══════════════════════════════════════════════════════════════════════════

class Esp32Service {
  // ── SINGLETON ───────────────────────────────────────────────────────────
  Esp32Service._internal();
  static final Esp32Service instance = Esp32Service._internal();
  factory Esp32Service() => instance;

  // ── Location Data ──────────────────────────────────────────────────────
  static const List<String> allLocations = [
    'AFIT Gates',
    '45x1 Hostel',
    'Old Girls Hostel',
    'TETFUND Hostel',
    'BK',
    'Boys Hostel',
    'Alfa Hall',
    'EED',
    'AFIT Mosque',
    'New Mechanical',
    'Centre of Entrepreneurship',
    'Hall A',
  ];

  static const List<String> offlinePickupLocations = allLocations;

  static const Map<String, int> locationCodeMap = {
    'AFIT Gates':                 1,
    '45x1 Hostel':                2,
    'Old Girls Hostel':           3,
    'TETFUND Hostel':             4,
    'BK':                         5,
    'Boys Hostel':                6,
    'Alfa Hall':                  7,
    'EED':                        8,
    'AFIT Mosque':                9,
    'New Mechanical':            10,
    'Centre of Entrepreneurship':11,
    'Hall A':                    12,
  };

  static const Map<String, String> locationAbbrevMap = {
    'AFIT Gates':                 'AGT',
    '45x1 Hostel':                '45H',
    'Old Girls Hostel':           'OGH',
    'TETFUND Hostel':             'TFH',
    'BK':                         'BKG',
    'Boys Hostel':                'BYH',
    'Alfa Hall':                  'AFH',
    'EED':                        'EED',
    'AFIT Mosque':                'MSQ',
    'New Mechanical':             'NME',
    'Centre of Entrepreneurship': 'EPC',
    'Hall A':                     'HLA',
  };

  static const Map<String, String> locationShortName = {
    'AFIT Gates':                 'AFIT Gates',
    '45x1 Hostel':                '45x1 Hostel',
    'Old Girls Hostel':           'Old Girls Hos.',
    'TETFUND Hostel':             'TETFUND Hos.',
    'BK':                         'BK',
    'Boys Hostel':                'Boys Hostel',
    'Alfa Hall':                  'Alfa Hall',
    'EED':                        'EED',
    'AFIT Mosque':                'AFIT Mosque',
    'New Mechanical':             'New Mechanical',
    'Centre of Entrepreneurship': 'Entrepreneur.',
    'Hall A':                     'Hall A',
  };

  // ─── AFIT KEKE ID Mapping ────────────────────────────────────────────────
  static String getPublicShuttleId(String internalId) {
    if (internalId.isEmpty) return '';
    final match = RegExp(r'SH(\d+)').firstMatch(internalId);
    if (match != null) {
      final num = int.tryParse(match.group(1)!) ?? 0;
      if (num >= 1 && num <= 16) {
        return 'AFIT-${num.toString().padLeft(3, '0')}';
      }
    }
    if (internalId.startsWith('AFIT-')) return internalId;
    return internalId;
  }

  static String publicShuttleFromAddr(int addr) {
    if (addr >= 0x11 && addr <= 0x20) {
      final num = addr - 0x10;
      return 'AFIT-${num.toString().padLeft(3, '0')}';
    }
    return '';
  }

  // ─── Packet Building ────────────────────────────────────────────────────
  static Uint8List buildPacket({
    required String pickupId,
    required String pickup,
    required String dest,
    required String rideType,
    required int pax,
    int apId = 1,
  }) {
    final pc = locationCodeMap[pickup] ?? 0;
    final dc = locationCodeMap[dest] ?? 0;
    final rt = rideType == 'Chartered' ? 1 : 0;
    final paxC = (rideType == 'Chartered' ? 1 : pax.clamp(1, 4));
    final rtPax = ((rt & 0x0F) << 4) | (paxC & 0x0F);

    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final buf = Uint8List(15);

    buf[0] = 0xA5;
    buf[1] = pickupId.isNotEmpty ? pickupId.codeUnitAt(0) : 0x3F;
    buf[2] = pickupId.length > 1 ? pickupId.codeUnitAt(1) : 0x30;
    buf[3] = pickupId.length > 2 ? pickupId.codeUnitAt(2) : 0x30;
    buf[4] = pc;
    buf[5] = dc;
    buf[6] = rtPax;
    buf[7] = apId.clamp(1, 3);
    buf[8] = 0x01;
    buf[9] = (ts >> 24) & 0xFF;
    buf[10] = (ts >> 16) & 0xFF;
    buf[11] = (ts >> 8) & 0xFF;
    buf[12] = ts & 0xFF;

    final crc = _crc16(buf.sublist(0, 13));
    buf[13] = (crc >> 8) & 0xFF;
    buf[14] = crc & 0xFF;

    return buf;
  }

  static int _crc16(Uint8List data) {
    int crc = 0xFFFF;
    for (final byte in data) {
      crc ^= byte << 8;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }

  // ─── LCD Row Helpers ────────────────────────────────────────────────────
  static String lcdPad(String s, [int width = 16]) {
    if (s.length >= width) return s.substring(0, width);
    return s + ' ' * (width - s.length);
  }

  static List<String> buildLcdRows({
    required List<Map<String, dynamic>> passengers,
    required String pickupLocation,
    required String destination,
    required String rideType,
    int countdown = 30,
  }) {
    final ids = passengers.map((p) => p['pickupId'] as String).join(' ');
    final page0 =
    lcdPad('${rideType == 'Chartered' ? 'CHARTERED' : 'SHARED'} x${passengers.length}');
    final page1 = lcdPad('IDs:$ids');
    final page2 = lcdPad('FROM:${locationShortName[pickupLocation] ?? pickupLocation}');
    final page3 = lcdPad('TO:${locationShortName[destination] ?? destination}');
    final row1 = lcdPad('${countdown}s [A]ok [R]no');
    return [page0, page1, page2, page3, row1];
  }

  // ─── Static helpers ─────────────────────────────────────────────────────
  static int getLocationCode(String locationName) =>
      locationCodeMap[locationName] ?? 0;

  static int getRideTypeCode(String rideType) =>
      rideType == 'Chartered' ? 1 : 0;

  static const Map<int, String> statusMap = {
    0: 'Pending',
    1: 'Assigned',
    2: 'Accepted',
    3: 'En Route',
    4: 'Rejected',
    5: 'Cancelled',
    6: 'Completed',
  };

  static String getStatusName(int code) => statusMap[code] ?? 'Unknown';

  static String normalizeNigerianPhone(String phone) {
    String p = phone.trim().replaceAll(' ', '').replaceAll('-', '');
    if (p.startsWith('+234')) return p;
    if (p.startsWith('234')) return '+$p';
    if (p.startsWith('0')) return '+234${p.substring(1)}';
    return '+234$p';
  }

  // ─── Offline hardware methods (Stubbed out — online mode active) ─────────
  Future<bool> isConnectedToEsp32() async => false;
  Future<List<Map<String, dynamic>>> fetchOfflineRequestsFromEsp32() async => [];
  Future<bool> sendOfflineStatusUpdateToEsp32({
    required String bookingId,
    required int status,
    String? shuttleId,
  }) async => false;
  Future<Map<String, dynamic>> sendRequestToEsp32({
    required String userName,
    required String pickupLocation,
    required String destination,
    required String rideType,
    required int passengerCount,
    String? pickupId,
  }) async => {'status': 'ERROR', 'message': 'Offline mode disabled'};
  Future<Map<String, dynamic>> pollRequestStatus(String pid) async =>
      {'status': 'ERROR', 'message': 'Offline mode disabled'};
}
