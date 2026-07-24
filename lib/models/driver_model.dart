import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleInfo {
  final String plateNumber;
  final String model;
  final int capacity;

  VehicleInfo({
    this.plateNumber = '',
    this.model = '',
    this.capacity = 0,
  });

  factory VehicleInfo.fromMap(Map<String, dynamic> map) {
    return VehicleInfo(
      plateNumber: map['plateNumber'] ?? '',
      model: map['model'] ?? '',
      capacity: map['capacity'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'plateNumber': plateNumber,
      'model': model,
      'capacity': capacity,
    };
  }

  VehicleInfo copyWith({
    String? plateNumber,
    String? model,
    int? capacity,
  }) {
    return VehicleInfo(
      plateNumber: plateNumber ?? this.plateNumber,
      model: model ?? this.model,
      capacity: capacity ?? this.capacity,
    );
  }
}

class DriverModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String phoneNumber;
  final String shuttleId;
  final String driverIdCardUrl;
  final String department;
  final VehicleInfo vehicleInfo;
  final String status; // pending | approved | rejected
  final String fcmToken;
  final String? createdBy; // uid of admin who created (null if self-registered)
  final DateTime createdAt;
  final DateTime? approvedAt;
  final String? approvedBy; // uid of admin who approved
  final int totalRatings;
  final double averageRating;

  DriverModel({
    required this.uid,
    required this.name,
    required this.email,
    this.role = 'driver',
    required this.phoneNumber,
    required this.shuttleId,
    this.driverIdCardUrl = '',
    this.department = '',
    VehicleInfo? vehicleInfo,
    this.status = 'pending',
    this.fcmToken = '',
    this.createdBy,
    required this.createdAt,
    this.approvedAt,
    this.approvedBy,
    this.totalRatings = 0,
    this.averageRating = 0.0,
  }) : vehicleInfo = vehicleInfo ?? VehicleInfo();

  // ── From Firestore ─────────────────────────────────────────────────
  factory DriverModel.fromMap(Map<String, dynamic> map, String uid) {
    return DriverModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'driver',
      phoneNumber: map['phoneNumber'] ?? '',
      shuttleId: map['shuttleId'] ?? '',
      driverIdCardUrl: map['driverIdCardUrl'] ?? '',
      department: map['department'] ?? '',
      vehicleInfo: map['vehicleInfo'] != null
          ? VehicleInfo.fromMap(map['vehicleInfo'] as Map<String, dynamic>)
          : VehicleInfo(),
      status: map['status'] ?? 'pending',
      fcmToken: map['fcmToken'] ?? '',
      createdBy: map['createdBy'],
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      approvedAt: map['approvedAt'] != null
          ? (map['approvedAt'] as Timestamp).toDate()
          : null,
      approvedBy: map['approvedBy'],
      totalRatings: map['totalRatings'] as int? ?? 0,
      averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory DriverModel.fromDocument(DocumentSnapshot doc) {
    return DriverModel.fromMap(
      doc.data() as Map<String, dynamic>,
      doc.id,
    );
  }

  // ── To Firestore ───────────────────────────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'phoneNumber': phoneNumber,
      'shuttleId': shuttleId,
      'driverIdCardUrl': driverIdCardUrl,
      'department': department,
      'vehicleInfo': vehicleInfo.toMap(),
      'status': status,
      'fcmToken': fcmToken,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'approvedBy': approvedBy,
      'totalRatings': totalRatings,
      'averageRating': averageRating,
    };
  }

  // ── Copy With ──────────────────────────────────────────────────────
  DriverModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    String? phoneNumber,
    String? shuttleId,
    String? driverIdCardUrl,
    String? department,
    VehicleInfo? vehicleInfo,
    String? status,
    String? fcmToken,
    String? createdBy,
    DateTime? createdAt,
    DateTime? approvedAt,
    String? approvedBy,
    int? totalRatings,
    double? averageRating,
  }) {
    return DriverModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      shuttleId: shuttleId ?? this.shuttleId,
      driverIdCardUrl: driverIdCardUrl ?? this.driverIdCardUrl,
      department: department ?? this.department,
      vehicleInfo: vehicleInfo ?? this.vehicleInfo,
      status: status ?? this.status,
      fcmToken: fcmToken ?? this.fcmToken,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      totalRatings: totalRatings ?? this.totalRatings,
      averageRating: averageRating ?? this.averageRating,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isSelfRegistered => createdBy == null;

  @override
  String toString() =>
      'DriverModel(uid: $uid, name: $name, shuttleId: $shuttleId, status: $status)';
}