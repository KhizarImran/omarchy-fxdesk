import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "LandMask.js" as LandMask

// One bar pill and one panel: which FX sessions are open right now, when the
// next one turns over, and every release due today for the currencies you
// trade. Every fact about time comes from bin/fx-brief; this file only draws
// it and counts down.
Panel {
  id: root
  moduleName: "khizarimran.fxdesk"
  ipcTarget: "khizarimran.fxdesk"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var sessions: []
  property var events: []
  property string errorText: ""
  property bool loaded: false

  // The clock the whole widget reads. Everything else is derived from the
  // epochs the helper handed over, so a countdown never needs a subprocess.
  property int nowSec: Math.floor(Date.now() / 1000)

  readonly property string briefPath: String(Qt.resolvedUrl("bin/fx-brief")).replace(/^file:\/\//, "")

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return (value === undefined || value === null || value === "") ? fallback : value
  }

  readonly property string currencies: String(setting("currencies", "USD,EUR,JPY,GBP,CHF,AUD,NZD,CAD"))
  readonly property int refreshMinutes: Math.max(5, Number(setting("refreshMinutes", 60)) || 60)
  readonly property string impactArg: String(setting("impact", "High + Medium")) === "High" ? "High" : "High,Medium"

  // ------------------------------------------------------------- sessions

  // The first window that has not closed yet: current if we are inside it,
  // otherwise the next one. Weekends have no window, so a Friday evening
  // correctly points at Monday.
  function currentWindow(session) {
    var windows = session.windows || []
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].close > root.nowSec) return windows[i]
    }
    return null
  }

  function isOpen(session) {
    var window = currentWindow(session)
    return window !== null && window.open <= root.nowSec
  }

  function sessionState(session) {
    var window = currentWindow(session)
    if (!window) return "closed"
    if (window.open > root.nowSec) return "opens in " + delta(window.open - root.nowSec)
    return "open · closes in " + delta(window.close - root.nowSec)
  }

  readonly property string openCodes: {
    var out = []
    for (var i = 0; i < sessions.length; i++) {
      if (isOpen(sessions[i])) out.push(sessions[i].code)
    }
    return out.join("+")
  }

  // --------------------------------------------------------------- events

  readonly property var nextEvent: {
    for (var i = 0; i < events.length; i++) {
      if (events[i].at > nowSec) return events[i]
    }
    return null
  }

  function delta(seconds) {
    if (seconds < 0) seconds = 0
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h" + (minutes % 60 < 10 ? "0" : "") + (minutes % 60) + "m"
    return Math.floor(hours / 24) + "d"
  }

  function clock(epoch) {
    return Qt.formatTime(new Date(epoch * 1000), "HH:mm")
  }

  // Fixed hues, not theme tokens: red means "this one moves the market" on
  // every colour scheme, and a trader reads it before they read the words.
  readonly property color highColor: "#e05252"
  readonly property color mediumColor: "#e0a33e"
  readonly property color lowColor: Color.muted

  function impactColor(impact) {
    if (impact === "High") return root.highColor
    if (impact === "Medium") return root.mediumColor
    return root.lowColor
  }

  function figures(event) {
    if (event.forecast === "" && event.previous === "") return ""
    return "f " + (event.forecast === "" ? "–" : event.forecast)
      + "   p " + (event.previous === "" ? "–" : event.previous)
  }

  // Local midnight, the left edge of the session strip.
  function dayStart() {
    var date = new Date(root.nowSec * 1000)
    date.setHours(0, 0, 0, 0)
    return Math.floor(date.getTime() / 1000)
  }

  // ---------------------------------------------------------------- fetch

  function refresh(force) {
    if (fetch.running) return
    // A forced refresh still keeps a five-minute floor under the feed: it rate
    // limits hard, and a panel someone leans on would earn a 429 for the day.
    fetch.command = [root.briefPath,
                     "--ccy", root.currencies,
                     "--impact", root.impactArg,
                     "--max-age", String(force === true ? 300 : root.refreshMinutes * 60)]
    fetch.running = true
  }

  function apply(output) {
    var brief
    try {
      brief = JSON.parse(String(output || "{}"))
    } catch (e) {
      root.errorText = "fx-brief produced output that is not JSON"
      return
    }
    root.sessions = brief.sessions || []
    root.events = brief.events || []
    root.errorText = String(brief.error || "")
    root.loaded = true
    root.nowSec = Math.floor(Date.now() / 1000)
  }

  Process {
    id: fetch
    running: false
    command: [root.briefPath]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.errorText = text.trim().split("\n")[0]
    }
  }

  Timer {
    id: tick
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.nowSec = Math.floor(Date.now() / 1000)
  }

  Timer {
    id: poll
    interval: root.refreshMinutes * 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // ------------------------------------------------------------------ bar

  readonly property string barLabel: {
    var head = openCodes === "" ? "closed" : openCodes
    var event = nextEvent
    // The currency alone: what is coming, without a clock ticking in the bar.
    // The countdown is a hover away, and the panel has it in full.
    if (event && event.at - nowSec <= 12 * 3600) head += " · " + event.ccy
    return " " + head
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    root.refresh(false)
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(true); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    dimmed: root.openCodes === ""
    tooltipText: {
      var event = root.nextEvent
      if (!event) return root.openCodes === "" ? "FX market closed" : "Open: " + root.openCodes
      return event.ccy + " " + event.title + " at " + root.clock(event.at)
        + " · in " + root.delta(event.at - root.nowSec)
    }
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh(true) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(4)

          // The market day at a glance: land dots for orientation, the four
          // centres lighting up as they open, and today's session windows laid
          // against local midnight-to-midnight with a line on now.
          Canvas {
            id: worldMap
            x: Style.space(10)
            width: column.width - Style.space(20)

            readonly property real mapHeight: width * LandMask.height / LandMask.width
            readonly property real barHeight: Style.space(7)
            readonly property real barGap: Style.space(3)
            readonly property real stripTop: mapHeight + Style.space(8)
            readonly property real stripHeight: Math.max(1, root.sessions.length) * (barHeight + barGap)

            height: stripTop + stripHeight + Style.space(12)

            readonly property var cities: [
              { code: "SYD", lon: 151.2, lat: -33.9, label: "Sydney" },
              { code: "TKY", lon: 139.7, lat: 35.7, label: "Tokyo" },
              { code: "LDN", lon: -0.1, lat: 51.5, label: "London" },
              { code: "NY", lon: -74.0, lat: 40.7, label: "New York" }
            ]

            // Repainting is cheap but not free, and a shut panel is not worth
            // 1,400 arcs every fifteen seconds.
            readonly property var palette: [root.foreground, Color.accent, root.opened]
            onPaletteChanged: requestPaint()

            Connections {
              target: root
              function onNowSecChanged() { if (root.opened) worldMap.requestPaint() }
              function onSessionsChanged() { worldMap.requestPaint() }
            }

            function projectX(lon) { return (lon + 180) / 360 * width }
            function projectY(lat) {
              return (LandMask.latTop - lat) / (LandMask.latTop - LandMask.latBottom) * mapHeight
            }

            function sessionFor(code) {
              for (var i = 0; i < root.sessions.length; i++) {
                if (root.sessions[i].code === code) return root.sessions[i]
              }
              return null
            }

            function fade(color, alpha) {
              return Qt.rgba(color.r, color.g, color.b, alpha)
            }

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.font = Style.space(9) + "px " + root.fontFamily

              var cell = width / LandMask.width
              var radius = Math.max(0.6, cell * 0.30)
              var midnight = root.dayStart()
              var dusk = midnight + 86400

              ctx.fillStyle = fade(root.foreground, 0.30)
              for (var y = 0; y < LandMask.height; y++) {
                var row = LandMask.rows[y]
                for (var x = 0; x < LandMask.width; x++) {
                  if (row.charCodeAt(x) !== 49) continue
                  ctx.beginPath()
                  ctx.arc((x + 0.5) * cell, (y + 0.5) * cell, radius, 0, 6.2832)
                  ctx.fill()
                }
              }

              ctx.fillStyle = fade(root.foreground, 0.13)
              for (var hour = 0; hour <= 24; hour += 3) {
                ctx.fillRect(Math.round(hour / 24 * width), stripTop - Style.space(4),
                             1, stripHeight + Style.space(4))
              }

              // A window is drawn clipped to today, so a session running past
              // local midnight ends at the edge instead of off the strip.
              for (var i = 0; i < root.sessions.length; i++) {
                var session = root.sessions[i]
                var live = root.isOpen(session)
                var top = stripTop + i * (barHeight + barGap)
                var windows = session.windows || []
                for (var w = 0; w < windows.length; w++) {
                  var from = Math.max(windows[w].open, midnight)
                  var to = Math.min(windows[w].close, dusk)
                  if (to <= from) continue
                  var x0 = (from - midnight) / 86400 * width
                  var x1 = (to - midnight) / 86400 * width
                  ctx.fillStyle = live ? Color.accent : fade(Color.accent, 0.32)
                  ctx.fillRect(x0, top, Math.max(2, x1 - x0), barHeight)
                  if (x1 - x0 > Style.space(30)) {
                    ctx.fillStyle = Color.popups.background
                    ctx.fillText(session.code, x0 + Style.space(4), top + barHeight - Style.space(2))
                  }
                }
              }

              ctx.fillStyle = fade(root.foreground, 0.45)
              for (var label = 0; label <= 21; label += 3) {
                ctx.fillText(label < 10 ? "0" + label : String(label),
                             label / 24 * width + Style.space(2), height - Style.space(2))
              }

              for (var c = 0; c < cities.length; c++) {
                var city = cities[c]
                var owner = sessionFor(city.code)
                var lit = owner !== null && root.isOpen(owner)
                var cx = projectX(city.lon)
                var cy = projectY(city.lat)

                if (lit) {
                  ctx.fillStyle = fade(Color.accent, 0.22)
                  ctx.beginPath(); ctx.arc(cx, cy, Style.space(6), 0, 6.2832); ctx.fill()
                }
                ctx.fillStyle = lit ? Color.accent : fade(root.foreground, 0.55)
                ctx.beginPath(); ctx.arc(cx, cy, Math.max(1.5, Style.space(2)), 0, 6.2832); ctx.fill()

                // Tokyo and Sydney sit close enough to the edge that a label
                // hung on the right would fall off the canvas.
                var labelWidth = ctx.measureText(city.label).width
                var lx = (cx + Style.space(5) + labelWidth > width)
                  ? cx - Style.space(5) - labelWidth : cx + Style.space(5)
                ctx.fillStyle = lit ? root.foreground : fade(root.foreground, 0.5)
                ctx.fillText(city.label, lx, cy + Style.space(3))
              }

              var nowX = Math.round((root.nowSec - midnight) / 86400 * width)
              ctx.fillStyle = fade(root.foreground, 0.85)
              ctx.fillRect(nowX, 0, 1, height - Style.space(11))
            }
          }

          PanelSeparator { width: parent.width }

          PanelSectionHeader {
            text: "SESSIONS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.sessions

            delegate: Item {
              required property var modelData
              width: column.width
              implicitHeight: sessionCode.implicitHeight + Style.space(8)

              readonly property bool sessionOpen: root.isOpen(modelData)

              Text {
                id: sessionCode
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.code
                color: sessionOpen ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.left: sessionCode.right
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: sessionOpen ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: root.sessionState(modelData)
                color: sessionOpen ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator { width: parent.width }

          PanelSectionHeader {
            text: root.events.length === 0 ? "TODAY" : "TODAY · " + root.events.length
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.events.length === 0
            width: parent.width
            leftPadding: Style.space(10)
            topPadding: Style.space(6)
            bottomPadding: Style.space(6)
            text: root.loaded ? "Nothing scheduled for these currencies." : "Loading…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.events

            delegate: Item {
              required property var modelData
              width: column.width
              implicitHeight: eventTime.implicitHeight + Style.space(9)

              readonly property bool past: modelData.at <= root.nowSec
              readonly property bool isNext: root.nextEvent !== null
                && root.nextEvent.at === modelData.at && root.nextEvent.title === modelData.title

              Rectangle {
                id: severity
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(7)
                height: width
                radius: width / 2
                color: root.impactColor(modelData.impact)
                opacity: past ? 0.4 : 1.0
              }

              Text {
                id: eventTime
                anchors.left: severity.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.clock(modelData.at)
                color: past ? root.dim : (isNext ? Color.accent : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: eventCcy
                anchors.left: eventTime.right
                anchors.leftMargin: Style.space(9)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.ccy
                color: past ? root.dim : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: eventFigures
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: root.figures(modelData)
                color: past ? root.dim : Qt.darker(root.foreground, 1.25)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.left: eventCcy.right
                anchors.leftMargin: Style.space(8)
                anchors.right: eventFigures.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.title
                color: past ? root.dim : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            width: parent.width
            leftPadding: Style.space(10)
            topPadding: Style.space(6)
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width }

          Text {
            width: parent.width
            leftPadding: Style.space(10)
            topPadding: Style.space(2)
            text: "r refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
