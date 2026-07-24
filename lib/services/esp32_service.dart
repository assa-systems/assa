import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:flutter/foundation.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ASSA ESP32 SERVICE  —  v28  (Fixed: Android network, form-urlencoded)
/// ═══════════════════════════════════════════════════════════════════════════

class Esp32Service {
  // ── SINGLETON ───────────────────────────────────────────────────────────
  Esp32Service._internal();
  static final Esp32Service instance = Esp32Service._internal();
  factory Esp32Service() => instance;

  // ── ESP32 Access Point Configuration ──────────────────────────────────
  static const String esp32IpAddress  = '192.168.4.1';
  static const int    esp32Port       = 80;
  static const String requestEndpoint = '/api/tx';
  static const String pollEndpoint    = '/api/rx';
  static const int    timeoutSeconds  = 8;  // Reduced from 10 for faster fail

  // ── Polling Configuration ──────────────────────────────────────────────
  static const int maxPollRetries = 50;
  static const int pollIntervalMs = 3000;

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

  // ─── Force WiFi (Android only) ────────────────────────────────────────
  // FIX: WiFiForIoTPlugin.forceWifiUsage() is a native MethodChannel call
  // that can hang indefinitely on some devices/OS versions instead of
  // throwing. Every caller of isConnectedToEsp32()/sendRequestToEsp32()/
  // pollRequestStatus() awaits this first — a hang here was propagating
  // all the way up into RequestScreen's connectivity check and submit
  // flow, leaving the "Checking connection..." / "Sending your
  // request..." spinners stuck forever with no error and no way forward.
  // A timeout guarantees this always returns.
  static Future<void> _forceWifi(bool force) async {
    if (!Platform.isAndroid) return;
    try {
      await WiFiForIoTPlugin.forceWifiUsage(force)
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (e) {
      debugPrint('Force WiFi error: $e');
    }
  }

  // ─── ESP32 Connection Check (Fixed: Uses HTTP GET, not socket) ───────
  Future<bool> isConnectedToEsp32() async {
    await _forceWifi(true);
    try {
      // Try HTTP GET to root - more reliable than raw socket on Android
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2)
        ..idleTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(
          Uri.parse('http://$esp32IpAddress:$esp32Port/')
      );
      final response = await request.close().timeout(const Duration(seconds: 2));
      client.close();
      // Any response (even 404) means the server is reachable
      return response.statusCode >= 200 && response.statusCode < 600;
    } catch (e) {
      debugPrint('ESP32 connection check failed: $e');
      return false;
    } finally {
      await _forceWifi(false);
    }
  }

  // ─── Poll AP for driver response status ─────────────────────────────────
  Future<Map<String, dynamic>> pollRequestStatus(
      String bookingId, {
        int maxRetries = maxPollRetries,
        int initialDelayMs = pollIntervalMs,
      }) async {
    int attempt = 0;
    int delayMs = initialDelayMs;

    while (attempt < maxRetries) {
      attempt++;
      try {
        final result = await _pollOnce(bookingId);
        final status = result['status'] as String? ?? '';

        if (status == 'ACCEPTED' ||
            status == 'REJECTED' ||
            status == 'CANCELLED' ||
            status == 'COMPLETED') {
          return result;
        }

        if (status == 'ERROR') {
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs = (delayMs * 1.5).toInt();
          continue;
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs = (delayMs * 1.2).toInt();
          continue;
        }

        return result;
      } catch (e) {
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs = (delayMs * 2).toInt();
        } else {
          return {'status': 'ERROR', 'message': 'Max retries exceeded: $e'};
        }
      }
    }

    return {'status': 'ERROR', 'message': 'Polling timed out'};
  }

  Future<Map<String, dynamic>> _pollOnce(String bookingId) async {
    await _forceWifi(true);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..idleTimeout = const Duration(seconds: 3);
      final request = await client
          .getUrl(Uri.parse('http://$esp32IpAddress:$esp32Port$pollEndpoint'))
          .timeout(const Duration(seconds: 3));
      final response = await request.close()
          .timeout(const Duration(seconds: 3));
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        if (body.trim().isEmpty) return {'status': 'PENDING', 'pid': bookingId};
        
        List<dynamic> msgs = [];
        try {
          msgs = jsonDecode(body) as List<dynamic>;
        } catch (_) {
          return {'status': 'PENDING', 'pid': bookingId};
        }

        for (final msg in msgs) {
          if (msg is Map<String, dynamic> && msg['t'] == 'STS') {
            final String pay = msg['pay']?.toString() ?? '';
            final parts = pay.split('|');
            
            if (parts.length >= 2 && parts[0] == bookingId) {
              final int rawStatus = int.tryParse(parts[1]) ?? 0;
              String normalized;
              switch (rawStatus) {
                case 2: // STATUS_ACCEPTED
                  normalized = 'ACCEPTED';
                  break;
                case 4: // STATUS_REJECTED
                  normalized = 'REJECTED';
                  break;
                case 5: // STATUS_CANCELLED
                  normalized = 'CANCELLED';
                  break;
                case 6: // STATUS_COMPLETED
                  normalized = 'COMPLETED';
                  break;
                case 1: // STATUS_ASSIGNED
                  normalized = 'ASSIGNED';
                  break;
                case -1: // STATUS_EXPIRED
                  normalized = 'EXPIRED';
                  break;
                case 0: // STATUS_PENDING
                default:
                  normalized = 'PENDING';
              }

              final String shuttleId = parts.length >= 4 ? parts[3] : '';
              final bool expired = rawStatus == -1;

              return {
                'status': normalized,
                'AFIT KEKE': shuttleId,
                'pid': bookingId,
                'rawStatus': rawStatus,
                'expired': expired,
              };
            }
          }
        }
        return {
          'status': 'PENDING',
          'AFIT KEKE': '',
          'pid': bookingId,
          'rawStatus': 0,
          'expired': false,
        };
      }
      return {'status': 'ERROR', 'message': 'HTTP ${response.statusCode}'};
    } on SocketException {
      return {'status': 'ERROR', 'message': 'AP not reachable'};
    } on TimeoutException {
      return {'status': 'ERROR', 'message': 'Poll timeout'};
    } catch (e) {
      return {'status': 'ERROR', 'message': e.toString()};
    } finally {
      await _forceWifi(false);
    }
  }

  // ─── SEND REQUEST TO ESP32 (FORM-URLENCODED) ───────────────────────────
  Future<Map<String, dynamic>> sendRequestToEsp32({
    required String userName,
    required String pickupLocation,
    required String destination,
    required String rideType,
    required int passengerCount,
    String? pickupId,
  }) async {
    await _forceWifi(true);
    try {
      final pc = locationCodeMap[pickupLocation] ?? 1;
      final dc = locationCodeMap[destination] ?? 1;
      final rt = rideType == 'Chartered' ? 1 : 0;
      final pax = rideType == 'Chartered' ? 1 : passengerCount.clamp(1, 15);

      // App uses Pickup ID as booking ID based on user preference
      final String pId = (pickupId != null && pickupId.trim().isNotEmpty) ? pickupId.trim() : 'N/A';
      final String generatedBookingId = pId != 'N/A' ? pId : 'REQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      
      // format: BookingID|UserName|PickupID|PickupCode|DestCode|RideType|Pax
      final String payStr = '$generatedBookingId|$userName|$pId|$pc|$dc|$rt|$pax';

      // Build form-urlencoded body for /api/tx
      final body = StringBuffer();
      body.write('t=REQ');
      body.write('&dst=0');
      body.write('&pay=${Uri.encodeComponent(payStr)}');

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..idleTimeout = const Duration(seconds: 5);

      final request = await client
          .postUrl(Uri.parse('http://$esp32IpAddress:$esp32Port$requestEndpoint'))
          .timeout(Duration(seconds: timeoutSeconds));

      final bodyBytes = utf8.encode(body.toString());

      request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded'
      );
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close()
          .timeout(Duration(seconds: timeoutSeconds));
      final bodyResponse = await response.transform(utf8.decoder).join();
      client.close();

      debugPrint('[ESP32] Response: $bodyResponse');

      try {
        final data = jsonDecode(bodyResponse) as Map<String, dynamic>;
        // Guide states: 200 OK {"success":true}
        if (response.statusCode == 200 && data['success'] == true) {
          return {
            'success': true,
            'data': bodyResponse,
            'bookingId': generatedBookingId, // Return the app-generated ID
            'from': pickupLocation,
            'to': destination,
          };
        }
        return {
          'success': false,
          'error': data['error'] as String? ?? 'Unknown error',
        };
      } catch (_) {
        return {
          'success': false,
          'error': 'Invalid response from AP: $bodyResponse',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'error': 'Cannot reach campus hotspot. Connect to "AFIT KEKEAP-1" WiFi first.',
      };
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Request timed out. Move closer to the campus access point.',
      };
    } catch (e) {
      return {'success': false, 'error': 'Offline request failed: $e'};
    } finally {
      await _forceWifi(false);
    }
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
}
