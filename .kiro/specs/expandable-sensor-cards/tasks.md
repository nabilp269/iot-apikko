# Implementation Plan: Expandable Sensor Cards

## Overview

This implementation plan breaks down the expandable sensor cards feature into discrete coding tasks. The feature transforms the existing static sensor display into an interactive card-based interface with expand/collapse functionality, animations, and historical trend visualization.

## Tasks

- [x] 1. Create data models and supporting types
  - Create `lib/models/sensor_data.dart` file
  - Define `SensorData` class with all required and optional fields
  - Define `SensorStatus` enum (normal, warning, danger)
  - Define `SensorType` enum (temperature, humidity, flame, gas)
  - Define `SensorThresholds` class for threshold values
  - Define `SensorDataPoint` class for historical data points
  - Add JSON serialization methods if needed for future API integration
  - _Requirements: 1.2, 2.4, 7.1, 7.2, 7.3, 7.4, 7.5, 9.1_

- [ ]* 1.1 Write unit tests for data models
  - Test `SensorData` instantiation with all fields
  - Test `SensorData` with null optional fields
  - Test enum value handling
  - _Requirements: 9.4_

- [x] 2. Implement HistoricalTrendChart widget
  - [x] 2.1 Create `lib/widgets/historical_trend_chart.dart` file
    - Create stateless widget accepting historical data, loading state, and sensor unit
    - Implement chart rendering using fl_chart package or custom painter
    - Add labeled axes for time (x-axis) and value (y-axis)
    - Support theme-based styling for chart colors
    - _Requirements: 2.5, 5.1, 5.2, 5.3, 9.3_
  
  - [x] 2.2 Add loading and empty state handling
    - Display `CircularProgressIndicator` when `isLoading` is true
    - Display "No historical data available" message with icon when data is null
    - Handle empty data list gracefully
    - _Requirements: 5.4, 5.5_
  
  - [ ]* 2.3 Write property test for HistoricalTrendChart
    - **Property 7: Historical Trend Presence**
    - **Validates: Requirements 2.5, 5.1**
    - Generate arbitrary lists of `SensorDataPoint` and verify chart renders without errors
  
  - [ ]* 2.4 Write property test for chart axes
    - **Property 11: Chart Axes Presence**
    - **Validates: Requirements 5.3**
    - Verify rendered chart contains labeled axes widgets

- [x] 3. Implement SensorCard widget
  - [x] 3.1 Create `lib/widgets/sensor_card.dart` file
    - Define stateful widget with `SensorData`, `onExpansionChanged` callback, and `initiallyExpanded` parameters
    - Set up state class with `SingleTickerProviderStateMixin`
    - Initialize `_isExpanded` boolean state variable
    - _Requirements: 2.1, 3.1, 9.1, 9.2_
  
  - [x] 3.2 Set up animation controller and animations
    - Create `AnimationController` with 300ms duration in `initState`
    - Define `_heightAnimation` with `Tween<double>` and `CurvedAnimation` using `Curves.easeInOutCubic`
    - Define `_iconRotationAnimation` for 180° rotation (0.0 to 0.5 turns)
    - Initialize expanded state based on `initiallyExpanded` parameter
    - Dispose animation controller in `dispose` method
    - _Requirements: 2.2, 2.3, 3.2, 3.3, 6.1, 6.2, 6.3_
  
  - [x] 3.3 Build collapsed state UI
    - Use `Card` widget with theme-based styling
    - Display sensor type icon with themed color (24dp)
    - Display sensor name using `theme.textTheme.titleMedium`
    - Display current value and unit using `theme.textTheme.headlineSmall` with bold weight
    - Display status badge as colored chip
    - Display status indicator as 8dp colored circle
    - Add expansion control chevron icon with rotation animation
    - Apply semantic labels for screen readers
    - _Requirements: 1.2, 1.3, 2.6, 9.3, 10.1_
  
  - [x] 3.4 Build expanded state UI
    - Display all collapsed content at top
    - Add divider line separating sections
    - Create metadata section with 2-column grid layout
    - Display location using `_buildMetadataField` helper
    - Display sensor type information
    - Display installation date formatted as readable string
    - Display last update as relative time (e.g., "2 seconds ago")
    - Display battery level or power status
    - Conditionally display threshold values if configured
    - Integrate `HistoricalTrendChart` widget with sensor's historical data
    - Handle null/missing optional fields gracefully (display "N/A")
    - _Requirements: 2.4, 2.5, 7.1, 7.2, 7.3, 7.4, 7.5, 9.4_
  
  - [x] 3.5 Implement tap gesture handling
    - Wrap card in `GestureDetector` with `onTap` handler
    - Implement `_handleTap` method that toggles `_isExpanded` state
    - Call `_animationController.forward()` when expanding
    - Call `_animationController.reverse()` when collapsing
    - Invoke `onExpansionChanged` callback to notify parent
    - Block taps during animation using `_animationController.isAnimating` check
    - Announce state changes to assistive technologies using `SemanticsService.announce`
    - _Requirements: 2.1, 3.1, 6.4, 10.4_
  
  - [x] 3.6 Add accessibility support
    - Wrap card in `Semantics` widget with descriptive labels
    - Include sensor name, value, status in semantic value
    - Set `expanded` property to `_isExpanded` state
    - Mark as button and provide `onTap` semantic action
    - Implement keyboard navigation with `RawKeyboardListener` responding to Enter/Space keys
    - Wrap expansion control in `InkWell` with minimum 48x48dp constraints
    - Add `focusable` property and tap hint
    - _Requirements: 10.1, 10.2, 10.3, 10.5_

- [ ]* 3.7 Write property tests for SensorCard widget
  - **Property 1: Default Collapsed State**
  - **Validates: Requirements 1.1**
  - Verify all cards initialize in collapsed state
  - **Property 2: Collapsed Content Completeness**
  - **Validates: Requirements 1.2, 1.3**
  - Verify collapsed state contains name, value, unit, status indicator
  - **Property 3: Collapsed Height Constraint**
  - **Validates: Requirements 1.4**
  - Verify collapsed height is less than 150dp and less than expanded height

- [ ]* 3.8 Write property tests for tap interaction
  - **Property 4: Tap Toggles Expansion State**
  - **Validates: Requirements 2.1, 3.1**
  - Verify tapping collapsed card expands it and tapping expanded card collapses it
  - **Property 5: Transition Animation Duration**
  - **Validates: Requirements 2.3, 3.3**
  - Verify animation completes within 300ms

- [ ]* 3.9 Write property tests for expanded content
  - **Property 6: Expanded Content Completeness**
  - **Validates: Requirements 2.4, 7.1, 7.2, 7.3, 7.4**
  - Verify expanded state contains all collapsed content plus metadata fields
  - **Property 8: Expansion Control State Indication**
  - **Validates: Requirements 2.6**
  - Verify expansion control visual appearance differs between states

- [ ]* 3.10 Write property tests for animation behavior
  - **Property 12: Height Animation Smoothness**
  - **Validates: Requirements 6.1, 6.3**
  - Verify non-linear easing curve is used for height animation
  - **Property 13: Expansion Control Animation**
  - **Validates: Requirements 6.2**
  - Verify expansion control animates rotation during transition
  - **Property 14: Tap Blocking During Animation**
  - **Validates: Requirements 6.4**
  - Verify tap gestures are ignored during animation

- [ ]* 3.11 Write property tests for data handling
  - **Property 15: Conditional Threshold Display**
  - **Validates: Requirements 7.5**
  - Verify thresholds displayed when configured, absent when not configured
  - **Property 18: Graceful Null Handling**
  - **Validates: Requirements 9.4**
  - Verify card renders without errors for null optional fields

- [ ]* 3.12 Write property tests for accessibility
  - **Property 19: Semantic Label Presence**
  - **Validates: Requirements 10.1**
  - Verify semantic labels present and accessible
  - **Property 20: Expansion Control Focusability**
  - **Validates: Requirements 10.2**
  - Verify expansion control is focusable
  - **Property 21: Keyboard Activation Response**
  - **Validates: Requirements 10.3**
  - Verify Enter/Space keys toggle expansion
  - **Property 22: State Change Announcement**
  - **Validates: Requirements 10.4**
  - Verify accessibility announcement on state change
  - **Property 23: Minimum Touch Target Size**
  - **Validates: Requirements 10.5**
  - Verify expansion control hit area is at least 48x48dp

- [x] 4. Implement SensorCardList widget
  - [x] 4.1 Create `lib/widgets/sensor_card_list.dart` file
    - Define stateful widget accepting list of `SensorData` objects
    - Set up state class with `_expandedCardIndex` tracking variable
    - Initialize `ScrollController` for scroll management
    - _Requirements: 4.1, 9.1_
  
  - [x] 4.2 Implement card expansion coordination
    - Define `_handleCardExpansion` method accepting card index and expansion state
    - Update `_expandedCardIndex` when a card expands
    - Call `setState` to rebuild list with new expansion states
    - Pass `initiallyExpanded` parameter to each `SensorCard` based on `_expandedCardIndex`
    - Ensure only one card is expanded at a time
    - _Requirements: 4.1_
  
  - [x] 4.3 Implement scroll position management
    - Define `_ensureCardVisible` method to adjust scroll position
    - Calculate card position in list and scroll to keep expanded card visible
    - Use `ScrollController.animateTo` with smooth animation
    - Call after card expansion state changes
    - _Requirements: 4.3_
  
  - [x] 4.4 Build ListView with SensorCard instances
    - Use `ListView.builder` for efficient rendering
    - Pass each sensor's data to `SensorCard`
    - Wire up `onExpansionChanged` callback to `_handleCardExpansion`
    - Pass `initiallyExpanded` based on `_expandedCardIndex` comparison
    - Add padding and spacing between cards
    - Dispose `ScrollController` in `dispose` method
    - _Requirements: 1.1, 4.2, 8.3_

- [ ]* 4.5 Write property tests for SensorCardList
  - **Property 9: Single Expansion Policy**
  - **Validates: Requirements 4.1**
  - Verify expanding one card collapses any previously expanded card
  - **Property 10: Viewport Scroll Adjustment**
  - **Validates: Requirements 4.3**
  - Verify scroll position adjusts to keep expanded card visible
  - **Property 16: Expansion State Persistence During Scroll**
  - **Validates: Requirements 8.1, 8.2**
  - Verify expanded state persists when scrolling card out and back into viewport

- [x] 5. Checkpoint - Ensure all widget tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Refactor server_monitoring_screen.dart to use new components
  - [x] 6.1 Add imports for new widgets and models
    - Import `sensor_data.dart`, `sensor_card_list.dart`
    - _Requirements: 9.1_
  
  - [x] 6.2 Create sensor data conversion method
    - Define `_sensorDataList` getter that converts existing state variables to `SensorData` objects
    - Create `SensorData` instance for temperature sensor with all fields
    - Create `SensorData` instance for humidity sensor with all fields
    - Create `SensorData` instance for flame sensor with all fields
    - Create `SensorData` instance for gas sensor with all fields
    - Include location, installation date, battery level, power status, thresholds
    - Call `_generateMockHistoricalData` for temperature, humidity, and gas sensors
    - Set `historicalData` to null for binary flame sensor
    - _Requirements: 1.2, 2.4, 7.1, 7.2, 7.3, 7.4, 7.5_
  
  - [x] 6.3 Implement mock historical data generator
    - Define `_generateMockHistoricalData` method accepting current value
    - Generate 24 `SensorDataPoint` instances (one per hour for last 24 hours)
    - Apply realistic variance around current value (±10%)
    - Return list of data points with timestamps
    - _Requirements: 5.1_
  
  - [x] 6.4 Add status determination helper methods
    - Define `_getTemperatureStatus` method returning `SensorStatus` based on temperature value
    - Define `_getHumidityStatus` method returning `SensorStatus` based on humidity value
    - Define `_getGasStatus` method returning `SensorStatus` based on gas value
    - Apply thresholds: danger (≥32°C temp, ≥2800 gas), warning (≥27°C temp, <30% or >60% humidity, ≥1800 gas)
    - _Requirements: 1.3_
  
  - [x] 6.5 Replace existing sensor card UI with SensorCardList
    - Remove old `_buildSensorCard` method and hardcoded grid layout
    - Replace with `SensorCardList` widget accepting `_sensorDataList`
    - Keep existing status banner, gas concentration bar, and simulation panel
    - Maintain existing simulation timer and state update logic
    - _Requirements: 1.1, 9.1_

- [ ]* 6.6 Write integration tests for server monitoring screen
  - Test sensor data conversion from state to `SensorData` objects
  - Test status determination methods with various input values
  - Test mock historical data generation
  - Verify `SensorCardList` receives correct data
  - _Requirements: 1.2, 1.3, 5.1_

- [ ] 7. Add theme-based styling support
  - [ ] 7.1 Update SensorCard to use Flutter theme
    - Use `Theme.of(context)` to access theme data
    - Apply `theme.cardTheme.color` and `theme.cardTheme.elevation` to Card widget
    - Apply `theme.textTheme.titleMedium` for sensor name
    - Apply `theme.textTheme.headlineSmall` for sensor value
    - Apply `theme.colorScheme.error` for danger status
    - Use theme colors for status indicators (normal: green, warning: amber, danger: error)
    - _Requirements: 9.3_
  
  - [ ] 7.2 Update HistoricalTrendChart to use Flutter theme
    - Apply theme colors to chart lines and axes
    - Use theme text styles for axis labels
    - Ensure chart adapts to light/dark theme automatically
    - _Requirements: 9.3_

- [ ]* 7.3 Write property test for theme-based styling
  - **Property 17: Theme-Based Styling**
  - **Validates: Requirements 9.3**
  - Verify sensor card styling reflects theme configuration

- [ ] 8. Final integration and polish
  - [ ] 8.1 Verify all sensors display correctly in collapsed state
    - Test with simulation mode enabled
    - Verify all four sensors appear in list
    - Check spacing and alignment
    - _Requirements: 1.1, 1.2, 1.3, 1.4_
  
  - [ ] 8.2 Verify expand/collapse interactions work smoothly
    - Test tapping each sensor card to expand
    - Verify only one card expands at a time
    - Verify animations are smooth with correct duration
    - Verify collapse functionality
    - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 4.1, 6.1, 6.2, 6.3, 6.4_
  
  - [ ] 8.3 Verify expanded state displays all information
    - Check all metadata fields display correctly
    - Verify historical trend chart renders
    - Check threshold display for sensors with configured thresholds
    - Verify null field handling (flame sensor has no battery, no historical data)
    - _Requirements: 2.4, 2.5, 5.1, 5.2, 5.3, 7.1, 7.2, 7.3, 7.4, 7.5, 9.4_
  
  - [ ] 8.4 Test scroll behavior and state persistence
    - Expand a card and scroll up/down
    - Verify card remains expanded after scrolling out of view and back
    - Verify scroll adjusts to keep expanded card visible
    - _Requirements: 4.2, 4.3, 8.1, 8.2, 8.3_
  
  - [ ] 8.5 Test accessibility features
    - Enable TalkBack/VoiceOver and verify semantic labels
    - Test keyboard navigation (Tab to focus, Enter/Space to activate)
    - Verify state change announcements
    - Test touch target sizes
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [ ] 9. Final checkpoint - Ensure all tests pass
  - Run all unit tests, property tests, and integration tests
  - Fix any failing tests
  - Verify no regressions in existing functionality
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- The implementation uses Flutter's built-in animation system and Material Design components
- Property tests validate universal correctness properties from the design document
- Unit and integration tests validate specific examples and edge cases
- The historical trend chart requires the `fl_chart` package or custom painter implementation
- Checkpoints ensure incremental validation and provide opportunities for user feedback
- All new widgets follow Flutter best practices with proper lifecycle management and disposal

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1", "1.1"] },
    { "id": 1, "tasks": ["2.1", "2.2"] },
    { "id": 2, "tasks": ["2.3", "2.4", "3.1", "3.2"] },
    { "id": 3, "tasks": ["3.3", "3.4"] },
    { "id": 4, "tasks": ["3.5", "3.6"] },
    { "id": 5, "tasks": ["3.7", "3.8", "3.9", "3.10", "3.11", "3.12", "4.1", "4.2"] },
    { "id": 6, "tasks": ["4.3", "4.4"] },
    { "id": 7, "tasks": ["4.5", "6.1", "6.2", "6.3", "6.4"] },
    { "id": 8, "tasks": ["6.5"] },
    { "id": 9, "tasks": ["6.6", "7.1", "7.2"] },
    { "id": 10, "tasks": ["7.3", "8.1", "8.2", "8.3"] },
    { "id": 11, "tasks": ["8.4", "8.5"] }
  ]
}
```
