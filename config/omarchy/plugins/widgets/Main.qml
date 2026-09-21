import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root
  // A light, high-contrast palette with soft rounded edges approximates the
  // current Apple Liquid Glass look while preserving legibility on wallpaper.
  readonly property string uiFont: "Noto Sans"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/widgets"
  readonly property color glassText: "#F7FBFF"
  readonly property color glassMutedText: "#D5E0EB"
  readonly property color glassFill: "#4024334A"
  readonly property color glassBorder: "#8AFFFFFF"
  property string weatherTemp: ""
  property string weatherDesc: ""
  property string weatherMeta: ""
  property string weatherWind: ""
  property string weatherSymbol: ""
  property string cpuText: "CPU  —"
  property string gpuText: "GPU  —"
  property string tempText: "CPU temp  —"
  property string netText: "Network  —"
  property real cpuLoad: -1
  property real gpuLoad: -1
  property real netLoad: -1
  property string artist: "Nothing is playing"
  property string title: "Start a player to see the current track"
  property string album: ""
  property string playerStatus: "Stopped"
  property string elapsed: "0:00"
  property string duration: "0:00"
  property real progress: 0
  property real positionSeconds: 0
  property real durationSeconds: 0
  property bool seeking: false
  property var previousCpu: null
  property var previousNet: null
  property double previousNetAt: 0
  function formatTime(value) { var seconds=Math.max(0,Math.floor(Number(value)||0));return Math.floor(seconds/60)+":"+("0"+(seconds%60)).slice(-2) }
  function playerCommand(command) {
    control.command=["sh","-c","if command -v playerctl >/dev/null;then playerctl --player=brave.instance76525 "+command+" 2>/dev/null || playerctl "+command+" 2>/dev/null;elif [ -S \"$XDG_RUNTIME_DIR/mpd.sock\" ];then printf '"+command+"\\n'|socat - UNIX-CONNECT:\"$XDG_RUNTIME_DIR/mpd.sock\";fi"]
    control.running=true
    playerPoll.restart()
  }
  function togglePlayback() { playerCommand(playerStatus === "Playing" ? "pause" : "play") }
  function seekTo(ratio) {
    if (durationSeconds <= 0) return
    ratio = Math.max(0, Math.min(1, ratio))
    positionSeconds = durationSeconds * ratio
    progress = ratio
    elapsed = formatTime(positionSeconds)
    playerCommand("position " + positionSeconds.toFixed(3))
  }
  function weatherLabel(code) {
    code=Number(code); if(code===0)return "ясно"; if(code===1)return "преимущественно ясно"; if(code===2)return "переменная облачность"; if(code===3)return "облачно"; if(code===45||code===48)return "туман"; if(code===56||code===57||code===66||code===67)return "дождь со снегом"; if(code<=55)return "морось"; if(code<=65)return "дождь"; if(code<=77)return "снег"; if(code<=82)return "ливень"; if(code<=86)return "снегопад"; return "гроза"
  }
  function windDirection(degrees) { var d=["С","СВ","В","ЮВ","Ю","ЮЗ","З","СЗ"];return d[Math.round((((Number(degrees)%360)+360)%360)/45)%8] }
  function weatherIcon(code, isDay) { code=Number(code);if(code===0)return Number(isDay)===1?"☀":"☾";if(code===1||code===2)return "⛅";if(code===3)return "☁";if(code===45||code===48)return "≋";if(code===56||code===57||code===66||code===67)return "🌨";if(code<=55)return "☂";if(code<=65)return "☔";if(code<=77)return "❄";if(code<=82)return "☔";if(code<=86)return "❄";return "ϟ" }
  function applyWeather(line) { var p=String(line).trim().split(/\s+/); if(p.length>=9&&isFinite(Number(p[0]))){var temp=Math.round(Number(p[0]));weatherTemp=(temp>0?"+":"")+temp+"°C";weatherDesc=weatherLabel(p[6]);weatherMeta="Ощущается "+Math.round(Number(p[1]))+"°C   ·   Влажность "+Math.round(Number(p[2]))+"%   ·   Осадки "+Number(p[3]).toFixed(1)+" мм";weatherWind="Ветер "+Number(p[4]).toFixed(1)+" м/с  "+windDirection(p[5]);weatherSymbol=weatherIcon(p[6],p[7])} }
  function applyCpu(line) { var f=String(line).trim().split(/\s+/);if(f.length<6||f[0]!=="cpu")return;var total=0;for(var i=1;i<f.length;i++)total+=Math.max(0,Number(f[i])||0);var now={total:total,idle:(Number(f[4])||0)+(Number(f[5])||0)};if(previousCpu){var dt=now.total-previousCpu.total;var di=now.idle-previousCpu.idle;if(dt>0){cpuLoad=Math.max(0,Math.min(1,(dt-di)/dt));cpuText="CPU  "+Math.round(cpuLoad*100)+"%"}}previousCpu=now }
  function applyGpu(line) { var p=String(line).trim().split("|");if(p.length>=2&&isFinite(Number(p[0]))&&isFinite(Number(p[1]))){gpuLoad=Math.max(0,Math.min(1,Number(p[0])/100));gpuText="GPU  "+Math.round(Number(p[0]))+"%  ·  "+Math.round(Number(p[1]))+"°C"}else gpuText="GPU unavailable" }
  function applyTemp(line) { var p=String(line).trim().split("|");var n=Number(p.length>1?p[1]:p[0]);tempText=isFinite(n)?(p.length>1?p[0]:"System")+"  "+n.toFixed(0)+"°C":"Temperature unavailable" }
  function formatRate(value) { var rate=Math.max(0,Number(value)||0);return rate<1?rate.toFixed(2):rate.toFixed(rate<10?2:1) }
  function applyNet(line) { var p=String(line).trim().split(/\s+/);if(p.length<3)return;var iface=p[0],now=Date.now(),rx=Number(p[1]),tx=Number(p[2]),speed=Number(p[3])||0;if(!isFinite(rx)||!isFinite(tx))return;if(!previousNet||previousNet.iface!==iface){previousNet={iface:iface,rx:rx,tx:tx};previousNetAt=now;netLoad=-1;return}if(now>previousNetAt){var sec=(now-previousNetAt)/1000,down=Math.max(0,(rx-previousNet.rx)*8/1e6/sec),up=Math.max(0,(tx-previousNet.tx)*8/1e6/sec);netText="↓ "+formatRate(down)+"  ↑ "+formatRate(up)+" Mbit/s";var capacity=speed>0?speed:100;netLoad=Math.max(0,Math.min(1,Math.max(down,up)/capacity))}previousNet={iface:iface,rx:rx,tx:tx};previousNetAt=now }
  function applyPlayer(line) {
    var p=String(line).trim().split("§")
    if(p.length<7||p[0]===""){playerStatus="Stopped";artist="Nothing is playing";title="Start a player to see the current track";album="";elapsed="0:00";duration="0:00";positionSeconds=0;durationSeconds=0;progress=0;return}
    playerStatus=p[0];artist=p[1]||"Unknown artist";title=p[2]||"Unknown title";album=p[3]
    if (!seeking) { positionSeconds=Math.max(0,Number(p[4])||0); durationSeconds=Math.max(0,Number(p[5])||0); progress=durationSeconds>0?Math.max(0,Math.min(1,positionSeconds/durationSeconds)):0; elapsed=formatTime(positionSeconds); duration=formatTime(durationSeconds) }
  }

  Process{id:weather;command:[Quickshell.env("HOME") + "/.local/share/omarchy/weather/weather-backend","--line"];running:true;stdout:SplitParser{onRead:function(l){root.applyWeather(l)}}}
  Process{id:cpu;command:["sh",root.pluginDir+"/metrics-backend","cpu"];running:true;stdout:SplitParser{onRead:function(l){root.applyCpu(l)}}}
  Process{id:gpu;command:["sh",root.pluginDir+"/metrics-backend","gpu"];running:true;stdout:SplitParser{onRead:function(l){root.applyGpu(l)}}}
  Process{id:temp;command:["sh",root.pluginDir+"/metrics-backend","temp"];running:true;stdout:SplitParser{onRead:function(l){root.applyTemp(l)}}}
  Process{id:net;command:["sh",root.pluginDir+"/metrics-backend","net"];running:true;stdout:SplitParser{onRead:function(l){root.applyNet(l)}}}
  Process{id:player;command:["sh","-c","if command -v playerctl >/dev/null;then playerctl --player=brave.instance76525 metadata --format '{{status}}§{{artist}}§{{title}}§{{album}}§{{position}}§{{mpris:length}}' 2>/dev/null || playerctl metadata --format '{{status}}§{{artist}}§{{title}}§{{album}}§{{position}}§{{mpris:length}}' 2>/dev/null;fi|awk -F'§' '{if($5>1000000)$5=$5/1000000;if($6>1000000)$6=$6/1000000;ratio=($6>0?$5/$6:0);print $1\"§\"$2\"§\"$3\"§\"$4\"§\"$5\"§\"$6\"§\"ratio}'|head -n1"];running:true;stdout:SplitParser{onRead:function(l){root.applyPlayer(l)}}}
  Timer{interval:2000;running:true;repeat:true;onTriggered:{cpu.running=true;net.running=true;player.running=true}}
  Timer{interval:5000;running:true;repeat:true;onTriggered:{gpu.running=true;temp.running=true}}
  Timer{interval:900000;running:true;repeat:true;onTriggered:weather.running=true}
  Timer{id:playerPoll;interval:350;repeat:false;onTriggered:player.running=true}

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      anchors { top: true; right: true }
      margins { top: 52; right: 30 }
      implicitWidth: 460
      implicitHeight: (weatherTemp !== "" ? 166 : 0) + 198 + 158 + 28
      color: "transparent"
      WlrLayershell.namespace: "omarchy-custom-widgets"
      // Desktop layer keeps all regular application windows above the cards;
      // the surface itself still receives pointer input on the desktop.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      exclusionMode: ExclusionMode.Ignore
      ColumnLayout {
        anchors.fill: parent
        spacing: 14
        Rectangle {
          visible: weatherTemp !== ""
          Layout.fillWidth: true; Layout.preferredHeight: 166
          radius: 30; color: root.glassFill; border.width: 1; border.color: root.glassBorder
          gradient: Gradient {
            GradientStop { position: 0; color: "#68FFFFFF" }
            GradientStop { position: 0.36; color: "#37DCEEFF" }
            GradientStop { position: 1; color: "#2B24334A" }
          }
          Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 29; color: "transparent"; border.width: 1; border.color: "#42FFFFFF" }
          RowLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 16
            Text { text: root.weatherSymbol; color: root.glassText; font.family: root.uiFont; font.pixelSize: 42; Layout.alignment: Qt.AlignVCenter }
            ColumnLayout {
              Layout.fillWidth: true; spacing: 4
              Text { text: root.weatherTemp + "  " + root.weatherDesc; color: root.glassText; font.family: root.uiFont; font.pixelSize: 27; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
              Text { text: root.weatherMeta; color: root.glassMutedText; opacity: .88; font.family: root.uiFont; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
              Text { text: root.weatherWind; color: root.glassText; opacity: .94; font.family: root.uiFont; font.pixelSize: 14; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
            }
          }
        }
        GridLayout {
          Layout.fillWidth: true; columns: 2; columnSpacing: 14; rowSpacing: 14
          Repeater {
            model: [{text:root.cpuText,icon:"ϟ"},{text:root.gpuText,icon:"◈"},{text:root.tempText,icon:"♨"},{text:root.netText,icon:"⌁"}]
            delegate: Rectangle {
              required property var modelData
              property string metricIcon: modelData ? modelData.icon : ""
              property string metricText: modelData ? modelData.text : ""
              Layout.fillWidth: true; Layout.preferredHeight: 92
              radius: 26; color: root.glassFill; border.width: 1; border.color: root.glassBorder
              gradient: Gradient {
                GradientStop { position: 0; color: "#5CFFFFFF" }
                GradientStop { position: 0.40; color: "#30CEE7FF" }
                GradientStop { position: 1; color: "#2924334A" }
              }
              Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 25; color: "transparent"; border.width: 1; border.color: "#38FFFFFF" }
              RowLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 10
                Text { text: parent.parent.metricIcon; color: root.glassText; font.family: root.uiFont; font.pixelSize: 17; Layout.alignment: Qt.AlignVCenter }
                ColumnLayout {
                  Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 6
                  Text { text: parent.parent.parent.metricText; color: root.glassText; font.family: root.uiFont; font.pixelSize: 16; Layout.fillWidth: true; elide: Text.ElideRight }
                  Rectangle {
                    visible: parent.parent.parent.parent.metricIcon === "ϟ" || parent.parent.parent.parent.metricIcon === "⌁"
                    Layout.fillWidth: true; Layout.preferredHeight: 3; radius: 2; color: "#35FFFFFF"
                    property real level: parent.parent.parent.parent.metricIcon === "ϟ" ? root.cpuLoad : root.netLoad
                    Rectangle { width: parent.level < 0 ? 0 : parent.width * parent.level; height: parent.height; radius: parent.radius; color: "#EFFFFFFF"; Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
                  }
                }
              }
            }
          }
        }
        Rectangle {
          Layout.fillWidth: true; Layout.preferredHeight: 158
          radius: 30; color: root.glassFill; border.width: 1; border.color: root.glassBorder
          gradient: Gradient {
            GradientStop { position: 0; color: "#68FFFFFF" }
            GradientStop { position: 0.36; color: "#37DCEEFF" }
            GradientStop { position: 1; color: "#2B24334A" }
          }
          Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 29; color: "transparent"; border.width: 1; border.color: "#42FFFFFF" }
          ColumnLayout {
            anchors.fill: parent; anchors.margins: 18
            RowLayout { Layout.fillWidth: true
              Text { text: "NOW PLAYING"; color: root.glassMutedText; opacity: .90; font.family: root.uiFont; font.pixelSize: 11; font.bold: true; Layout.fillWidth: true }
              Text { text: root.playerStatus.toUpperCase(); color: root.glassMutedText; opacity: .90; font.family: root.uiFont; font.pixelSize: 11; font.bold: true }
            }
            Text { text: root.artist; color: root.glassText; font.family: root.uiFont; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
            Text { text: root.title + (root.album !== "" ? "  ·  " + root.album : ""); color: root.glassMutedText; font.family: root.uiFont; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
            Rectangle { id: seekBar; Layout.fillWidth: true; Layout.preferredHeight: 12; radius: 6; color: "transparent"
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 5; radius: 3; color: "#42FFFFFF" }
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * root.progress; height: 5; radius: 3; color: "#EFFFFFFF" }
              Rectangle { x: Math.max(0, Math.min(parent.width - width, parent.width * root.progress - width / 2)); anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: "#F7FBFF"; border.width: 1; border.color: "#80FFFFFF"; visible: seekMouse.containsMouse || seekMouse.pressed }
              MouseArea { id: seekMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton
                onPressed: function(mouse) { root.seeking=true; root.seekTo(mouse.x / width) }
                onPositionChanged: function(mouse) { if (pressed) root.seekTo(mouse.x / width) }
                onReleased: { root.seeking=false; playerPoll.restart() }
              }
            }
            RowLayout { Layout.fillWidth: true
              Text { text: root.elapsed + " / " + root.duration; color: root.glassMutedText; opacity: .90; font.family: root.uiFont; font.pixelSize: 11; Layout.fillWidth: true }
              Row { spacing: 6
                Rectangle { width: 98; height: 28; radius: 14; color: playMouse.containsMouse ? "#7AFFFFFF" : "#4DFFFFFF"; border.width: 1; border.color: "#70FFFFFF"
                  Row { anchors.centerIn: parent; spacing: 5
                    Text { text: root.playerStatus === "Playing" ? "Ⅱ" : "▶"; color: root.glassText; font.family: root.uiFont; font.pixelSize: 13 }
                    Text { text: root.playerStatus === "Playing" ? "Pause" : "Play"; color: root.glassText; font.family: root.uiFont; font.pixelSize: 11; font.bold: true }
                  }
                  MouseArea { id: playMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePlayback() }
                }
                Rectangle { width: 78; height: 28; radius: 14; color: stopMouse.containsMouse ? "#7AFFFFFF" : "#4DFFFFFF"; border.width: 1; border.color: "#70FFFFFF"
                  Row { anchors.centerIn: parent; spacing: 5
                    Text { text: "■"; color: root.glassText; font.family: root.uiFont; font.pixelSize: 13 }
                    Text { text: "Stop"; color: root.glassText; font.family: root.uiFont; font.pixelSize: 11; font.bold: true }
                  }
                  MouseArea { id: stopMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton; cursorShape: Qt.PointingHandCursor; onClicked: root.playerCommand("stop") }
                }
              }
            }
          }
        }
      }
    }
  }
  Process{id:control;command:["true"]}
}
