# Design Document: Expandable Sensor Cards

## Overview

This document describes the design for implementing expandable/collapsible sensor cards in a Flutter IoT monitoring application. The feature transforms the existing static sensor display into an interactive card-based interface where users can tap cards to reveal detailed sensor information, historical trends, and metadata.

## Architecture

### Component Structure

The implementation follows a widget composition pattern with clear separation of concerns:

```
ServerMonitoringScreen (Container)
├── SensorCardList (Stateful Widget)
│   ├── State Management (Expansion tracking)
│   └── ListView.builder
│       └── Multiple SensorCard instances
│
SensorCard (Stateful Widget)
├── AnimationController (Height & rotation)
├── CardContent (Visual representation)
│   ├── CollapsedView
│   │   ├── Sensor name, value, unit
│   │   ├── Status indicator
│   │   └── Expansion control icon
│   └── ExpandedView
│       ├── All collapsed content
│       ├── Detailed metadata fields
│       ├── HistoricalTrendChart
│       └── Additional sensor information
└── GestureDetector (Tap handling)
```

### Core Components

#### 1. SensorCard Widget

**Purpose**: A self-contained, stateful widget representing a single sensor with expand/collapse functionality.

**Key Responsibilities**:
- Manage its own expansion state (collapsed/expanded)
- Handle animation lifecycle for smooth transitions
- Render appropriate content based on current state
- Emit callbacks for expansion/collapse events
- Provide accessibility semantics

**State**:
```dart
class _SensorCardState extends State<SensorCard> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _heightAnimation;
  late Animation<double> _iconRotationAnimation;
  
  // Sensor data from widget
  // Animation curves and durations
}
```

**Interface**:
```dart
class SensorCard extends StatefulWidget {
  final SensorData sensorData;
  final VoidCallback? onExpansionChanged;
  final bool initiallyExpanded;
  
  const SensorCard({
    Key? key,
    required this.sensorData,
    this.onExpansionChanged,
    this.initiallyExpanded = false,
  }) : super(key: key);
}
```

#### 2. SensorCardList Widget

**Purpose**: Manages the collection of sensor cards and enforces single-expansion policy.

**Key Responsibilities**:
- Track which card (if any) is currently expanded
- Coordinate collapse of previously expanded card when a new one expands
- Manage scroll position to keep expanded cards visible
- Build the scrollable list of sensor cards

**State**:
```dart
class _SensorCardListState extends State<SensorCardList> {
  int? _expandedCardIndex;
  final ScrollController _scrollController = ScrollController();
  
  void _handleCardExpansion(int index, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedCardIndex = index;
        _ensureCardVisible(index);
      } else if (_expandedCardIndex == index) {
        _expandedCardIndex = null;
      }
    });
  }
}
```

#### 3. HistoricalTrendChart Widget

**Purpose**: Visualize sensor data over time with a line chart.

**Key Responsibilities**:
- Render 24-hour historical data as a line chart
- Display labeled axes (time and value)
- Handle loading and error states
- Adapt to theme configuration

**State**:
```dart
class HistoricalTrendChart extends StatelessWidget {
  final List<SensorDataPoint>? historicalData;
  final bool isLoading;
  final String sensorUnit;
  
  const HistoricalTrendChart({
    Key? key,
    required this.historicalData,
    this.isLoading = false,
    required this.sensorUnit,
  }) : super(key: key);
}
```

### Data Models

#### SensorData Model

```dart
class SensorData {
  final String id;
  final String name;
  final double currentValue;
  final String unit;
  final SensorStatus status;
  final SensorType type;
  
  // Optional detailed fields
  final String? location;
  final DateTime? installationDate;
  final DateTime lastUpdate;
  final double? batteryLevel;
  final String? powerStatus;
  final SensorThresholds? thresholds;
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
}
```

#### Supporting Models

```dart
enum SensorStatus { normal, warning, danger }

enum SensorType { temperature, humidity, flame, gas }

class SensorThresholds {
  final double? minSafe;
  final double? maxSafe;
  final double? warningThreshold;
  final double? dangerThreshold;
  
  const SensorThresholds({
    this.minSafe,
    this.maxSafe,
    this.warningThreshold,
    this.dangerThreshold,
  });
}

class SensorDataPoint {
  final DateTime timestamp;
  final double value;
  
  const SensorDataPoint({
    required this.timestamp,
    required this.value,
  });
}
```

## State Management

### Expansion State Strategy

The implementation uses a **coordinated local state** approach:

1. **Local State in SensorCard**: Each card manages its own `_isExpanded` boolean and animation controller
2. **Coordination via SensorCardList**: The parent list tracks which card is expanded and coordinates collapse of others
3. **Callback Communication**: Cards notify the list via `onExpansionChanged` callback when their expansion state changes

**Expansion Flow**:
```
User taps Card B
  → Card B's GestureDetector triggers
  → Card B calls onExpansionChanged(true)
  → SensorCardList receives callback
  → List updates _expandedCardIndex to B's index
  → List rebuilds, passing initiallyExpanded to each card
  → Card A receives initiallyExpanded=false, triggers collapse
  → Card B receives initiallyExpanded=true (already expanded)
```

**State Persistence During Scroll**:
- Expansion state is stored in `_expandedCardIndex` at the list level
- As cards scroll in/out of viewport, they rebuild with correct `initiallyExpanded` value
- This ensures state persists across viewport changes

## Animation Implementation

### Animation Configuration

**Duration**: 300ms for all state transitions (expand and collapse)

**Easing Curve**: `Curves.easeInOutCubic` for natural, smooth motion

**Animated Properties**:
1. **Height**: Card height transitions from collapsed (compact) to expanded (full details)
2. **Icon Rotation**: Expansion control icon rotates 180° between states

### Animation Controller Setup

```dart
@override
void initState() {
  super.initState();
  
  _animationController = AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: this,
  );
  
  _heightAnimation = Tween<double>(
    begin: 0.0,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: _animationController,
    curve: Curves.easeInOutCubic,
  ));
  
  _iconRotationAnimation = Tween<double>(
    begin: 0.0,
    end: 0.5, // 0.5 turns = 180 degrees
  ).animate(CurvedAnimation(
    parent: _animationController,
    curve: Curves.easeInOutCubic,
  ));
  
  if (widget.initiallyExpanded) {
    _animationController.value = 1.0;
    _isExpanded = true;
  }
}
```

### Animation Rendering

```dart
Widget build(BuildContext context) {
  return AnimatedBuilder(
    animation: _animationController,
    builder: (context, child) {
      return SizeTransition(
        sizeFactor: _heightAnimation,
        child: GestureDetector(
          onTap: _isAnimating ? null : _handleTap,
          child: Card(
            child: Column(
              children: [
                _buildCollapsedContent(),
                if (_heightAnimation.value > 0.0)
                  _buildExpandedContent(),
              ],
            ),
          ),
        ),
      );
    },
  );
}
```

### Tap Gesture Blocking During Animation

```dart
bool get _isAnimating => _animationController.isAnimating;

void _handleTap() {
  if (_isAnimating) return; // Block taps during animation
  
  setState(() {
    _isExpanded = !_isExpanded;
    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  });
  
  widget.onExpansionChanged?.call();
}
```

## Visual Design

### Collapsed State Layout

**Height**: Approximately 120dp (compact)

**Content**:
```
┌─────────────────────────────────────┐
│  [Icon]  Sensor Name        [▼]    │
│          24.6°C                      │
│          Status: Normal              │
│          [●] Status Indicator        │
└─────────────────────────────────────┘
```

**Elements**:
- Sensor type icon (24dp, themed color)
- Sensor name (subtitle text style)
- Current value with unit (headline text style)
- Status badge (chip with colored background)
- Status indicator dot (8dp circle, colored by status)
- Expansion control chevron icon (24dp, animated rotation)

### Expanded State Layout

**Height**: Approximately 400dp (variable based on content)

**Content**:
```
┌─────────────────────────────────────┐
│  [Icon]  Sensor Name        [▲]    │
│          24.6°C                      │
│          Status: Normal              │
│          [●] Status Indicator        │
├─────────────────────────────────────┤
│  Detailed Information               │
│  Location: Server Room A            │
│  Type: DHT22 Temperature Sensor     │
│  Installed: 2024-01-15              │
│  Last Update: 2 seconds ago         │
│  Battery: 87%                       │
│  Thresholds: 18-27°C (Safe)         │
├─────────────────────────────────────┤
│  Historical Trend (24h)             │
│  [Line Chart Visualization]         │
│  ┌────────────────────────────┐    │
│  │     ^                      │    │
│  │  30°│     /\  /\            │    │
│  │  25°│    /  \/  \           │    │
│  │  20°│___/       \___        │    │
│  │     └──────────────────>   │    │
│  │     0h        12h      24h  │    │
│  └────────────────────────────┘    │
└─────────────────────────────────────┘
```

**Additional Elements in Expanded View**:
- Divider line separating sections
- Metadata fields (2-column grid layout)
- Historical trend chart (full width, 200dp height)
- Chart axes with labels
- Loading spinner (when historical data loading)
- "No data available" message (when historical data unavailable)

### Theming Support

The component uses Flutter's `Theme.of(context)` for styling:

```dart
final theme = Theme.of(context);
final colorScheme = theme.colorScheme;

// Card background
Card(
  color: theme.cardTheme.color ?? colorScheme.surface,
  elevation: theme.cardTheme.elevation ?? 2.0,
  ...
)

// Text styles
Text(
  sensor.name,
  style: theme.textTheme.titleMedium,
)

Text(
  '${sensor.currentValue}${sensor.unit}',
  style: theme.textTheme.headlineSmall?.copyWith(
    fontWeight: FontWeight.bold,
  ),
)

// Status colors
Color _getStatusColor(SensorStatus status) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (status) {
    case SensorStatus.normal:
      return Colors.green;
    case SensorStatus.warning:
      return Colors.amber;
    case SensorStatus.danger:
      return colorScheme.error;
  }
}
```

## Integration with Existing Code

### Refactoring server_monitoring_screen.dart

**Current Implementation**: The existing screen uses `_buildSensorCard()` method to create static sensor card widgets within a hardcoded layout.

**Migration Strategy**:

1. **Extract sensor data**: Convert the existing state variables into `SensorData` objects
2. **Replace static cards**: Replace the current sensor card grid with `SensorCardList`
3. **Maintain simulation**: Keep the simulation mode functionality working with the new card system

**Code Changes**:

```dart
class _ServerMonitoringScreenState extends State<ServerMonitoringScreen> {
  // Keep existing simulation state variables
  double _temperature = 24.6;
  double _humidity = 48.0;
  bool _flameDetected = false;
  int _gasValue = 1420;
  Timer? _timer;
  int _secondsAgo = 2;
  
  // NEW: Convert to SensorData objects
  List<SensorData> get _sensorDataList => [
    SensorData(
      id: 'temp-001',
      name: 'Sensor Suhu',
      currentValue: _temperature,
      unit: '°C',
      status: _getTemperatureStatus(),
      type: SensorType.temperature,
      lastUpdate: DateTime.now().subtract(Duration(seconds: _secondsAgo)),
      location: 'Server Room - Rack A',
      installationDate: DateTime(2024, 1, 15),
      batteryLevel: 87.0,
      powerStatus: 'Battery',
      thresholds: SensorThresholds(
        minSafe: 18.0,
        maxSafe: 27.0,
        warningThreshold: 27.0,
        dangerThreshold: 32.0,
      ),
      historicalData: _generateMockHistoricalData(_temperature),
    ),
    SensorData(
      id: 'hum-001',
      name: 'Kelembapan',
      currentValue: _humidity,
      unit: '%',
      status: _getHumidityStatus(),
      type: SensorType.humidity,
      lastUpdate: DateTime.now().subtract(Duration(seconds: _secondsAgo)),
      location: 'Server Room - Rack A',
      installationDate: DateTime(2024, 1, 15),
      batteryLevel: 92.0,
      powerStatus: 'Battery',
      thresholds: SensorThresholds(
        minSafe: 30.0,
        maxSafe: 60.0,
      ),
      historicalData: _generateMockHistoricalData(_humidity),
    ),
    SensorData(
      id: 'flame-001',
      name: 'Deteksi Api',
      currentValue: _flameDetected ? 1.0 : 0.0,
      unit: '',
      status: _flameDetected ? SensorStatus.danger : SensorStatus.normal,
      type: SensorType.flame,
      lastUpdate: DateTime.now().subtract(Duration(seconds: _secondsAgo)),
      location: 'Server Room - Ceiling',
      installationDate: DateTime(2024, 1, 15),
      powerStatus: 'Wired (GPIO 27)',
      thresholds: null,
      historicalData: null, // Binary sensor, no trend
    ),
    SensorData(
      id: 'gas-001',
      name: 'Bau Gas & Asap',
      currentValue: _gasValue.toDouble(),
      unit: ' ADC',
      status: _getGasStatus(),
      type: SensorType.gas,
      lastUpdate: DateTime.now().subtract(Duration(seconds: _secondsAgo)),
      location: 'Server Room - Air Intake',
      installationDate: DateTime(2024, 1, 15),
      batteryLevel: 78.0,
      powerStatus: 'Battery',
      thresholds: SensorThresholds(
        maxSafe: 1800.0,
        warningThreshold: 1800.0,
        dangerThreshold: 2800.0,
      ),
      historicalData: _generateMockHistoricalData(_gasValue.toDouble()),
    ),
  ];
  
  @override
  Widget build(BuildContext context) {
    // ... keep existing status banner code ...
    
    return Scaffold(
      // ... existing AppBar ...
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ... keep existing status banner ...
          
          const SizedBox(height: 20),
          const Text(
            'Kondisi Sensor Real-time',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // REPLACE: Old grid with new SensorCardList
          SensorCardList(
            sensors: _sensorDataList,
          ),
          
          const SizedBox(height: 20),
          
          // ... keep existing gas concentration bar ...
          // ... keep existing simulation panel ...
        ],
      ),
    );
  }
  
  // Helper methods for status determination
  SensorStatus _getTemperatureStatus() {
    if (_temperature >= 32.0) return SensorStatus.danger;
    if (_temperature >= 27.0) return SensorStatus.warning;
    return SensorStatus.normal;
  }
  
  SensorStatus _getHumidityStatus() {
    if (_humidity < 30.0 || _humidity > 60.0) return SensorStatus.warning;
    return SensorStatus.normal;
  }
  
  SensorStatus _getGasStatus() {
    if (_gasValue >= 2800) return SensorStatus.danger;
    if (_gasValue >= 1800) return SensorStatus.warning;
    return SensorStatus.normal;
  }
  
  // Mock historical data generator
  List<SensorDataPoint> _generateMockHistoricalData(double currentValue) {
    final now = DateTime.now();
    final data = <SensorDataPoint>[];
    
    // Generate 24 data points (one per hour)
    for (int i = 23; i >= 0; i--) {
      final timestamp = now.subtract(Duration(hours: i));
      final variance = (currentValue * 0.1) * (0.5 - (i % 2) / 2.0);
      final value = currentValue + variance;
      data.add(SensorDataPoint(timestamp: timestamp, value: value));
    }
    
    return data;
  }
}
```

### File Structure

```
lib/
├── screens/
│   └── server_monitoring_screen.dart (Modified)
├── widgets/
│   ├── sensor_card.dart (New)
│   ├── sensor_card_list.dart (New)
│   └── historical_trend_chart.dart (New)
└── models/
    └── sensor_data.dart (New)
```

## Accessibility Implementation

### Semantic Labels

```dart
Semantics(
  label: '${sensor.name} sensor card',
  value: '${sensor.currentValue} ${sensor.unit}, Status: ${sensor.status}',
  expanded: _isExpanded,
  button: true,
  onTap: _handleTap,
  child: Card(
    // ... card content ...
  ),
)
```

### Keyboard Navigation

```dart
Focus(
  child: GestureDetector(
    onTap: _handleTap,
    child: Semantics(
      focusable: true,
      onTapHint: _isExpanded ? 'Double tap to collapse' : 'Double tap to expand',
      child: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _handleTap();
            }
          }
        },
        child: Card(
          // ... card content ...
        ),
      ),
    ),
  ),
)
```

### Touch Target Size

```dart
// Expansion control with minimum 48x48dp touch target
InkWell(
  onTap: _handleTap,
  child: Container(
    constraints: const BoxConstraints(
      minWidth: 48.0,
      minHeight: 48.0,
    ),
    alignment: Alignment.center,
    child: RotationTransition(
      turns: _iconRotationAnimation,
      child: Icon(
        Icons.expand_more,
        size: 24.0,
      ),
    ),
  ),
)
```

### State Announcement

```dart
void _handleTap() {
  // ... existing tap handling ...
  
  // Announce state change to screen readers
  final announcement = _isExpanded
      ? '${widget.sensorData.name} expanded. Showing detailed information.'
      : '${widget.sensorData.name} collapsed. Showing summary only.';
  
  SemanticsService.announce(
    announcement,
    TextDirection.ltr,
  );
}
```

## Error Handling

### Missing Optional Data

```dart
Widget _buildMetadataField(String label, String? value, {String? fallback}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          value ?? fallback ?? 'N/A',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}
```

### Historical Data Loading State

```dart
Widget _buildHistoricalTrend() {
  if (widget.sensorData.historicalData == null) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, color: Colors.white38, size: 32),
          SizedBox(height: 8),
          Text(
            'No historical data available',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
  
  if (_isLoadingHistoricalData) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
      ),
    );
  }
  
  return HistoricalTrendChart(
    historicalData: widget.sensorData.historicalData!,
    sensorUnit: widget.sensorData.unit,
  );
}
```

### Animation Controller Disposal

```dart
@override
void dispose() {
  _animationController.dispose();
  _focusNode.dispose();
  super.dispose();
}
```

## Performance Considerations

### Widget Rebuilding

- Use `const` constructors wherever possible to minimize rebuilds
- Separate stateless content into dedicated widgets
- Use `AnimatedBuilder` to limit rebuilds to animated portions only

### Scroll Performance

- Leverage `ListView.builder` for efficient lazy loading of cards
- Keep card widget tree shallow to minimize layout cost
- Avoid expensive operations in `build()` method

### Animation Performance

- Use `SingleTickerProviderStateMixin` for efficient animation ticking
- Dispose animation controllers properly to prevent memory leaks
- Use hardware-accelerated transitions (`SizeTransition`, `RotationTransition`)

## Testing Strategy

The feature will be validated through property-based testing for universal behaviors and example-based testing for specific scenarios. See Correctness Properties section below.

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Default Collapsed State

*For any* list of sensor cards initialized for the first time, all cards should be in collapsed state.

**Validates: Requirements 1.1**

### Property 2: Collapsed Content Completeness

*For any* sensor card in collapsed state, the rendered output should contain the sensor name, current value, unit, and visual status indicator.

**Validates: Requirements 1.2, 1.3**

### Property 3: Collapsed Height Constraint

*For any* sensor card, the height in collapsed state should be less than 150dp and significantly less than the expanded state height.

**Validates: Requirements 1.4**

### Property 4: Tap Toggles Expansion State

*For any* sensor card, tapping while in collapsed state should transition to expanded state, and tapping while in expanded state should transition to collapsed state.

**Validates: Requirements 2.1, 3.1**

### Property 5: Transition Animation Duration

*For any* state transition (expand or collapse), the animation should complete within 300 milliseconds.

**Validates: Requirements 2.3, 3.3**

### Property 6: Expanded Content Completeness

*For any* sensor card in expanded state, the rendered output should contain all collapsed content plus detailed metadata fields (location, type, timestamp, installation date, power status).

**Validates: Requirements 2.4, 7.1, 7.2, 7.3, 7.4**

### Property 7: Historical Trend Presence

*For any* sensor card in expanded state with available historical data, the render tree should include a historical trend visualization component.

**Validates: Requirements 2.5, 5.1**

### Property 8: Expansion Control State Indication

*For any* sensor card, the expansion control's visual appearance (rotation or icon) should differ between collapsed and expanded states.

**Validates: Requirements 2.6**

### Property 9: Single Expansion Policy

*For any* sensor card list with one card expanded, expanding a different card should cause the originally expanded card to transition to collapsed state, resulting in at most one expanded card.

**Validates: Requirements 4.1**

### Property 10: Viewport Scroll Adjustment

*For any* sensor card that expands while positioned such that its full expanded content would extend beyond the viewport, the scroll position should adjust to keep the card's content visible.

**Validates: Requirements 4.3**

### Property 11: Chart Axes Presence

*For any* rendered historical trend chart, the visualization should include labeled axes for time and sensor value.

**Validates: Requirements 5.3**

### Property 12: Height Animation Smoothness

*For any* state transition, the sensor card height should be animated using a non-linear easing curve (not linear interpolation).

**Validates: Requirements 6.1, 6.3**

### Property 13: Expansion Control Animation

*For any* state transition, the expansion control icon should animate its rotation or appearance during the transition.

**Validates: Requirements 6.2**

### Property 14: Tap Blocking During Animation

*For any* sensor card with an animation in progress, tap gestures should be ignored until the animation completes.

**Validates: Requirements 6.4**

### Property 15: Conditional Threshold Display

*For any* sensor with configured alert thresholds, the expanded state should display the threshold values. For any sensor without thresholds, no threshold section should be displayed.

**Validates: Requirements 7.5**

### Property 16: Expansion State Persistence During Scroll

*For any* sensor card in expanded state, scrolling the list (including scrolling the card out of and back into the viewport) should maintain the expanded state.

**Validates: Requirements 8.1, 8.2**

### Property 17: Theme-Based Styling

*For any* Flutter theme configuration, the sensor card styling (colors, text styles, elevation) should reflect the theme's color scheme and text theme values.

**Validates: Requirements 9.3**

### Property 18: Graceful Null Handling

*For any* sensor data with null or missing optional fields (location, installation date, battery level, thresholds), the card should render without errors, displaying "N/A" or omitting the field as appropriate.

**Validates: Requirements 9.4**

### Property 19: Semantic Label Presence

*For any* sensor card, semantic labels describing the sensor name, value, status, and expansion state should be present and accessible to screen readers.

**Validates: Requirements 10.1**

### Property 20: Expansion Control Focusability

*For any* expansion control, it should be focusable for keyboard navigation.

**Validates: Requirements 10.2**

### Property 21: Keyboard Activation Response

*For any* focused expansion control, pressing the Enter or Space key should toggle the expansion state.

**Validates: Requirements 10.3**

### Property 22: State Change Announcement

*For any* state transition, an accessibility announcement should be triggered to inform assistive technologies of the state change.

**Validates: Requirements 10.4**

### Property 23: Minimum Touch Target Size

*For any* expansion control, the hit test area should be at least 48x48 density-independent pixels.

**Validates: Requirements 10.5**

## Future Enhancements

Potential extensions beyond the current scope:

1. **Swipe Gestures**: Allow swipe-to-expand/collapse as an alternative to tap
2. **Multi-Expansion Mode**: Optional mode allowing multiple cards expanded simultaneously
3. **Card Sorting**: Allow users to reorder cards by dragging or sort by priority/status
4. **Historical Data Range Selection**: Let users choose the time range for trend charts (1h, 6h, 24h, 7d)
5. **Export Functionality**: Export sensor data or trend charts as images/CSV
6. **Customizable Card Content**: Allow users to configure which fields appear in collapsed vs expanded states
7. **Card Actions**: Add action buttons (acknowledge alert, mute notifications, etc.) to expanded cards
8. **Comparison Mode**: Select multiple sensors to view their trends side-by-side

