// ═══════════════════════════════════════════════════════════════════════════
// offline_request_store.dart  —  ASSA Local Offline Request Persistence
// Academic Project: AFIT Shuttle Service App (ASSA)
// Author: Abd21 | AFIT Kaduna | B.Eng Telecommunication Engineering
//
// PURPOSE:
//   Stores offline (ESP32/LoRa) ride requests entirely on the device using
//   SharedPreferences. No Firestore or internet required.
//
//   When a passenger submits a request via the AP Wi-Fi hotspot:
//     1. Request is sent to the AP over HTTP
//     2. A local record is saved here immediately
//     3. My Requests screen reads this store and displays the request
//     4. The offline feedback dialog polls the AP and calls updateStatus()
//        when the driver responds — updating the local record in place
//     5. User can cancel (remove) the request at any time
//
//   Data is keyed by PID (e.g. "A01") and stored as JSON in SharedPreferences
//   under the key "assa_offline_requests".
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ── Offline request status codes (mirrors AP firmware response strings) ──────
enum OfflineStatus {
  pending,    // AP received, waiting for Gateway → SU → driver
  accepted,   // Driver pressed ACCEPT on Shuttle Unit
  confirmed,  // Gateway confirmed all passengers assigned
  rejected,   // Driver pressed REJECT or 30 s timeout
  cancelled,  // User cancelled locally
}

extension OfflineStatusExt on OfflineStatus {
  String get label {
    switch (this) {
      case OfflineStatus.pending:   return 'Pending (Offline)';
      case OfflineStatus.accepted:  return 'Accepted';
      case OfflineStatus.confirmed: return 'Confirmed';
      case OfflineStatus.rejected:  return 'No Shuttle';
      case OfflineStatus.cancelled: return 'Cancelled';
    }
  }

  static OfflineStatus fromString(String s) {
    switch (s) {
      case 'accepted':  return OfflineStatus.accepted;
      case 'confirmed': return OfflineStatus.confirmed;
      case 'rejected':  return OfflineStatus.rejected;
      case 'cancelled': return OfflineStatus.cancelled;
      default:          return OfflineStatus.pending;
    }
  }
}

// ── Local offline request model ───────────────────────────────────────────────
class OfflineRequest {
  final String pid;             // 3-char Pickup ID e.g. "A01"
  final String pickupLocation;  // e.g. "45x1 Hostel"
  final String destination;     // e.g. "BK"
  final String rideType;        // "Shared" | "Chartered"
  final int    passengerCount;
  final DateTime createdAt;
  OfflineStatus status;
  String shuttleId;             // populated when driver accepts e.g. "AFIT-001"

  OfflineRequest({
    required this.pid,
    required this.pickupLocation,
    required this.destination,
    required this.rideType,
    required this.passengerCount,
    required this.createdAt,
    this.status    = OfflineStatus.pending,
    this.shuttleId = '',
  });

  Map<String, dynamic> toJson() => {
    'pid':             pid,
    'pickupLocation':  pickupLocation,
    'destination':     destination,
    'rideType':        rideType,
    'passengerCount':  passengerCount,
    'createdAt':       createdAt.toIso8601String(),
    'status':          status.name,
    'shuttleId':       shuttleId,
  };

  factory OfflineRequest.fromJson(Map<String, dynamic> j) => OfflineRequest(
    pid:            j['pid']            as String,
    pickupLocation: j['pickupLocation'] as String,
    destination:    j['destination']    as String,
    rideType:       j['rideType']       as String? ?? 'Shared',
    passengerCount: j['passengerCount'] as int?    ?? 1,
    createdAt:      DateTime.parse(j['createdAt']  as String),
    status:         OfflineStatusExt.fromString(j['status'] as String? ?? 'pending'),
    shuttleId:      j['shuttleId']      as String? ?? '',
  );
}

// ── Store singleton ───────────────────────────────────────────────────────────
class OfflineRequestStore {
  OfflineRequestStore._();
  static final instance = OfflineRequestStore._();

  static const _key = 'assa_offline_requests';

  // In-memory cache — loaded once, kept in sync
  final List<OfflineRequest> _requests = [];
  bool _loaded = false;

  // ── Load from SharedPreferences ────────────────────────────────────────────
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _requests.clear();
        _requests.addAll(
          list.map((e) => OfflineRequest.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {
        // Corrupted data — start fresh
        _requests.clear();
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_requests.map((r) => r.toJson()).toList()));
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// All stored requests, newest first.
  Future<List<OfflineRequest>> getAll() async {
    await _ensureLoaded();
    final sorted = List<OfflineRequest>.from(_requests)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  /// Save a new offline request immediately after AP confirms receipt.
  Future<void> add(OfflineRequest req) async {
    await _ensureLoaded();
    // Remove any old entry with the same PID (e.g. after a retry)
    _requests.removeWhere((r) => r.pid == req.pid);
    _requests.add(req);
    await _persist();
  }

  /// Update status (and optionally shuttleId) for a given PID.
  /// Called by the offline feedback dialog when the AP poll returns a result.
  Future<void> updateStatus(
      String pid,
      OfflineStatus status, {
        String shuttleId = '',
      }) async {
    await _ensureLoaded();
    for (final r in _requests) {
      if (r.pid == pid) {
        r.status    = status;
        if (shuttleId.isNotEmpty) r.shuttleId = shuttleId;
        break;
      }
    }
    await _persist();
  }

  /// Cancel (remove) a request by PID. Used by My Requests cancel button.
  Future<void> cancel(String pid) async {
    await _ensureLoaded();
    final idx = _requests.indexWhere((r) => r.pid == pid);
    if (idx != -1) {
      _requests[idx].status = OfflineStatus.cancelled;
      await _persist();
    }
  }

  /// Hard-delete a cancelled request from the list.
  Future<void> delete(String pid) async {
    await _ensureLoaded();
    _requests.removeWhere((r) => r.pid == pid);
    await _persist();
  }

  /// Find a single request by PID.
  Future<OfflineRequest?> find(String pid) async {
    await _ensureLoaded();
    try {
      return _requests.firstWhere((r) => r.pid == pid);
    } catch (_) {
      return null;
    }
  }

  /// Force a reload from disk (call after app resumes from background).
  void invalidate() => _loaded = false;
}