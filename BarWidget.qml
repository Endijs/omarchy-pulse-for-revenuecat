import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.endijs.pulse-for-revenuecat"

  readonly property var dataService: root.bar && root.bar.shell
    ? root.bar.shell.serviceFor(root.moduleName)
    : null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dataService ? root.dataService.barText() : "RC · …"
    tooltipText: root.dataService ? root.dataService.tooltipText() : "Pulse for RevenueCat is loading"
    horizontalMargin: 8

    onPressed: function(mouseButton) {
      if (!root.bar || !root.bar.shell) return
      if (mouseButton === Qt.RightButton) {
        if (root.dataService) {
          var target = root.dataService.barScope === "selected" ? root.dataService.selectedProject : "all"
          root.dataService.refresh(target)
        }
      } else {
        root.bar.shell.toggle(root.moduleName, "{}")
      }
    }
  }
}
