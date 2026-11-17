/// Represents the operational status of a sensor based on its current reading
enum SensorStatus {
  /// Sensor reading is within normal operating parameters
  normal,
  
  /// Sensor reading is approaching critical thresholds
  warning,
  
  /// Sensor reading has exceeded critical thresholds
  danger,
}

/// Categorizes the type of physical sensor
enum SensorType {
  /// Temperature measurement sensor (e.g., DHT22, DS18B20)
  temperature,
  
  /// Humidity measurement sensor (e.g., DHT22, DHT11)
  humidity,
  
  /// Flame detection sensor (binary detection)
  flame,
  
  /// Gas concentration sensor (e.g., MQ-2, MQ-135)
  gas,
}

/// Defines alert threshold values for a sensor
class SensorThresholds {
  /// Minimum safe operating value (optional)
  final double? minSafe;
  
  /// Maximum safe operating value (optional)
  final double? maxSafe;
  
  /// Value at which warning status is triggered (optional)
  final double? warningThreshold;
  
  /// Value at which danger status is triggered (optional)
  final double? dangerThreshold;
  
  const SensorThresholds({
    this.minSafe,
    this.maxSafe,
    this.warningThreshold,
    this.dangerThreshold,
  });
  
  /// Creates a SensorThresholds instance from JSON data
  factory SensorThresholds.fromJson(Map<String, dynamic> json) {
    return SensorThresholds(
      minSafe: json['minSafe'] as double?,
      maxSafe: json['maxSafe'] as double?,
      warningThreshold: json['warningThreshold'] as double?,
      dangerThreshold: json['dangerThreshold'] as double?,
    );
  }
  
  /// Converts this SensorThresholds instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'minSafe': minSafe,
      'maxSafe': maxSafe,
      'warningThreshold': warningThreshold,
      'dangerThreshold': dangerThreshold,
    };
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorThresholds &&
        other.minSafe == minSafe &&
        other.maxSafe == maxSafe &&
        other.warningThreshold == warningThreshold &&
        other.dangerThreshold == dangerThreshold;
  }
  
  @override
  int get hashCode {
    return Object.hash(
      minSafe,
      maxSafe,
      warningThreshold,
      dangerThreshold,
    );
  }
}

/// Represents a single data point in sensor historical data
class SensorDataPoint {
  /// The timestamp when this measurement was taken
  final DateTime timestamp;
  
  /// The measured value at this timestamp
  final double value;
  
  const SensorDataPoint({
    required this.timestamp,
    required this.value,
  });
  
  /// Creates a SensorDataPoint instance from JSON data
  factory SensorDataPoint.fromJson(Map<String, dynamic> json) {
    return SensorDataPoint(
      timestamp: DateTime.parse(json['timestamp'] as String),
      value: (json['value'] as num).toDouble(),
    );
  }
  
  /// Converts this SensorDataPoint instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'value': value,
    };
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorDataPoint &&
        other.timestamp == timestamp &&
        other.value == value;
  }
  
  @override
  int get hashCode => Object.hash(timestamp, value);
}

/// Complete sensor data model including current readings and metadata
class SensorData {
  /// Unique identifier for this sensor
  final String id;
  
  /// Human-readable name of the sensor
  final String name;
  
  /// Current measured value
  final double currentValue;
  
  /// Unit of measurement (e.g., "°C", "%", " ADC")
  final String unit;
  
  /// Current operational status based on readings
  final SensorStatus status;
  
  /// Type of sensor
  final SensorType type;
  
  /// Timestamp of the last data update
  final DateTime lastUpdate;
  
  /// Physical location of the sensor (optional)
  final String? location;
  
  /// Date when the sensor was installed (optional)
  final DateTime? installationDate;
  
  /// Battery level percentage (0-100, optional)
  final double? batteryLevel;
  
  /// Power source description (optional, e.g., "Battery", "Wired (GPIO 27)")
  final String? powerStatus;
  
  /// Configured alert thresholds for this sensor (optional)
  final SensorThresholds? thresholds;
  
  /// Historical data points for trend visualization (optional)
  final List<SensorDataPoint>? historicalData;
  
  const SensorData({
    required this.id,
    required this.name,
    required this.currentValue,
    required this.unit,
    required this.status,
    required this.type,
    required this.lastUpdate,
    this.location,
    this.installationDate,
    this.batteryLevel,
    this.powerStatus,
    this.thresholds,
    this.historicalData,
  });
  
  /// Creates a SensorData instance from JSON data
  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      id: json['id'] as String,
      name: json['name'] as String,
      currentValue: (json['currentValue'] as num).toDouble(),
      unit: json['unit'] as String,
      status: SensorStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SensorStatus.normal,
      ),
      type: SensorType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SensorType.temperature,
      ),
      lastUpdate: DateTime.parse(json['lastUpdate'] as String),
      location: json['location'] as String?,
      installationDate: json['installationDate'] != null
          ? DateTime.parse(json['installationDate'] as String)
          : null,
      batteryLevel: json['batteryLevel'] as double?,
      powerStatus: json['powerStatus'] as String?,
      thresholds: json['thresholds'] != null
          ? SensorThresholds.fromJson(json['thresholds'] as Map<String, dynamic>)
          : null,
      historicalData: json['historicalData'] != null
          ? (json['historicalData'] as List)
              .map((e) => SensorDataPoint.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
  
  /// Converts this SensorData instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'currentValue': currentValue,
      'unit': unit,
      'status': status.name,
      'type': type.name,
      'lastUpdate': lastUpdate.toIso8601String(),
      'location': location,
      'installationDate': installationDate?.toIso8601String(),
      'batteryLevel': batteryLevel,
      'powerStatus': powerStatus,
      'thresholds': thresholds?.toJson(),
      'historicalData': historicalData?.map((e) => e.toJson()).toList(),
    };
  }
  
  /// Creates a copy of this SensorData with optional field overrides
  SensorData copyWith({
    String? id,
    String? name,
    double? currentValue,
    String? unit,
    SensorStatus? status,
    SensorType? type,
    DateTime? lastUpdate,
    String? location,
    DateTime? installationDate,
    double? batteryLevel,
    String? powerStatus,
    SensorThresholds? thresholds,
    List<SensorDataPoint>? historicalData,
  }) {
    return SensorData(
      id: id ?? this.id,
      name: name ?? this.name,
      currentValue: currentValue ?? this.currentValue,
      unit: unit ?? this.unit,
      status: status ?? this.status,
      type: type ?? this.type,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      location: location ?? this.location,
      installationDate: installationDate ?? this.installationDate,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      powerStatus: powerStatus ?? this.powerStatus,
      thresholds: thresholds ?? this.thresholds,
      historicalData: historicalData ?? this.historicalData,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorData &&
        other.id == id &&
        other.name == name &&
        other.currentValue == currentValue &&
        other.unit == unit &&
        other.status == status &&
        other.type == type &&
        other.lastUpdate == lastUpdate &&
        other.location == location &&
        other.installationDate == installationDate &&
        other.batteryLevel == batteryLevel &&
        other.powerStatus == powerStatus &&
        other.thresholds == thresholds &&
        _listEquals(other.historicalData, historicalData);
  }
  
  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      currentValue,
      unit,
      status,
      type,
      lastUpdate,
      location,
      installationDate,
      batteryLevel,
      powerStatus,
      thresholds,
      Object.hashAll(historicalData ?? []),
    );
  }
  
  /// Helper method to compare two lists for equality
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
