import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {

  id: root
  
  Variants {
    model: Quickshell.screens

    Pill {
      required property var modelData
      screen: modelData
    }
  }
} 
