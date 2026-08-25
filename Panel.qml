import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool closingFromHost: false

  readonly property color background: Color.background
  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color cardColor: Style.selectedFillFor(foreground, accent)
  readonly property string fontFamily: Style.font.family

  readonly property var cards: [
    { id: "mrr", label: "MONTHLY RECURRING", shortLabel: "MRR", money: true },
    { id: "revenue", label: "REVENUE · 28 DAYS", shortLabel: "Revenue · 28 days", money: true },
    { id: "active_subscriptions", label: "ACTIVE SUBSCRIPTIONS", shortLabel: "Active subscriptions", money: false },
    { id: "active_trials", label: "ACTIVE TRIALS", shortLabel: "Active trials", money: false },
    { id: "new_customers", label: "NEW CUSTOMERS · 28D", shortLabel: "New customers · 28 days", money: false },
    { id: "active_users", label: "ACTIVE USERS · 28D", shortLabel: "Active users · 28 days", money: false }
  ]

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) }
    catch (error) { payload = ({}) }
    if (service && payload.demo === true) service.setDemo(true)
    else if (service && service.configured && !service.demoMode) service.refreshIfDue(service.selectedProject)
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("io.github.endijs.pulse-for-revenuecat")
    else window.visible = false
  }

  function metric(id) {
    return service ? service.metric(id) : null
  }

  function cardValue(card) {
    var item = metric(card.id)
    var value = item ? item.value : 0
    return card.money && service ? service.formatMoney(value, false) : (service ? service.formatCount(value) : "0")
  }

  function cardById(id) {
    for (var i = 0; i < cards.length; i++)
      if (cards[i].id === id) return cards[i]
    return cards[1]
  }

  function drawSeries(canvas, points, showGrid) {
    var ctx = canvas.getContext("2d")
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    if (!points || points.length < 2) return

    var values = []
    for (var i = 0; i < points.length; i++) values.push(Number(points[i].value || 0))
    var minimum = values[0]
    var maximum = values[0]
    for (var j = 1; j < values.length; j++) {
      minimum = Math.min(minimum, values[j])
      maximum = Math.max(maximum, values[j])
    }
    var span = Math.max(1, maximum - minimum)
    var pad = showGrid ? 5 : 2

    if (showGrid) {
      ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      ctx.lineWidth = 1
      for (var g = 1; g < 4; g++) {
        var gy = Math.round(canvas.height * g / 4) + 0.5
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(canvas.width, gy); ctx.stroke()
      }
    }

    ctx.strokeStyle = root.accent
    ctx.lineWidth = showGrid ? 2.5 : 1.5
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.beginPath()
    for (var p = 0; p < values.length; p++) {
      var x = pad + (canvas.width - pad * 2) * p / (values.length - 1)
      var y = pad + (canvas.height - pad * 2) * (1 - (values[p] - minimum) / span)
      if (p === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    }
    ctx.stroke()
  }

  function startManage() {
    if (!service || manageProc.running) return
    manageProc.command = ["xdg-terminal-exec", service.helperPath, "manage-hold"]
    manageProc.running = true
  }

  function startSettings() {
    if (!service || settingsProc.running) return
    settingsProc.command = ["xdg-terminal-exec", service.helperPath, "settings-manage-hold"]
    settingsProc.running = true
  }

  Process {
    id: manageProc
    command: []
    onExited: {
      if (!root.service) return
      root.service.leaveDemo(true)
    }
  }

  Process {
    id: settingsProc
    command: []
    onExited: {
      if (!root.service) return
      root.service.leaveDemo(false)
    }
  }

  Connections {
    target: root.service
    function onSnapshotChanged() { expandedChart.requestPaint() }
    function onExpandedMetricChanged() { expandedChart.requestPaint() }
  }

  FloatingWindow {
    id: window
    title: "Pulse for RevenueCat"
    color: root.background
    implicitWidth: 820
    implicitHeight: 760
    minimumSize: Qt.size(650, 580)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("io.github.endijs.pulse-for-revenuecat")
    }

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.requestClose()
          event.accepted = true
        } else if (event.key === Qt.Key_R && root.service) {
          root.service.refresh(root.service.selectedProject)
          event.accepted = true
        }
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: Style.space(22)
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: scroll.availableWidth
          spacing: Style.space(18)

          Row {
            width: parent.width
            spacing: Style.space(12)

            Rectangle {
              width: Style.space(48)
              height: width
              radius: width / 2
              color: root.accent
              clip: true

              Text {
                anchors.centerIn: parent
                text: root.service && root.service.selectedProject !== "all"
                  ? String(root.service.currentName()).charAt(0).toUpperCase() : "R"
                textFormat: Text.PlainText
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }

            Column {
              width: parent.width - Style.space(48) - manageButton.width - settingsButton.width - parent.spacing * 3
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.service ? root.service.currentName() : "Pulse for RevenueCat"
                textFormat: Text.PlainText
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Text {
                width: parent.width
                text: root.service ? root.service.currentSubtitle() : "Starting…"
                textFormat: Text.PlainText
                color: root.dim
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Button {
              id: manageButton
              anchors.verticalCenter: parent.verticalCenter
              text: manageProc.running ? "Open…" : "Projects"
              enabled: !manageProc.running && !settingsProc.running && !!root.service
              bordered: true
              foreground: root.foreground
              accent: root.accent
              onClicked: root.startManage()
            }

            Button {
              id: settingsButton
              anchors.verticalCenter: parent.verticalCenter
              text: settingsProc.running ? "Open…" : "Settings"
              enabled: !settingsProc.running && !manageProc.running && !!root.service
              bordered: true
              foreground: root.foreground
              accent: root.accent
              onClicked: root.startSettings()
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            visible: !!root.service && !root.service.loading && !root.service.configured && !root.service.demoMode
            width: parent.width
            spacing: Style.space(14)

            Text {
              text: "Connect your RevenueCat projects"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Add one read-only v2 key per project. Keys stay in your desktop keyring. Pulse combines enabled projects into one overview and lets you inspect each project separately."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Row {
              spacing: Style.space(10)
              Button {
                text: manageProc.running ? "Manager open…" : "Add projects"
                enabled: !manageProc.running && !settingsProc.running && !!root.service
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.startManage()
              }
              Button {
                text: "Preview demo"
                enabled: !!root.service
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.service.setDemo(true)
              }
            }
          }

          Column {
            visible: !root.service || (root.service.loading && !root.service.configured && !root.service.demoMode)
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Loading your RevenueCat dashboard…"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: "Restoring saved data while the latest metrics load."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Column {
            visible: !!root.service && (root.service.configured || root.service.demoMode)
            width: parent.width
            spacing: Style.space(10)

            Dropdown {
              width: Math.min(Style.space(340), parent.width)
              label: "VIEW"
              value: root.service ? root.service.selectedProject : "all"
              options: root.service ? root.service.projectOptions() : []
              enabled: !!root.service && !root.service.settingSaving
              foreground: root.foreground
              background: root.background
              accent: root.accent
              onChanged: function(value) { if (root.service) root.service.saveSetting("selected-project", value) }
            }

            Text {
              visible: root.service && root.service.selectedProject === "all" && root.service.ready
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Totals use a shared currency. Customer and user counts are summed across projects and may include the same person more than once."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            visible: root.service && root.service.issueMessages().length > 0
            width: parent.width
            implicitHeight: permissionMessage.implicitHeight + Style.space(24)
            radius: Style.cornerRadius
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.42)

            Text {
              id: permissionMessage
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              wrapMode: Text.WordWrap
              text: root.service ? root.service.issueMessages().join("\n") : ""
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            visible: !!root.service && (root.service.configured || root.service.demoMode) && !root.service.ready
            width: parent.width
            spacing: Style.space(12)

            Text {
              text: root.service && root.service.loading ? "Loading RevenueCat…" : "No metrics are available"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              spacing: Style.space(10)
              Button {
                text: "Retry"
                enabled: !!root.service && !root.service.loading
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.service.refresh(root.service.selectedProject)
              }
              Button {
                text: "Manage projects"
                enabled: !manageProc.running
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.startManage()
              }
              Button {
                text: "Preview demo"
                enabled: !!root.service
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.service.setDemo(true)
              }
            }
          }

          Column {
            visible: !!root.service && root.service.ready
            width: parent.width
            spacing: Style.space(18)

            Grid {
              id: metricGrid
              width: parent.width
              columns: width >= Style.space(680) ? 3 : 2
              spacing: Style.space(10)

              Repeater {
                model: root.cards

                Rectangle {
                  required property var modelData
                  property var points: root.service ? root.service.chart(modelData.id) : []
                  readonly property bool selected: root.service && root.service.expandedMetric === modelData.id
                  width: (metricGrid.width - metricGrid.spacing * (metricGrid.columns - 1)) / metricGrid.columns
                  height: Style.space(124)
                  radius: Style.cornerRadius
                  color: root.cardColor
                  border.width: selected ? 1 : 0
                  border.color: root.accent
                  clip: true
                  onPointsChanged: sparkline.requestPaint()

                  Canvas {
                    id: sparkline
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.space(10)
                    height: Style.space(42)
                    opacity: parent.selected ? 0.95 : 0.58
                    onPaint: root.drawSeries(sparkline, parent.points, false)
                    Component.onCompleted: requestPaint()
                  }

                  Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(14)
                    spacing: Style.space(5)

                    Text {
                      width: parent.width
                      text: modelData.label
                      elide: Text.ElideRight
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      width: parent.width
                      text: root.cardValue(modelData)
                      elide: Text.ElideRight
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.display
                      font.bold: true
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.service) root.service.saveSetting("expanded-metric", modelData.id)
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(220)
              radius: Style.cornerRadius
              color: root.cardColor

              Item {
                anchors.fill: parent
                anchors.margins: Style.space(14)

                Row {
                  id: chartHeader
                  width: parent.width

                  Text {
                    width: parent.width / 2
                    text: root.cardById(root.service ? root.service.expandedMetric : "revenue").shortLabel.toUpperCase()
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    width: parent.width / 2
                    horizontalAlignment: Text.AlignRight
                    text: "Last 28 days"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Canvas {
                  id: expandedChart
                  property var points: root.service ? root.service.chart(root.service.expandedMetric) : []
                  anchors.top: chartHeader.bottom
                  anchors.topMargin: Style.space(8)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  onPointsChanged: requestPaint()
                  onPaint: root.drawSeries(expandedChart, points, true)
                  Component.onCompleted: requestPaint()
                }

                Text {
                  visible: expandedChart.points.length < 2
                  anchors.centerIn: parent
                  text: "Chart unavailable"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                width: parent.width - refreshButton.width - liveButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: (root.service.stale ? "Cached · " : "") + root.service.updatedText()
                  + " · refreshes every " + (root.service.refreshMinutes === 60 ? "hour" : String(root.service.refreshMinutes) + "m")
                color: root.service.stale ? root.urgent : root.dim
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Button {
                id: liveButton
                visible: root.service && root.service.demoMode
                text: "Use live data"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.service.setDemo(false)
              }

              Button {
                id: refreshButton
                text: root.service && root.service.loading ? "Refreshing…" : "Refresh"
                enabled: root.service && !root.service.loading
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.service.refresh(root.service.selectedProject)
              }
            }
          }
        }
      }
    }
  }
}
