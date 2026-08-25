import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string helperPath: Qt.resolvedUrl("revenuecat-control").toString().replace(/^file:\/\//, "")
  property bool loading: true
  property bool bootstrapComplete: false
  property bool demoMode: false
  property bool settingSaving: false
  property bool reloadQueued: false
  property bool reloadQueuedRefresh: false
  property bool bootstrapRefreshAfterLoad: true
  property string pendingSettingName: ""
  property string output: ""
  property string bootstrapOutput: ""
  property string fetchOutput: ""
  property string operationError: ""
  property var refreshAttempts: ({})
  property var activeRefreshTargets: []
  property var queuedRefreshTargets: []
  property string selectedProjectOverride: ""
  property string expandedMetricOverride: ""
  property string barMetricOverride: ""
  property string barScopeOverride: ""
  property int refreshMinutesOverride: 0
  property var snapshot: ({
    schemaVersion: 3,
    configured: false,
    ok: false,
    stale: false,
    demo: false,
    currency: "USD",
    fetchedAt: 0,
    settings: ({
      refreshMinutes: 60,
      selectedProject: "all",
      barMetric: "mrr",
      barScope: "all",
      expandedMetric: "revenue",
      revenueType: "revenue"
    }),
    projects: [],
    totals: ({
      id: "all",
      name: "All projects",
      iconUrl: "",
      ok: false,
      stale: false,
      fetchedAt: 0,
      metrics: ({}),
      charts: ({})
    }),
    stats: ({ totalProjects: 0, updatedProjects: 0 }),
    issues: []
  })

  readonly property bool configured: snapshot.configured === true
  readonly property string selectedProject: selectedProjectOverride !== ""
    ? selectedProjectOverride : String(snapshot.settings && snapshot.settings.selectedProject || "all")
  readonly property string expandedMetric: expandedMetricOverride !== ""
    ? expandedMetricOverride : String(snapshot.settings && snapshot.settings.expandedMetric || "revenue")
  readonly property string barMetric: barMetricOverride !== ""
    ? barMetricOverride : String(snapshot.settings && snapshot.settings.barMetric || "mrr")
  readonly property string barScope: barScopeOverride !== ""
    ? barScopeOverride : String(snapshot.settings && snapshot.settings.barScope || "all")
  readonly property int refreshMinutes: refreshMinutesOverride > 0
    ? refreshMinutesOverride : Number(snapshot.settings && snapshot.settings.refreshMinutes || 60)
  readonly property var currentView: viewFor(selectedProject)
  readonly property bool ready: !!currentView && currentView.ok === true
  readonly property bool stale: !!currentView && currentView.stale === true

  function projectById(id) {
    var projects = snapshot && snapshot.projects ? snapshot.projects : []
    for (var i = 0; i < projects.length; i++)
      if (String(projects[i].id) === String(id)) return projects[i]
    return null
  }

  function viewFor(id) {
    if (String(id || "all") === "all") return snapshot.totals || null
    return projectById(id) || snapshot.totals || null
  }

  function barView() {
    return barScope === "selected" ? currentView : (snapshot.totals || currentView)
  }

  function metricFor(view, id) {
    var metrics = view && view.metrics ? view.metrics : ({})
    return metrics[id] || null
  }

  function metric(id) {
    return metricFor(currentView, id)
  }

  function chartFor(view, id) {
    var charts = view && view.charts ? view.charts : ({})
    return charts[id] instanceof Array ? charts[id] : []
  }

  function chart(id) {
    return chartFor(currentView, id)
  }

  function projectOptions() {
    var options = [{ value: "all", label: "All projects" }]
    var projects = snapshot && snapshot.projects ? snapshot.projects : []
    for (var i = 0; i < projects.length; i++)
      options.push({ value: String(projects[i].id), label: safeDisplayText(projects[i].name || projects[i].id) })
    return options
  }

  function safeDisplayText(value) {
    // Imported Omarchy controls currently use Text.AutoText. Keep remote
    // metadata incapable of becoming markup even if a helper/cache is stale.
    return String(value || "").replace(/[<>&]/g, "")
  }

  function currentName() {
    if (selectedProject === "all") return "Pulse for RevenueCat"
    return safeDisplayText(currentView && currentView.name || selectedProject)
  }

  function currentSubtitle() {
    if (loading && !configured) return "Loading projects…"
    if (selectedProject === "all") {
      var stats = snapshot.stats || ({})
      return String(stats.updatedProjects || 0) + " of " + String(stats.totalProjects || 0) + " projects · " + String(snapshot.currency || "USD")
    }
    return "RevenueCat project · " + String(snapshot.currency || "USD")
  }

  function currentIconUrl() {
    // RevenueCat does not document a stable image-host allowlist. Avoid an
    // unbounded, metadata-selected Qt network fetch and render initials.
    return ""
  }

  function issueMessages() {
    var issues
    if (selectedProject === "all") issues = snapshot && snapshot.issues ? snapshot.issues : []
    else issues = currentView && currentView.issues ? currentView.issues : []
    var messages = []
    for (var i = 0; i < issues.length; i++) {
      var message = safeDisplayText(issues[i].message || "")
      if (message !== "" && messages.indexOf(message) < 0) messages.push(message)
    }
    if (operationError !== "" && messages.indexOf(operationError) < 0) messages.push(operationError)
    return messages
  }

  function currencyPrefix(code) {
    switch (String(code || "USD").toUpperCase()) {
      case "USD": return "$"
      case "EUR": return "€"
      case "GBP": return "£"
      case "JPY": return "¥"
      case "KRW": return "₩"
      case "CNY": return "¥"
      case "INR": return "₹"
      default: return String(code || "USD").toUpperCase() + " "
    }
  }

  function compactNumber(value, decimals) {
    var number = Number(value)
    if (!isFinite(number)) number = 0
    var absolute = Math.abs(number)
    if (absolute >= 1000000) return (number / 1000000).toFixed(absolute >= 10000000 ? 1 : 2).replace(/\.0+$/, "") + "M"
    if (absolute >= 1000) return (number / 1000).toFixed(absolute >= 100000 ? 0 : 1).replace(/\.0$/, "") + "K"
    return number.toFixed(decimals === undefined ? 0 : decimals)
  }

  function formatMoney(value, compact) {
    var code = snapshot && snapshot.currency ? snapshot.currency : "USD"
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    if (compact) return currencyPrefix(code) + compactNumber(amount, 0)
    var decimals = ["JPY", "KRW"].indexOf(String(code).toUpperCase()) >= 0 ? 0 : 2
    return currencyPrefix(code) + amount.toFixed(decimals)
  }

  function formatCount(value) {
    return compactNumber(value, 0)
  }

  function updatedText() {
    var fetchedAt = Number(currentView && currentView.fetchedAt || 0)
    if (!(fetchedAt > 0)) return "Never updated"
    var seconds = Math.max(0, Math.floor((Date.now() - fetchedAt) / 1000))
    if (seconds < 60) return "Updated just now"
    if (seconds < 3600) return "Updated " + Math.floor(seconds / 60) + "m ago"
    if (seconds < 86400) return "Updated " + Math.floor(seconds / 3600) + "h ago"
    return "Updated " + Math.floor(seconds / 86400) + "d ago"
  }

  function lastRefreshFor(project) {
    if (!project) return 0
    var attempted = Number(refreshAttempts[String(project.id)] || 0)
    var fetched = Number(project.fetchedAt || 0)
    var latest = Math.max(attempted, fetched)
    if (latest > 0 && latest < 100000000000) latest *= 1000
    return latest
  }

  function projectRefreshDue(project) {
    if (!project) return false
    var retryAfter = Number(project.retryAfterAt || 0)
    if (retryAfter > 0 && retryAfter < 100000000000) retryAfter *= 1000
    if (retryAfter > Date.now()) return false
    var lastRefresh = lastRefreshFor(project)
    if (!(lastRefresh > 0)) return true
    return Date.now() - lastRefresh >= refreshMinutes * 60 * 1000
  }

  function projectIdsForView(viewId) {
    var requested = String(viewId || "all")
    var projects = snapshot && snapshot.projects ? snapshot.projects : []
    if (requested !== "all") return projectById(requested) ? [requested] : []
    var ids = []
    for (var i = 0; i < projects.length; i++) {
      ids.push(String(projects[i].id))
    }
    return ids
  }

  function dueProjectIds(viewId) {
    if (!configured || demoMode) return []
    var ids = projectIdsForView(viewId)
    var due = []
    for (var i = 0; i < ids.length; i++) {
      if (projectRefreshDue(projectById(ids[i]))) due.push(ids[i])
    }
    return due
  }

  function refreshDue(viewId) {
    return dueProjectIds(viewId).length > 0
  }

  function refreshIfDue(viewId) {
    if (fetchProc.running) return
    startRefreshTargets(dueProjectIds(viewId))
  }

  function markRefreshAttempts(targets) {
    var next = ({})
    for (var key in refreshAttempts) next[key] = refreshAttempts[key]
    var now = Date.now()
    for (var i = 0; i < targets.length; i++) next[String(targets[i])] = now
    refreshAttempts = next
  }

  function barMetricLabel() {
    return barMetric === "revenue" ? "Revenue · 28d" : "MRR"
  }

  function barText() {
    var view = barView()
    if (loading && !(view && view.ok)) return "RC · …"
    if (!configured && !demoMode) return "RC · setup"
    if (!(view && view.ok)) return "RC · !"
    var item = metricFor(view, barMetric)
    return "RC " + (barMetric === "revenue" ? "28d" : "MRR") + " · " + formatMoney(item ? item.value : 0, true)
  }

  function tooltipText() {
    var view = barView()
    if (!configured && !demoMode) return "Pulse for RevenueCat · setup required"
    if (!(view && view.ok)) return "Pulse for RevenueCat · data unavailable"
    var item = metricFor(view, barMetric)
    var scope = barScope === "selected" && selectedProject !== "all" ? safeDisplayText(view.name || selectedProject) : "All projects"
    var suffix = view.stale ? " · cached" : ""
    return scope + " · " + barMetricLabel() + " · " + formatMoney(item ? item.value : 0, false) + suffix
  }

  function applyPayload(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      var valid = parsed && typeof parsed === "object" && !(parsed instanceof Array)
        && Number(parsed.schemaVersion) === 3
        && typeof parsed.configured === "boolean" && typeof parsed.ok === "boolean"
        && parsed.settings && typeof parsed.settings === "object" && !(parsed.settings instanceof Array)
        && parsed.projects instanceof Array
        && parsed.totals && typeof parsed.totals === "object" && !(parsed.totals instanceof Array)
        && parsed.stats && typeof parsed.stats === "object" && !(parsed.stats instanceof Array)
        && parsed.issues instanceof Array
      if (!valid) throw new Error("invalid snapshot shape")
      snapshot = parsed
      operationError = ""
      var saved = parsed.settings
      if (selectedProjectOverride !== "" && String(saved.selectedProject || "all") === selectedProjectOverride)
        selectedProjectOverride = ""
      if (expandedMetricOverride !== "" && String(saved.expandedMetric || "revenue") === expandedMetricOverride)
        expandedMetricOverride = ""
      if (barMetricOverride !== "" && String(saved.barMetric || "mrr") === barMetricOverride)
        barMetricOverride = ""
      if (barScopeOverride !== "" && String(saved.barScope || "all") === barScopeOverride)
        barScopeOverride = ""
      if (refreshMinutesOverride > 0 && Number(saved.refreshMinutes || 60) === refreshMinutesOverride)
        refreshMinutesOverride = 0
      return true
    } catch (error) {
      operationError = "RevenueCat returned an invalid response; the previous dashboard remains visible."
      return false
    }
  }

  function startRefreshTargets(targets) {
    if (!demoMode && (!targets || targets.length === 0)) return
    if (fetchProc.running) {
      queuedRefreshTargets = targets ? targets.slice() : []
      return
    }
    queuedRefreshTargets = []
    activeRefreshTargets = targets ? targets.slice() : []
    output = ""
    fetchOutput = ""
    loading = true
    fetchProc.command = demoMode ? [helperPath, "demo"] : [helperPath, "fetch"].concat(activeRefreshTargets)
    fetchProc.running = true
  }

  function refresh(viewId) {
    startRefreshTargets(demoMode ? [] : projectIdsForView(viewId || selectedProject))
  }

  function reloadCached(refreshAfterLoad) {
    var wantsRefresh = refreshAfterLoad === true
    if (fetchProc.running) {
      reloadQueued = true
      reloadQueuedRefresh = reloadQueuedRefresh || wantsRefresh
      return
    }
    if (bootstrapProc.running) {
      bootstrapRefreshAfterLoad = bootstrapRefreshAfterLoad || wantsRefresh
      return
    }
    bootstrapOutput = ""
    bootstrapRefreshAfterLoad = wantsRefresh
    bootstrapProc.command = [helperPath, "cached"]
    bootstrapProc.running = true
  }

  function clearSettingOverrides() {
    selectedProjectOverride = ""
    expandedMetricOverride = ""
    barMetricOverride = ""
    barScopeOverride = ""
    refreshMinutesOverride = 0
  }

  function leaveDemo(refreshAfterLoad) {
    demoMode = false
    clearSettingOverrides()
    reloadCached(refreshAfterLoad === true)
  }

  function setDemo(enabled) {
    if (enabled === true) {
      demoMode = true
      startRefreshTargets([])
    } else {
      leaveDemo(true)
    }
  }

  function saveSetting(name, value) {
    if (settingProc.running) return
    if (name === "selected-project") selectedProjectOverride = String(value)
    else if (name === "expanded-metric") expandedMetricOverride = String(value)
    else if (name === "bar-metric") barMetricOverride = String(value)
    else if (name === "bar-scope") barScopeOverride = String(value)
    else if (name === "refresh-minutes") refreshMinutesOverride = Number(value)
    if (demoMode) return
    pendingSettingName = name
    settingSaving = true
    settingProc.command = [helperPath, "settings", name, String(value)]
    settingProc.running = true
  }

  Process {
    id: bootstrapProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.bootstrapOutput = text
    }
    onExited: function(exitCode) {
      var shouldRefresh = root.bootstrapRefreshAfterLoad
      root.bootstrapRefreshAfterLoad = false
      root.bootstrapComplete = true
      if (!fetchProc.running) {
        root.loading = false
        var accepted = false
        if (exitCode === 0 && !root.demoMode) accepted = root.applyPayload(root.bootstrapOutput)
        else if (exitCode !== 0) root.operationError = "Could not load the saved RevenueCat dashboard; the previous dashboard remains visible."
        if (accepted && shouldRefresh) root.refreshIfDue("all")
      }
    }
  }

  Process {
    id: fetchProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fetchOutput = text
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) {
        root.output = root.fetchOutput
        root.applyPayload(root.fetchOutput)
      } else {
        root.operationError = "Could not refresh RevenueCat; the previous dashboard remains visible."
      }
      if (!root.demoMode) root.markRefreshAttempts(root.activeRefreshTargets)
      root.activeRefreshTargets = []
      if (root.reloadQueued) {
        var refreshAfterLoad = root.reloadQueuedRefresh
        root.reloadQueued = false
        root.reloadQueuedRefresh = false
        Qt.callLater(function() { root.reloadCached(refreshAfterLoad) })
      } else if (root.queuedRefreshTargets.length > 0) {
        var queued = root.queuedRefreshTargets.slice()
        root.queuedRefreshTargets = []
        Qt.callLater(function() { root.startRefreshTargets(queued) })
      }
    }
  }

  Process {
    id: settingProc
    command: []
    onExited: function(exitCode) {
      var savedName = root.pendingSettingName
      root.pendingSettingName = ""
      root.settingSaving = false
      if (exitCode === 0) {
        if (savedName === "selected-project") root.refreshIfDue(root.selectedProject)
      } else {
        if (savedName === "selected-project") root.selectedProjectOverride = ""
        else if (savedName === "expanded-metric") root.expandedMetricOverride = ""
        else if (savedName === "bar-metric") root.barMetricOverride = ""
        else if (savedName === "bar-scope") root.barScopeOverride = ""
        else if (savedName === "refresh-minutes") root.refreshMinutesOverride = 0
      }
    }
  }

  Timer {
    interval: Math.min(60000, Math.max(5000, root.refreshMinutes * 60 * 1000))
    repeat: true
    running: root.bootstrapComplete
    onTriggered: root.refreshIfDue("all")
  }

  Component.onCompleted: {
    bootstrapOutput = ""
    bootstrapRefreshAfterLoad = true
    bootstrapProc.command = [helperPath, "cached"]
    bootstrapProc.running = true
  }
}
