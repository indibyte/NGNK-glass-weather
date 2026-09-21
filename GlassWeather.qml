import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  function open(payloadJson) {}
  function close() {}

  readonly property string layerNamespace: "NGNK.glass-weather"
  readonly property string glassRuleName: root.layerNamespace + "-glass"

  readonly property color glassTint: Color.popups.background
  readonly property color glassEdge: Color.popups.text
  readonly property color glassInk: Color.popups.text
  readonly property color glassAccent: Color.accent

  readonly property string configPath: Quickshell.env("HOME")
    + "/.config/omarchy/glass-weather.json"

  property bool blurEnabled: true

  readonly property real bodyAlpha: root.blurEnabled ? 0.42 : 0.64
  readonly property real sheenAlpha: 0.13
  readonly property real shadeAlpha: 0.14

  readonly property int cornerRadius: Math.max(Style.cornerRadius, Style.space(22))
  readonly property int padX: Style.space(32)
  readonly property int padY: Style.space(26)
  readonly property int edgeMargin: Style.space(30) + Style.gapsOut
  readonly property int topMargin: Style.bar.sizeHorizontal + Style.gapsOut
    + Style.space(20) + Math.round(Style.space(150)) + Style.space(20)

  readonly property int locationSize: Style.fontPx(1.1)
  readonly property int conditionSize: Style.fontPx(0.95)
  readonly property int metricSize: Style.fontPx(0.85)
  readonly property int tempSize: Style.fontPx(3.6)
  readonly property int glyphSize: Style.fontPx(2.6)
  readonly property int rowGap: Style.space(12)

  readonly property int editorBaseHeight: Style.space(56)
  readonly property int editorRowHeight: Style.space(38)
  readonly property int editorHintHeight: Style.space(30)

  readonly property int panelMinWidth: Style.space(299)
  readonly property int panelMinHeight: Style.space(376)
  readonly property int contentWidth: root.panelMinWidth - root.padX * 2

  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    var best = null
    for (var i = 0; i < screens.length; i++) {
      var candidate = screens[i]
      if (!candidate || candidate.width <= 0 || candidate.height <= 0) continue
      if (!best || candidate.width * candidate.height > best.width * best.height) best = candidate
    }
    return best
  }

  property var glassQueue: []

  function glassCommands() {
    if (Hyprland.usingLua) {
      return [[
        "hyprctl", "eval",
        'hl.layer_rule({ name = "' + root.glassRuleName + '"'
          + ', match = { namespace = "^' + root.layerNamespace + '$" }'
          + ", blur = true, ignore_alpha = 0.05, enabled = true })"
      ]]
    }
    return [
      ["hyprctl", "keyword", "layerrule", "blur, " + root.layerNamespace],
      ["hyprctl", "keyword", "layerrule", "ignorealpha 0.05, " + root.layerNamespace]
    ]
  }

  function applyGlass() {
    root.glassQueue = root.glassCommands()
    root.runNextGlass()
  }

  function runNextGlass() {
    if (blurProc.running || root.glassQueue.length === 0) return
    var pending = root.glassQueue.slice(1)
    blurProc.command = root.glassQueue[0]
    root.glassQueue = pending
    blurProc.running = true
  }

  function probeBlur() {
    blurProbe.running = true
  }

  Process {
    id: blurProc
    onExited: root.runNextGlass()
  }

  Process {
    id: blurProbe
    command: ["hyprctl", "-j", "getoption", "decoration:blur:enabled"]
    stdout: StdioCollector {
      id: blurProbeOut
      waitForEnd: true
      onStreamFinished: {
        try {
          root.blurEnabled = !!JSON.parse(blurProbeOut.text || "{}").bool
        } catch (error) {
          root.blurEnabled = true
        }
      }
    }
  }

  property string state: "idle"
  property string placeName: ""
  property real latitude: 0
  property real longitude: 0
  property string tempUnit: "celsius"

  function fahrenheitCountry(countryCode) {
    return countryCode === "US" || countryCode === "LR" || countryCode === "MM"
  }

  readonly property string tempUnitLabel: root.tempUnit === "fahrenheit" ? "F" : "C"

  property int weatherCode: 0
  property real tempDisplay: 0
  property real feelsLike: 0
  property real humidity: 0
  property real windSpeed: 0
  property bool isDay: true
  property int todayMax: 0
  property int todayMin: 0
  property var weekly: []
  property string updatedAt: ""
  property bool editing: false
  readonly property string weekdayFormat: "ddd"
  property string editQuery: ""
  property var candidates: []
  property int candidateIndex: -1
  property bool searchActive: false

  readonly property var condition: root.conditionFor(root.weatherCode, root.isDay)

  function conditionFor(code, day) {
    if (code === 0) return { glyph: day ? "\u2600" : "\uD83C\uDF19", label: day ? "Clear sky" : "Clear night", back: day ? "#FFC94D" : "#8A9BD4" }
    if (code === 1) return { glyph: "\uD83C\uDF24", label: "Mostly clear", back: "#FFD98E" }
    if (code === 2) return { glyph: "\u26C5", label: "Partly cloudy", back: "#B8C9DA" }
    if (code === 3) return { glyph: "\u2601", label: "Overcast", back: "#9FB2C4" }
    if (code === 45 || code === 48) return { glyph: "\uD83C\uDF2B", label: "Foggy", back: "#A3B1BD" }
    if (code === 51 || code === 53 || code === 55) return { glyph: "\uD83C\uDF26", label: "Drizzle", back: "#7FB3E3" }
    if (code === 56 || code === 57) return { glyph: "\uD83C\uDF27", label: "Freezing drizzle", back: "#7FB3E3" }
    if (code === 61 || code === 63 || code === 65) return { glyph: "\uD83C\uDF27", label: "Rain", back: "#5B9BD5" }
    if (code === 66 || code === 67) return { glyph: "\uD83C\uDF27", label: "Freezing rain", back: "#5B9BD5" }
    if (code === 71 || code === 73 || code === 75) return { glyph: "\uD83C\uDF28", label: "Snow", back: "#BFE3F7" }
    if (code === 77) return { glyph: "\uD83C\uDF28", label: "Snow grains", back: "#BFE3F7" }
    if (code === 80 || code === 81 || code === 82) return { glyph: "\uD83C\uDF26", label: "Rain showers", back: "#7FB3E3" }
    if (code === 85 || code === 86) return { glyph: "\uD83C\uDF28", label: "Snow showers", back: "#BFE3F7" }
    if (code === 95) return { glyph: "\u26C8", label: "Thunderstorm", back: "#FFB64D" }
    if (code === 96 || code === 99) return { glyph: "\u26C8", label: "Storm with hail", back: "#FFB64D" }
    return { glyph: "\u2600", label: "Unknown", back: "#B8C9DA" }
  }

  function forecastGlyphFor(code) {
    if (code === 0) return "\u2600"
    if (code === 1) return "\uD83C\uDF24"
    if (code === 2) return "\u26C5"
    if (code === 3) return "\u2601"
    if (code === 45 || code === 48) return "\uD83C\uDF2B"
    if (code === 51 || code === 53 || code === 55 || code === 80 || code === 81 || code === 82) return "\uD83C\uDF26"
    if (code === 56 || code === 57 || code === 61 || code === 63 || code === 65 || code === 66 || code === 67) return "\uD83C\uDF27"
    if (code === 71 || code === 73 || code === 75 || code === 77 || code === 85 || code === 86) return "\uD83C\uDF28"
    if (code >= 95) return "\u26C8"
    return "\u2600"
  }

  function geocodeCommand(query) {
    return ["curl", "-fsS", "-m", "15",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(query)
      + "&count=1&language=en&format=json"]
  }

  function searchCommand(query) {
    return ["curl", "-fsS", "-m", "15",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(query)
      + "&count=6&language=en&format=json"]
  }

  function weatherCommand() {
    return ["curl", "-fsS", "-m", "15",
      "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude
      + "&longitude=" + root.longitude
      + "&temperature_unit=" + (root.tempUnit === "fahrenheit" ? "fahrenheit" : "celsius")
      + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
      + "&daily=temperature_2m_max,temperature_2m_min,weather_code"
      + "&forecast_days=5"
      + "&timezone=auto"]
  }

  function fetchWeather() {
    if (root.latitude === 0 && root.longitude === 0) return
    root.state = "loading"
    weatherProc.command = root.weatherCommand()
    weatherProc.running = true
  }

  function parseWeather(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var current = json.current
      if (!current) throw new Error("empty")
      root.weatherCode = Number(current.weather_code) || 0
      root.tempDisplay = Math.round(Number(current.temperature_2m))
      root.feelsLike = Math.round(Number(current.apparent_temperature))
      root.humidity = Math.round(Number(current.relative_humidity_2m))
      root.windSpeed = Number(current.wind_speed_10m)
      root.isDay = Number(current.is_day) === 1
      if (json.daily && json.daily.temperature_2m_max) root.todayMax = Math.round(Number(json.daily.temperature_2m_max[0]))
      if (json.daily && json.daily.temperature_2m_min) root.todayMin = Math.round(Number(json.daily.temperature_2m_min[0]))
      root.weekly = []
      if (json.daily && json.daily.time) {
        var times = json.daily.time
        var highs = json.daily.temperature_2m_max || []
        var lows = json.daily.temperature_2m_min || []
        var codes = json.daily.weather_code || []
        var built = []
        for (var i = 0; i < times.length; i++) {
          built.push({
            day: Qt.formatDate(new Date(String(times[i]) + "T00:00:00"), root.weekdayFormat),
            code: Number(codes[i]) || 0,
            high: Math.round(Number(highs[i])),
            low: Math.round(Number(lows[i]))
          })
        }
        root.weekly = built
      }
      root.updatedAt = Qt.formatTime(new Date(), "HH:mm")
      root.state = "ready"
      root.probeBlur()
    } catch (error) {
      root.state = "error"
    }
  }

  function geocode(query) {
    var q = String(query || "").trim()
    if (q.length === 0) {
      root.state = "idle"
      root.placeName = ""
      return
    }
    root.state = "loading"
    geocodeProc.command = root.geocodeCommand(q)
    geocodeProc.running = true
  }

  function parseGeocode(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var hit = (json.results && json.results.length > 0) ? json.results[0] : null
      if (!hit) throw new Error("not found")
      root.latitude = Number(hit.latitude)
      root.longitude = Number(hit.longitude)
      root.tempUnit = root.fahrenheitCountry(String(hit.country_code || "")) ? "fahrenheit" : "celsius"
      var place = String(hit.name || "")
      var region = String(hit.admin1 || hit.country || "")
      root.placeName = region.length > 0 && region !== place ? place + ", " + region : place
      root.fetchWeather()
    } catch (error) {
      root.placeName = ""
      root.state = "error"
    }
  }

  function applyConfig() {
    if (!configFile.loaded) return
    var q = String(locationAdapter.query || "").trim()
    if (q.length === 0) {
      root.state = "idle"
      root.placeName = ""
      return
    }
    geocodeTimer.restart()
  }

  function beginEdit() {
    root.editQuery = String(locationAdapter.query || root.placeName || "")
    root.candidates = []
    root.candidateIndex = -1
    root.searchActive = false
    root.editing = true
    Qt.callLater(function() {
      locationInput.forceActiveFocus()
      locationInput.selectAll()
    })
  }

  function searchCities(query) {
    var q = String(query || "").trim()
    if (q.length === 0) {
      root.candidates = []
      root.candidateIndex = -1
      root.searchActive = false
      return
    }
    root.searchActive = true
    searchProc.command = root.searchCommand(q)
    searchProc.running = true
  }

  function applyCandidates(raw) {
    try {
      var json = JSON.parse(raw || "{}")
      var hits = json.results || []
      root.candidates = hits.map(function(hit) {
        var region = String(hit.admin1 || hit.country || "")
        var display = region.length > 0 && region !== hit.name
          ? String(hit.name) + ", " + region : String(hit.name || "")
        return {
          name: display,
          region: region,
          country: String(hit.country || ""),
          countryCode: String(hit.country_code || ""),
          latitude: Number(hit.latitude),
          longitude: Number(hit.longitude)
        }
      })
      root.candidateIndex = root.candidates.length > 0 ? 0 : -1
    } catch (error) {
      root.candidates = []
      root.candidateIndex = -1
    }
  }

  function pickCandidate(index) {
    var candidate = root.candidates[index]
    if (!candidate) return
    locationAdapter.query = candidate.name
    root.placeName = candidate.name
    root.latitude = candidate.latitude
    root.longitude = candidate.longitude
    root.tempUnit = root.fahrenheitCountry(candidate.countryCode) ? "fahrenheit" : "celsius"
    root.candidates = []
    root.candidateIndex = -1
    root.searchActive = false
    root.editing = false
    root.fetchWeather()
  }

  function commitEdit() {
    if (root.candidateIndex >= 0 && root.candidates.length > 0) {
      root.pickCandidate(root.candidateIndex)
      return
    }
    var q = String(root.editQuery || "").trim()
    if (q.length === 0) return
    locationAdapter.query = q
    root.candidates = []
    root.candidateIndex = -1
    root.editing = false
    root.geocode(q)
  }

  function closeEdit() {
    root.candidates = []
    root.candidateIndex = -1
    root.searchActive = false
    root.editing = false
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      id: geocodeOut
      waitForEnd: true
      onStreamFinished: root.parseGeocode(geocodeOut.text)
    }
  }

  Process {
    id: weatherProc
    stdout: StdioCollector {
      id: weatherOut
      waitForEnd: true
      onStreamFinished: root.parseWeather(weatherOut.text)
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: root.applyCandidates(searchOut.text)
    }
  }

  JsonAdapter {
    id: locationAdapter
    property string query: ""
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    onFileChanged: root.applyConfig()
    onLoaded: root.applyConfig()
    onLoadFailed: (error) => {
      if (error === FileViewError.FileNotFound) configFile.writeAdapter()
    }
    onAdapterUpdated: saveTimer.restart()

    adapter: locationAdapter
  }

  Timer {
    id: saveTimer
    interval: 300
    repeat: false
    onTriggered: configFile.writeAdapter()
  }

  Timer {
    id: geocodeTimer
    interval: 350
    repeat: false
    onTriggered: root.geocode(String(locationAdapter.query || ""))
  }

  Timer {
    id: searchTimer
    interval: 260
    repeat: false
    onTriggered: root.searchCities(root.editQuery)
  }

  Timer {
    id: refreshTimer
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.fetchWeather()
  }

  Component.onCompleted: {
    root.applyGlass()
    root.probeBlur()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded") {
        root.applyGlass()
        root.probeBlur()
      }
    }
  }

  PanelWindow {
    id: win

    screen: root.targetScreen
    color: "transparent"

    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      right: true
    }

    margins {
      top: root.topMargin
      right: root.edgeMargin
    }

    exclusionMode: ExclusionMode.Ignore

    implicitWidth: root.panelMinWidth
    implicitHeight: root.panelMinHeight

    Rectangle {
      id: body
      anchors.fill: parent
      radius: root.cornerRadius
      color: Util.alpha(root.glassTint, root.bodyAlpha)
      border.width: 1
      border.color: Util.alpha(root.glassEdge, 0.16)

      Rectangle {
        anchors.fill: parent
        anchors.margins: body.border.width
        radius: Math.max(0, root.cornerRadius - body.border.width)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha("#ffffff", root.sheenAlpha) }
          GradientStop { position: 0.5; color: Util.alpha("#ffffff", 0.0) }
          GradientStop { position: 1.0; color: Util.alpha("#000000", root.shadeAlpha) }
        }
      }
    }

    Item {
      id: content
      width: root.contentWidth
      height: root.panelMinHeight - root.padY * 2
      anchors.centerIn: parent

      Text {
        id: locationText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: Math.min(implicitWidth, parent.width)
        elide: Text.ElideRight
        text: {
          if (root.state === "idle") return "Click to set location"
          if (root.state === "loading" && root.placeName.length === 0) return "Locating..."
          if (root.state === "error") return "Location not found"
          return root.placeName
        }
        color: Util.alpha(root.glassAccent, 0.9)
        font.family: Style.font.family
        font.pixelSize: root.locationSize
        font.letterSpacing: Style.space(1)
      }

      Row {
        id: currentRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: locationText.bottom
        anchors.topMargin: Style.space(6)
        spacing: Style.space(18)
        visible: root.state === "ready"

        Item {
          id: iconHost
          width: Style.space(88)
          height: Style.space(88)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: Util.alpha(root.condition.back, 0.18)
          }

          Text {
            anchors.centerIn: parent
            text: root.condition.glyph
            font.family: "Noto Color Emoji"
            font.pixelSize: Style.fontPx(3.4)
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.tempDisplay + "\u00B0" + root.tempUnitLabel
          color: root.glassInk
          font.family: Style.font.family
          font.pixelSize: Style.fontPx(4.2)
          font.weight: Font.Light
          font.letterSpacing: Style.space(1)
        }
      }

      Text {
        id: statusText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: locationText.bottom
        anchors.topMargin: Style.space(20)
        text: root.state === "ready" ? "" : (root.state === "loading" ? "Loading..." : "—")
        color: Util.alpha(root.glassInk, 0.75)
        font.family: Style.font.family
        font.pixelSize: root.tempSize
        font.letterSpacing: Style.space(1)
      }

      Text {
        id: conditionText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: currentRow.bottom
        anchors.topMargin: Style.space(2)
        text: root.condition.label
        color: Util.alpha(root.glassInk, 0.85)
        font.family: Style.font.family
        font.pixelSize: root.conditionSize
        font.letterSpacing: Style.space(1)
        visible: root.state === "ready"
      }

      Rectangle {
        id: divider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: conditionText.bottom
        anchors.topMargin: Style.space(10)
        height: 1
        color: Util.alpha(root.glassInk, 0.15)
        visible: root.state === "ready"
      }

      Column {
        id: forecastCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: divider.bottom
        anchors.topMargin: Style.space(8)
        spacing: Style.space(5)
        visible: root.state === "ready" && root.weekly.length > 0

        Repeater {
          id: forecastRepeater
          model: root.weekly

          Row {
            width: forecastCol.width
            height: Style.space(30)
            spacing: Style.space(0)

            Text {
              width: Style.space(56)
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              text: modelData.day
              color: Util.alpha(root.glassInk, 0.75)
              font.family: Style.font.family
              font.pixelSize: root.metricSize
            }

            Text {
              width: Style.space(40)
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignHCenter
              text: root.forecastGlyphFor(modelData.code)
              font.family: "Noto Color Emoji"
              font.pixelSize: Style.fontPx(1.2)
            }

            Item {
              width: forecastCol.width - Style.space(56) - Style.space(40) - Style.space(48) - Style.space(48)
              height: parent.height
            }

            Text {
              width: Style.space(48)
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignRight
              text: modelData.high + "\u00B0"
              color: root.glassInk
              font.family: Style.font.family
              font.pixelSize: root.metricSize
              font.weight: Font.Medium
            }

            Text {
              width: Style.space(48)
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignRight
              text: modelData.low + "\u00B0"
              color: Util.alpha(root.glassInk, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.fontPx(0.78)
            }
          }
        }
      }
    }

    MouseArea {
      id: editArea
      anchors.fill: parent
      z: 1
      onClicked: root.editing ? root.closeEdit() : root.beginEdit()
    }
  }

  PanelWindow {
    id: editWin

    screen: root.targetScreen
    color: "transparent"
    visible: root.editing

    WlrLayershell.namespace: root.layerNamespace + "-edit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Util.alpha("#000000", 0.35)
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      onClicked: root.closeEdit()
    }

    Item {
      id: editCard
      width: root.contentWidth + root.padX * 2
      height: root.editorBaseHeight
        + (root.candidates.length > 0
            ? root.candidates.length * root.editorRowHeight
            : (root.searchActive ? root.editorHintHeight : 0))
      anchors.top: parent.top
      anchors.topMargin: root.topMargin
      anchors.right: parent.right
      anchors.rightMargin: root.edgeMargin

      Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: Util.alpha(root.glassTint, root.bodyAlpha)
        border.width: 1
        border.color: Util.alpha(root.glassEdge, 0.24)

        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: Math.max(0, root.cornerRadius - 1)
          gradient: Gradient {
            GradientStop { position: 0.0; color: Util.alpha("#ffffff", root.sheenAlpha) }
            GradientStop { position: 1.0; color: Util.alpha("#000000", root.shadeAlpha) }
          }
        }
      }

      MouseArea {
        id: cardBlocker
        anchors.fill: parent
        z: 0
        onClicked: root.closeEdit()
      }

      TextInput {
        id: locationInput
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.editorBaseHeight
        verticalAlignment: TextInput.AlignVCenter
        anchors.leftMargin: root.padX
        anchors.rightMargin: root.padX
        z: 1
        text: root.editQuery
        color: root.glassInk
        selectionColor: Util.alpha(root.glassAccent, 0.55)
        font.family: Style.font.family
        font.pixelSize: root.locationSize
        selectByMouse: true
        cursorVisible: true
        activeFocusOnPress: true

        onTextEdited: {
          root.editQuery = locationInput.text
          searchTimer.restart()
        }

        Keys.onPressed: (event) => {
          if (event.key === Qt.Key_Escape) {
            root.closeEdit(); event.accepted = true; return
          }
          if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            var count = root.candidates.length
            if (count > 0) {
              var delta = event.key === Qt.Key_Down ? 1 : -1
              root.candidateIndex = (root.candidateIndex + delta + count) % count
            }
            event.accepted = true
          }
        }

        onAccepted: root.commitEdit()
      }

      Item {
        id: editorStatus
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: locationInput.bottom
        height: root.editorHintHeight
        visible: root.searchActive && root.candidates.length === 0

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Searching Open-Meteo..."
          color: Util.alpha(root.glassInk, 0.55)
          font.family: Style.font.family
          font.pixelSize: root.metricSize
          font.letterSpacing: Style.space(1)
        }
      }

      Column {
        id: candidateList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: locationInput.bottom
        spacing: 2

        Repeater {
          id: candidateRepeater
          model: root.candidates

          Item {
            width: candidateList.width
            height: root.editorRowHeight

            Rectangle {
              anchors.fill: parent
              visible: index === root.candidateIndex
              color: Util.alpha(root.glassAccent, 0.2)
              radius: Style.space(6)
            }

            MouseArea {
              id: candidateRowArea
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onEntered: root.candidateIndex = index
              onClicked: root.pickCandidate(index)
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: root.padX
              anchors.rightMargin: root.padX
              elide: Text.ElideRight
              text: {
                var c = root.candidates[index]
                return c ? c.name + (c.country ? " \u00B7 " + c.country : "") : ""
              }
              color: index === root.candidateIndex ? root.glassAccent : root.glassInk
              font.family: Style.font.family
              font.pixelSize: root.metricSize
              font.letterSpacing: Style.space(1)
            }
          }
        }
      }
    }
  }
}