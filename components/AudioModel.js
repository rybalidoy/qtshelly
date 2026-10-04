// Pure helpers for the sound center. Ported from omarchy's
// shell/plugins/panels/audio/Model.js, trimmed to the parts that do not
// depend on omarchy-specific plugins or helper binaries.
//
// Kept as plain functions (no Quickshell types) so the classification
// rules stay unit-testable; see test/shell.d/audio-test.sh upstream.

// ── Node classification ─────────────────────────────────────────

// Quickshell exposes PwNodeType as a flag set, but String() on it yields the
// raw integer rather than the enum key, so it has to be tested numerically.
// The bits below were read off a live graph by matching each value against
// the node's media.class:
//
//   Audio/Source          -> 9  = Audio|Source
//   Audio/Sink            -> 17 = Audio|Sink
//   Stream/Input/Audio    -> 13 = Stream|Source|Audio
//   Stream/Output/Audio   -> 21 = Stream|Sink|Audio
//   Video/Source          -> 10 = Video|Source
var PW_AUDIO = 1
var PW_VIDEO = 2
var PW_STREAM = 4
var PW_SOURCE = 8
var PW_SINK = 16

function nodeTypeFlags(node) {
  if (!node) return 0
  var t = Number(node.type)
  return isNaN(t) ? 0 : t
}

// Identify true playback streams without reading node.properties:
// PwNode.properties is empty until the node is bound, and reading it while
// capture streams are appearing can destabilise Quickshell's Pipewire
// service. Stream/Output/Audio nodes publish isSink: true; capture streams
// publish as Stream/Input/Audio and do not.
function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true
  var t = nodeTypeFlags(node)
  return (t & PW_STREAM) !== 0 && (t & PW_SINK) !== 0
}

function isAudioSource(node) {
  if (!node) return false
  var t = nodeTypeFlags(node)
  if (t !== 0) {
    // Audio/Sink also carries the Audio bit, so require Source and the
    // absence of Sink, and keep camera inputs (Video/Source) out.
    return (t & PW_AUDIO) !== 0
      && (t & PW_SOURCE) !== 0
      && (t & PW_SINK) === 0
      && (t & PW_VIDEO) === 0
  }
  return !!node.audio
}

// Quickshell does not recognise the "/Virtual" media-class suffix, so DSP
// endpoints such as EasyEffects' easyeffects_source come back as Untracked,
// with no audio interface and no readable properties -- there is nothing
// authoritative left to inspect. Fall back to PipeWire's naming convention
// for virtual endpoints, which is what these nodes use.
//
// Without this the EasyEffects input only appears in the panel while
// something is recording into it, because that is the only time WirePlumber
// binds it and Quickshell can finally classify it.
function isUnclassifiedVirtualSource(node) {
  if (!node || node.isSink || node.isStream) return false
  if (nodeTypeFlags(node) !== 0) return false
  if (node.audio) return true
  return /(^|[_\-.])source$/.test(String(node.name || ""))
}

function listSnapshot(list) {
  return list && list.slice ? list.slice() : []
}

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

// ── Labels ──────────────────────────────────────────────────────

// Strip the ALSA/udev noise that shows up in PipeWire descriptions so
// device rows read as "Built-in Audio Analog Stereo", not
// "alsa_output.pci-0000_01_00.1.analog-stereo".
function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Output$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\bMicrophones\b/g, "Microphone")
  return label
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function nodeLabel(node) {
  if (!node) return "Unknown"
  var p = nodeProps(node)
  var nickname = friendlyDeviceLabel(node.nickname || node.nick || p["node.nick"] || p["device.profile.description"] || "")
  if (nickname) return nickname
  return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
}

// Playful mood name for a volume level. Mirrors omarchy's ladder; the
// bands are wide enough that a 5% nudge does not rename the room.
function outputVolumeName(volume, muted) {
  if (muted) return "Muted"
  var p = Math.round(volume * 100)
  if (p === 0) return "Silenced"
  if (p >= 100) return "Concert hall"
  if (p >= 85) return "Party mode"
  if (p >= 70) return "Cranked up"
  if (p >= 50) return "Steady groove"
  if (p >= 30) return "Easy listening"
  if (p >= 15) return "Murmur"
  return "Whisper"
}

// ── Glyphs (Nerd Font) ──────────────────────────────────────────

function isHeadphones(node) {
  if (!node) return false
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || "",
    p["node.description"] || "",
    p["node.nick"] || ""
  ].join(" ")).toLowerCase()
  return blob.indexOf("headphone") !== -1
    || blob.indexOf("headset") !== -1
    || blob.indexOf("earbud") !== -1
    || blob.indexOf("earphone") !== -1
    || blob.indexOf("airpod") !== -1
}

function sinkGlyph(node) {
  if (!node) return "󰓃"
  if (isHeadphones(node)) return "󰋋"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || "",
    p["device.product.name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

function sourceGlyph(node) {
  if (!node) return "󰍬"
  var p = nodeProps(node)
  var blob = String([
    node.name, node.description, node.nickname,
    p["device.icon-name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("headset") !== -1) return "󰋋"
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
  return "󰍬"
}

// Speaker glyph for a volume level. The Material Design speaker icons
// render visually smaller than the rest of the set in Nerd Fonts.
function outputIcon(volume, muted) {
  if (muted) return "󰕾"
  var v = volume === undefined ? 0 : volume
  if (v >= 0.67) return "󰕽"
  if (v >= 0.34) return "󰖀"
  if (v > 0) return "󰔀"
  return "󰕾"
}

function inputIcon(muted) {
  return muted ? "󰍭" : "󰍬"
}

// ── Stream naming ───────────────────────────────────────────────

function friendlyStreamLabel(label) {
  label = String(label || "").trim()
  if (!label) return ""

  var known = {
    "spotify": "Spotify"
  }
  var normalized = label.toLowerCase()
  return known[normalized] || label
}

function streamLabelKey(label) {
  return String(label || "").trim().toLowerCase()
}

// PipeWire reports some clients under the placeholder "audio-src"
// instead of a real application name.
function streamLabelIsGeneric(label) {
  return streamLabelKey(label) === "audio-src"
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function mprisPlayerLabel(player) {
  if (!player) return ""
  return friendlyStreamLabel(player.identity || player.desktopEntry || "")
}

function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
  var streamKey = streamLabelKey(friendlyStreamLabel(streamLabel))
  var playerKey = streamLabelKey(playerLabel)
  if (!streamKey || !playerKey) return false
  return streamKey === playerKey
    || streamKey.indexOf(playerKey) !== -1
    || playerKey.indexOf(streamKey) !== -1
}

function isCandidatePlayer(player) {
  if (!player) return false
  if (!player.isPlaying && !player.canPlay) return false
  return !!mprisPlayerLabel(player)
}

// Prefer the MPRIS display name when a stream's own label already
// identifies one player (Chromium, Steam, ...).
function matchingMprisStreamLabel(label, players) {
  if (streamLabelIsGeneric(label)) return ""
  var values = Array.isArray(players) ? players : []
  for (var i = 0; i < values.length; i++) {
    if (!isCandidatePlayer(values[i])) continue
    var playerLabel = mprisPlayerLabel(values[i])
    if (streamRepresentsMprisPlayer(label, playerLabel)) return playerLabel
  }
  return ""
}

// For a generic stream, fall back to the one candidate player that no
// other stream already accounts for (e.g. Spotify).
function unmatchedMprisStreamLabel(label, players, streams) {
  if (!streamLabelIsGeneric(label)) return ""

  var values = Array.isArray(players) ? players : []
  var streamValues = Array.isArray(streams) ? streams : []
  var candidates = []

  for (var i = 0; i < values.length; i++) {
    if (!isCandidatePlayer(values[i])) continue
    var playerLabel = mprisPlayerLabel(values[i])

    var represented = false
    for (var j = 0; j < streamValues.length; j++) {
      var streamLabel = rawStreamLabel(streamValues[j])
      if (!streamLabelIsGeneric(streamLabel) && streamRepresentsMprisPlayer(streamLabel, playerLabel)) {
        represented = true
        break
      }
    }
    if (!represented) candidates.push(playerLabel)
  }

  return candidates.length === 1 ? candidates[0] : ""
}

function streamLabel(node, players, streams) {
  if (!node) return "Stream"
  var label = rawStreamLabel(node)
  return friendlyStreamLabel(matchingMprisStreamLabel(label, players)
    || unmatchedMprisStreamLabel(label, players, streams)
    || label) || "Stream"
}

// ── pactl interop (per-app output routing) ──────────────────────
//
// Quickshell's Pipewire service exposes PwNodeIface.properties as
// read-only, so a stream's `target.object` cannot be written from QML.
// `pactl move-sink-input` is the supported way to move a live stream, which
// means routing state has to come from pactl while volume and mute stay on
// the native Pipewire path.
//
// The catch is that the two ID spaces are unrelated: on this machine the
// vesktop streams are PipeWire nodes 171/179 but pactl sink-inputs 1726/1773.
// Only the name is shared, and two streams can share a name, so the pairing
// has to fall back on ordering -- both sides number their entries in creation
// order, and PipeWire node ids increase monotonically.

function routeKey(name) {
  return String(name || "").trim().toLowerCase()
}

// "pactl list sinks short" -> one tab/space separated row per sink:
//   1579<TAB>alsa_output.usb-Synaptics_...<TAB>PipeWire<TAB>...
function parseSinksShort(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 2) continue
    var idx = parseInt(parts[0], 10)
    if (isNaN(idx)) continue
    out.push({ "index": idx, "name": parts[1] })
  }
  return out
}

// "pactl list sink-inputs" -> blocks that each start with a header line,
// "Sink Input #1726", followed by indented key/value lines.
function parseSinkInputs(text) {
  var out = []
  var blocks = String(text || "").split(/^Sink Input #/m)
  // blocks[0] is the preamble before the first entry.
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i]
    var idx = parseInt(block.split(/\s/)[0], 10)
    if (isNaN(idx)) continue

    var sinkIndex = -1
    var m = block.match(/^[ \t]*Sink:[ \t]*(\d+)[ \t]*$/m)
    if (m) sinkIndex = parseInt(m[1], 10)

    var nodeName = ""
    m = block.match(/node\.name[ \t]*=[ \t]*"([^"]*)"/)
    if (m) nodeName = m[1]

    var appName = ""
    m = block.match(/application\.name[ \t]*=[ \t]*"([^"]*)"/)
    if (m) appName = m[1]

    out.push({
      "index": idx,
      "name": nodeName || appName,
      "app": appName,
      "sinkIndex": sinkIndex
    })
  }
  return out
}

// Pair our PipeWire stream nodes with pactl sink-inputs, keyed by node id so
// the caller can look a route up in any order. Each pactl entry is claimed at
// most once, which is what keeps two identically named streams apart.
function streamRouteMap(streams, sinkInputs) {
  var inputs = (Array.isArray(sinkInputs) ? sinkInputs : []).slice()
  inputs.sort(function (a, b) { return a.index - b.index })

  var pools = {}
  for (var i = 0; i < inputs.length; i++) {
    var key = routeKey(inputs[i].name)
    if (!pools[key]) pools[key] = []
    pools[key].push({ "entry": inputs[i], "used": false })
  }

  var nodes = (Array.isArray(streams) ? streams : []).slice()
  nodes.sort(function (a, b) {
    return (Number(a && a.id) || 0) - (Number(b && b.id) || 0)
  })

  var map = {}
  for (var j = 0; j < nodes.length; j++) {
    var node = nodes[j]
    if (!node) continue
    var pool = pools[routeKey(node.name)]
    var slot = null
    if (pool) {
      for (var k = 0; k < pool.length; k++) {
        if (!pool[k].used) {
          pool[k].used = true
          slot = pool[k].entry
          break
        }
      }
    }
    // A stream with no pactl counterpart is still listed; it just has no
    // routing handle, and the UI says so rather than offering a dead menu.
    map[node.id] = slot
      ? { "pulseIndex": slot.index, "sinkIndex": slot.sinkIndex }
      : null
  }
  return map
}

// Join pactl's sink indices (the handle move-sink-input needs) with our
// PipeWire sink nodes (which carry the readable nickname), matched on name --
// PipeWire's node.name for an ALSA sink is byte-identical to pactl's sink
// name, so this pairing is exact.
function joinSinks(sinksShort, sinkNodes) {
  var byName = {}
  var nodes = Array.isArray(sinkNodes) ? sinkNodes : []
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i]) byName[String(nodes[i].name || "")] = nodes[i]
  }

  var out = []
  var list = Array.isArray(sinksShort) ? sinksShort : []
  for (var j = 0; j < list.length; j++) {
    out.push({
      "index": list[j].index,
      "pulseName": list[j].name,
      "node": byName[list[j].name] || null
    })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    PW_AUDIO: PW_AUDIO,
    PW_VIDEO: PW_VIDEO,
    PW_STREAM: PW_STREAM,
    PW_SOURCE: PW_SOURCE,
    PW_SINK: PW_SINK,
    nodeTypeFlags: nodeTypeFlags,
    isPlaybackStream: isPlaybackStream,
    isAudioSource: isAudioSource,
    isUnclassifiedVirtualSource: isUnclassifiedVirtualSource,
    listSnapshot: listSnapshot,
    clamp: clamp,
    friendlyDeviceLabel: friendlyDeviceLabel,
    nodeProps: nodeProps,
    nodeLabel: nodeLabel,
    outputVolumeName: outputVolumeName,
    isHeadphones: isHeadphones,
    sinkGlyph: sinkGlyph,
    sourceGlyph: sourceGlyph,
    outputIcon: outputIcon,
    inputIcon: inputIcon,
    friendlyStreamLabel: friendlyStreamLabel,
    streamLabelKey: streamLabelKey,
    streamLabelIsGeneric: streamLabelIsGeneric,
    rawStreamLabel: rawStreamLabel,
    mprisPlayerLabel: mprisPlayerLabel,
    streamRepresentsMprisPlayer: streamRepresentsMprisPlayer,
    matchingMprisStreamLabel: matchingMprisStreamLabel,
    unmatchedMprisStreamLabel: unmatchedMprisStreamLabel,
    streamLabel: streamLabel,
    routeKey: routeKey,
    parseSinksShort: parseSinksShort,
    parseSinkInputs: parseSinkInputs,
    streamRouteMap: streamRouteMap,
    joinSinks: joinSinks
  }
}
