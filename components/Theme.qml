
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: theme

  property color background: "#1e1e2e"
  property color surface: "#313244"
  property color surfaceHover: "#45475a"
  property color foreground: "#cdd6f4"
  property color muted: "#a6adc8"
  property color accent: "#89b4fa"
  property color danger: "#f38ba8"
  property color warning: "#f9e2af"
  property color success: "#a6e4a1"
  property color accentText: "#11111b"
  property color dangerText: "#11111b"
  property color border: "#313244"
  property color barFill: "#20000000"
  property color fallbackBackground: "#1a1a1a"
  property real dimOpacity: 0.10

  readonly property int radius: 0
  readonly property int radiusPopup: 9
  readonly property int radiusCard: 0
  readonly property int borderWidth: 2
  readonly property int barHeight: 38
  readonly property int barSpacing: 6

  // Nerd Font, used for glyph icons (speaker, mic, device types).
  readonly property string fontFamily: "FantasqueSansM Nerd Font"
  readonly property int fontXs: 10 
  readonly property int fontSm: 11 
  readonly property int fontBase: 12
  readonly property int fontMd: 14
  readonly property int fontLg: 16 
}
