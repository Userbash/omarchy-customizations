import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "CatMotion.js" as Motion
import "SpectrumParser.js" as Spectrum

Item {
  id: root

  // Only fixed, local paths are passed to Cava: no user input reaches a shell.
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/music-desktop"
  readonly property int bandCount: 144
  readonly property int spriteWidth: 138
  readonly property int spriteHeight: 146
  readonly property int catHitboxHeight: 138
  // The panel is shown on a 144 Hz display. Keep the simulation step tied to
  // that refresh rate, with fractional pose frames between whole samples.
  property var bands: Array(bandCount).fill(0)
  property real energy: 0
  property real spectrumPeak: 0
  property real musicLevel: 0
  property real musicDrive: 0
  property real energyFloor: 0
  property real catTempo: 0
  property string clockText: ""
  property string monthText: ""
  property string dayText: ""
  property string weekdayText: ""
  property real walkPhase: 0
  property real lastRawEnergy: 0
  property real idleBob: 0
  // A single canonical resting pose. Every new screen surface and every
  // completed music animation returns to these values before motion resumes.
  readonly property real catDefaultX: 610
  readonly property real catDefaultY: 168
  readonly property real catDefaultZ: 3
  readonly property real catDefaultRotation: 0
  readonly property bool catDefaultFacingRight: false
  // Cat movement starts only after a short, audible signal. It remains still
  // through quiet gaps and when Cava is receiving no music at all.
  property bool musicActive: false
  property real audibleSeconds: 0
  property real quietSeconds: 0
  property real catFrame: 0
  property real catX: catDefaultX
  property real catY: catDefaultY
  property real catZ: catDefaultZ
  property real catVelocityX: 0
  property real catVelocityY: 0
  property real pointerVelocityX: 0
  property real patrolDirection: -1
  property real jumpCooldown: 0
  property bool catDragging: false
  property bool catFacingRight: catDefaultFacingRight
  property real cursorDistance: 9999
  property real catStageWidth: 0
  property real catStageHeight: 0
  property bool catStageReady: false
  property var catStageOwner: null
  property bool catAnimationActive: false
  property real beatPeak: 0
  property real catSpin: catDefaultRotation
  property real catTailAngle: 0
  property real dragOffsetX: 0
  property real dragOffsetY: 0
  property real lastSpectrumAt: 0
  property bool spectrumStale: true
  property string cavaError: ""
  property int cavaRestartCount: 0
  readonly property int cavaMaxRetries: 5
  property int cavaConsecutiveFailures: 0
  property real cavaBackoffSeconds: 2
  property var catPose: Motion.CatMotion.pose(0, 0, catDefaultFacingRight)
  readonly property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

  function clamp(value) {
    return Math.max(0, Math.min(1, Number(value) || 0))
  }

  function resetCatAnimation() {
    // Keep this complete: a screen lock can remove the Wayland output while
    // the root service stays alive. Carrying over even one velocity, pose, or
    // rotation value makes the newly-created surface appear to jump or tilt.
    root.bands = Array(root.bandCount).fill(0)
    root.energy = 0
    root.spectrumPeak = 0
    root.musicLevel = 0
    root.musicDrive = 0
    root.energyFloor = 0
    root.catTempo = 0
    root.walkPhase = 0
    root.lastRawEnergy = 0
    root.idleBob = 0
    root.musicActive = false
    root.audibleSeconds = 0
    root.quietSeconds = 0
    root.catFrame = 0
    root.catX = root.catDefaultX
    root.catY = root.catDefaultY
    root.catZ = root.catDefaultZ
    root.catVelocityX = 0
    root.catVelocityY = 0
    root.pointerVelocityX = 0
    root.patrolDirection = -1
    root.jumpCooldown = 0
    root.catDragging = false
    root.catFacingRight = root.catDefaultFacingRight
    root.cursorDistance = 9999
    root.beatPeak = 0
    root.catSpin = root.catDefaultRotation
    root.catTailAngle = 0
    root.dragOffsetX = 0
    root.dragOffsetY = 0
    root.lastSpectrumAt = 0
    root.spectrumStale = true
    root.catPose = Motion.CatMotion.pose(0, 0, root.catDefaultFacingRight)
    root.catAnimationActive = false

    // The canonical defaults fit the normal DP-6 stage. Clamp only for a
    // smaller transient/fallback surface so no invalid coordinate leaks into
    // the next real monitor.
    if (root.catStageWidth > 0 && root.catStageHeight > 0) {
      root.catX = Motion.CatMotion.clamp(root.catX, 0, Math.max(0, root.catStageWidth - root.spriteWidth))
      root.catY = Motion.CatMotion.clamp(root.catY, 0, Math.max(0, root.catStageHeight - root.spriteHeight))
    }
  }

  function updateCatStage(stage, width, height) {
    var nextWidth = Math.max(0, Number(width) || 0)
    var nextHeight = Math.max(0, Number(height) || 0)
    if (root.catStageOwner !== null && root.catStageOwner !== stage) return
    if (nextWidth < root.spriteWidth || nextHeight < root.spriteHeight) {
      if (root.catStageOwner !== null && root.catStageOwner !== stage) return
      root.catStageOwner = stage
      root.catStageReady = false
      root.catStageWidth = 0
      root.catStageHeight = 0
      root.resetCatAnimation()
      return
    }

    var changed = !root.catStageReady || root.catStageWidth !== nextWidth || root.catStageHeight !== nextHeight
    root.catStageOwner = stage
    root.catStageWidth = nextWidth
    root.catStageHeight = nextHeight
    root.catStageReady = true
    // A new or resized stage follows a lock/DPMS transition. Start from the
    // same safe pose rather than applying stale physics to a new surface.
    if (changed) root.resetCatAnimation()
  }

  function invalidateCatStage(stage) {
    // During a DPMS/lock transition a replacement stage can be created before
    // the old one is destroyed. Only the currently active stage may invalidate
    // shared motion state; an old delegate must not stop the new display.
    if (root.catStageOwner !== stage) return
    root.catStageOwner = null
    root.catStageReady = false
    root.catStageWidth = 0
    root.catStageHeight = 0
    root.resetCatAnimation()
  }

  function updateClock() {
    var now = new Date()
    var months = ["ЯНВАРЯ", "ФЕВРАЛЯ", "МАРТА", "АПРЕЛЯ", "МАЯ", "ИЮНЯ", "ИЮЛЯ", "АВГУСТА", "СЕНТЯБРЯ", "ОКТЯБРЯ", "НОЯБРЯ", "ДЕКАБРЯ"]
    var weekdays = ["ВОСКРЕСЕНЬЕ", "ПОНЕДЕЛЬНИК", "ВТОРНИК", "СРЕДА", "ЧЕТВЕРГ", "ПЯТНИЦА", "СУББОТА"]
    clockText = Qt.formatDateTime(now, "HH:mm")
    monthText = months[now.getMonth()]
    dayText = String(now.getDate())
    weekdayText = weekdays[now.getDay()]
  }

  function applySpectrum(line) {
    var parsed = Spectrum.SpectrumParser.parse(line, root.bandCount)
    bands = parsed.bands
    energy = parsed.energy
    spectrumPeak = parsed.peak
    lastSpectrumAt = Date.now()
    spectrumStale = false
    cavaConsecutiveFailures = 0
    cavaBackoffSeconds = 2
    cavaError = ""
  }

  function clearSpectrum() {
    bands = Array(root.bandCount).fill(0)
    energy = 0
    spectrumPeak = 0
    lastRawEnergy = 0
    lastSpectrumAt = 0
    spectrumStale = true
  }

  function moveCatToward(mouseX, mouseY) {
    var dx = Number(mouseX) - (catX + 56)
    var dy = Number(mouseY) - (catY + 68)
    var distance = Math.sqrt(dx * dx + dy * dy)
    cursorDistance = distance
    // A nearby cursor only sets a gentle target speed. The 144 Hz loop eases
    // toward it, so pointer movement can never create a sharp velocity spike.
    if (!catDragging && distance < 240) {
      pointerVelocityX = Motion.CatMotion.clamp(dx * 0.55, -90, 90)
      catFacingRight = dx > 0
    }
  }

  FrameAnimation {
    id: catMotionTimer
    // Runs once per rendered frame, so on the verified 144 Hz DP-6 monitor
    // the cat receives 144 updates per second. frameTime keeps each update
    // stable if the compositor briefly presents slower.
    // Do not advance physics while the lock screen has removed the monitor.
    // The next valid stage will reset and begin cleanly from the default pose.
    running: root.catStageReady
    onTriggered: {
      var dt = Motion.CatMotion.clamp(frameTime, 1 / 240, 1 / 45)
      if (root.lastSpectrumAt > 0 && Date.now() - root.lastSpectrumAt > 1200) {
        root.clearSpectrum()
      }
      // A fast attack follows the beat; a shorter release keeps the result
      // lively while still interpolating every rendered frame.
      // The band average gives the overall loudness; the strongest band keeps
      // bass/drum hits visible even when the other 143 bands are quiet.
      var musicSignal = Math.max(root.energy, root.spectrumPeak * 0.52)
      var levelResponse = musicSignal > root.musicLevel ? 18 : 5.5
      root.musicLevel = Motion.CatMotion.smooth(root.musicLevel, musicSignal, dt, levelResponse)
      var audible = musicSignal >= 0.025
      if (audible) {
        root.audibleSeconds += dt
        root.quietSeconds = 0
      } else {
        root.quietSeconds += dt
        root.audibleSeconds = 0
      }
      // These thresholds filter silence but let the cat catch the rhythm
      // almost immediately when a track begins.
      if (!root.musicActive && root.audibleSeconds >= 0.08) root.musicActive = true
      if (root.musicActive && root.quietSeconds >= 0.55) root.musicActive = false

      if (!root.musicActive) {
        // The completed music animation must not leave a partial jump, flip,
        // or rotation behind for the next track or after a display wake-up.
        if (!root.catDragging && root.catAnimationActive) root.resetCatAnimation()
        if (!root.catDragging && !root.catAnimationActive &&
            (Math.abs(root.catX - root.catDefaultX) > 0.5 || Math.abs(root.catY - root.catDefaultY) > 0.5)) {
          root.catX = Motion.CatMotion.clamp(root.catDefaultX, 0, Math.max(0, root.catStageWidth - root.spriteWidth))
          root.catY = Motion.CatMotion.clamp(root.catDefaultY, 0, Math.max(0, root.catStageHeight - root.spriteHeight))
          root.catVelocityX = 0
          root.catVelocityY = 0
        }
        // No music means no motion or gravity simulation: preserve the exact
        // canonical X/Y/Z pose until a new audible signal arrives.
        return
      }
      root.catAnimationActive = true

      // Music level is normalized against a modest threshold because Cava's
      // 144-band average is naturally much smaller than its loudest bar.
      var driveTarget = Motion.CatMotion.clamp((root.musicLevel - 0.018) / 0.12, 0, 1)
      root.musicDrive = Motion.CatMotion.smooth(root.musicDrive, driveTarget, dt, driveTarget > root.musicDrive ? 10 : 4.5)
      // Track a slow local average. Peaks above it become beat impulses.
      root.energyFloor = Motion.CatMotion.smooth(root.energyFloor, root.musicLevel, dt, root.musicLevel > root.energyFloor ? 1.45 : 0.9)
      var rawRise = Math.max(0, musicSignal - root.lastRawEnergy)
      var beatSurplus = Math.max(0, root.musicLevel - root.energyFloor)
      // Cava's 60 Hz samples catch the transient first; their rise detects
      // drums reliably, while the slower surplus term follows loud phrases.
      var beatTarget = Motion.CatMotion.clamp((beatSurplus - 0.004) * 20 + rawRise * 7.5, 0, 1)
      root.beatPeak = Motion.CatMotion.smooth(root.beatPeak, beatTarget, dt, beatTarget > root.beatPeak ? 18 : 7)
      root.lastRawEnergy = musicSignal

      // Faster rhythm = faster pose cycle, stride and lean. The blend is
      // continuous, so kicks feel energetic without visible frame snapping.
      var targetTempo = root.musicActive ? 0.80 + root.musicDrive * 1.35 + root.beatPeak * 0.55 : 0
      root.catTempo = Motion.CatMotion.smooth(root.catTempo, targetTempo, dt, root.musicActive ? 5.8 : 8.5)
      root.catFrame = (root.catFrame + root.catTempo * Motion.CatMotion.frameCount * dt) % Motion.CatMotion.frameCount
      root.walkPhase = (root.walkPhase + root.catTempo * Math.PI * 2 * dt) % (Math.PI * 2)
      var targetBob = root.musicActive ? Math.sin(root.walkPhase * 1.4) * (1.2 + root.catTempo * 2.6 + root.beatPeak * 1.2) : 0
      root.idleBob = Motion.CatMotion.smooth(root.idleBob, targetBob, dt, 9)

      root.catPose = Motion.CatMotion.pose(root.catFrame, root.musicDrive, root.catFacingRight)
      root.catTailAngle = root.catPose.tail
      // A beat adds a bounded lean instead of an accumulated full spin. The
      // angle always returns to zero, so a restored screen can never reveal a
      // cat frozen sideways at 90° or 270°.
      var spinAmplitude = root.musicActive ? 1.5 + root.musicDrive * 4 + root.beatPeak * 10 : 0
      var spinTarget = Math.sin(root.walkPhase * 2.1) * spinAmplitude
      root.catSpin = Motion.CatMotion.smooth(root.catSpin, spinTarget, dt, root.musicActive ? 12 : 8)

      if (!root.catDragging && root.catStageWidth > 0) {
        if (root.catX <= 0.5) root.patrolDirection = 1
        else if (root.catX >= root.catStageWidth - root.spriteWidth - 0.5) root.patrolDirection = -1
        var patrolSpeed = root.musicActive ? 120 + root.musicDrive * 170 + root.beatPeak * 70 : 0
        var patrolVelocity = root.patrolDirection * patrolSpeed + Math.sin(root.walkPhase * 1.5) * (18 + root.beatPeak * 32)
        if (root.musicActive && root.cursorDistance < 240) patrolVelocity += root.pointerVelocityX
        root.catVelocityX = Motion.CatMotion.smooth(root.catVelocityX, patrolVelocity, dt, root.musicActive ? 6.2 : 10)
        root.jumpCooldown = Math.max(0, root.jumpCooldown - dt)
        var floorY = root.catStageHeight - root.spriteHeight
        // One bounded, smooth hop per beat cluster. A cooldown stops rapid
        // machine-gun jumping while retaining clear musical accents.
        if (root.musicActive && root.catY >= floorY - 0.5 && root.beatPeak > 0.22 && root.jumpCooldown === 0) {
          root.catVelocityY = -(245 + root.musicDrive * 115 + root.beatPeak * 95)
          root.jumpCooldown = 0.30
        }
        // Mouse guidance fades away too, so the cat never suddenly changes
        // direction when the pointer leaves its hit area.
        root.pointerVelocityX = Motion.CatMotion.smooth(root.pointerVelocityX, 0, dt, 2.6)
        var next = Motion.CatMotion.nextPosition({ x: root.catX, y: root.catY, vx: root.catVelocityX, vy: root.catVelocityY }, root.catStageWidth, root.catStageHeight, dt)
        root.catX = next.x; root.catY = next.y; root.catVelocityX = next.vx; root.catVelocityY = next.vy
        if (Math.abs(next.vx) > 1) root.catFacingRight = next.vx > 0
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.updateClock()
  }

  Component.onCompleted: root.updateClock()

  Process {
    id: cava
    command: ["cava", "-p", root.pluginDir + "/cava.conf"]
    running: true
    stdout: SplitParser { onRead: function(line) { root.applySpectrum(line) } }
    stderr: SplitParser { onRead: function(line) { root.cavaError = String(line || "").trim() } }
    onExited: function(exitCode) {
      root.cavaError = exitCode === 0 ? "Cava exited" : "Cava exited with code " + exitCode
      root.clearSpectrum()
      root.cavaRestartCount += 1
      root.cavaConsecutiveFailures += 1
      if (root.cavaConsecutiveFailures >= root.cavaMaxRetries) {
        root.cavaError = "Cava disabled after " + root.cavaMaxRetries + " consecutive failures"
        return
      }
      restartTimer.interval = Math.min(30000, Math.max(2000, root.cavaBackoffSeconds * 1000))
      root.cavaBackoffSeconds = Math.min(30, root.cavaBackoffSeconds * 2)
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: {
      cava.running = true
    }
  }

  Timer {
    id: spectrumWatchdog
    interval: 500
    running: true
    repeat: true
    onTriggered: {
      if (root.lastSpectrumAt > 0 && Date.now() - root.lastSpectrumAt > 1200) root.clearSpectrum()
    }
  }

  Variants {
    model: root.targetScreen ? [root.targetScreen] : []

    PanelWindow {
      id: desktop
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-music-desktop"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // The surface is transparent and has no input mask, so desktop clicks
      // continue through to the wallpaper and ordinary windows.
      Item {
        anchors.fill: parent

        Row {
          id: spectrum
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: 30
          anchors.rightMargin: 30
          anchors.bottomMargin: 16
          height: 210
          spacing: 7

          Repeater {
            model: root.bandCount
            Rectangle {
              required property int index
              width: (spectrum.width - spectrum.spacing * (root.bandCount - 1)) / root.bandCount
              height: Math.max(4, spectrum.height * (0.02 + root.bands[index] * 0.98))
              anchors.bottom: parent.bottom
              radius: 2
              color: "#e9edf2"
              opacity: 0.45 + root.bands[index] * 0.38
              Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
              Behavior on opacity { NumberAnimation { duration: 70 } }
            }
          }
        }

        Item {
          id: clockArea
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          // Keep the time in the lower centre, above the visualizer and next
          // to the cat's running area.
          anchors.bottomMargin: spectrum.height + spectrum.anchors.bottomMargin + 36
          width: clockTextItem.implicitWidth
          height: clockTextItem.implicitHeight
          z: 10

          Text {
            id: clockTextItem
            anchors.centerIn: parent
            text: root.clockText
            color: "#ffffff"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 116
            font.weight: Font.ExtraBold
            style: Text.Outline
            styleColor: "#2a3046a0"
            verticalAlignment: Text.AlignVCenter
          }
        }

        // The date is deliberately outside the large clock so neither text
        // can cover the other; it stays readable at the right of the time.
        Column {
          id: dateColumn
          anchors.left: clockArea.right
          anchors.leftMargin: 34
          anchors.verticalCenter: clockArea.verticalCenter
          spacing: 1
          z: 12
          Text { text: root.monthText; color: "#ffffff"; opacity: 0.90; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16; font.weight: Font.Bold }
          Text { text: root.dayText; color: "#ffffff"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 38; font.weight: Font.ExtraBold }
          Text { text: root.weekdayText; color: "#ffffff"; opacity: 0.92; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; font.weight: Font.DemiBold }
        }

        Item {
          id: catStage
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 18
          // The cat owns the whole lower desktop area; it can run under the
          // clock, leap onto its baseline, and fall with bounded physics.
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.min(parent.height * 0.46, 540)
          z: 11
          Component.onCompleted: root.updateCatStage(catStage, width, height)
          Component.onDestruction: root.invalidateCatStage(catStage)
          onWidthChanged: root.updateCatStage(catStage, width, height)
          onHeightChanged: root.updateCatStage(catStage, width, height)

          Item {
            id: catWalker
            width: root.spriteWidth
            height: root.spriteHeight
            x: root.catX
            y: root.catY
            z: root.catZ

            Image {
              id: cat
              width: 138
              height: 138
              // Original transparent cat artwork; no opaque square backdrop.
              source: "file://" + root.pluginDir + "/assets/music-cat-reference.png"
              fillMode: Image.PreserveAspectFit
              smooth: true
              y: root.idleBob + root.catPose.bob
              transformOrigin: Item.Bottom
              rotation: root.catPose.lean + root.catSpin
              transform: Scale {
                id: catBeatScale
                origin.x: cat.width / 2
                origin.y: cat.height
                xScale: root.catPose.scaleX
                yScale: root.catPose.scaleY
                Behavior on xScale { NumberAnimation { duration: 140; easing.type: Easing.InOutSine } }
                Behavior on yScale { NumberAnimation { duration: 140; easing.type: Easing.InOutSine } }
              }
              Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.InOutSine } }
              Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.InOutSine } }
            }

            Rectangle {
              // Tail motion is drawn separately so the transparent SVG never
              // carries the opaque square background from the old PNG sprite.
              width: 48; height: 9; radius: 5
              color: "#c8ad91"
              border.color: "#50463e"; border.width: 3
              x: root.catFacingRight ? 84 : 4; y: 86
              transformOrigin: Item.Left
              rotation: root.catTailAngle
              Behavior on rotation { NumberAnimation { duration: 120; easing.type: Easing.InOutSine } }
              z: -2
            }

            // Soft contact shadow sells the hop and squash without adding input.
            Rectangle {
              id: catShadow
              width: 94 + root.musicDrive * 24
              height: 10 - root.musicDrive * 3
              radius: height / 2
              color: "#1b1b1b"
              opacity: 0.22 - root.musicDrive * 0.07
              x: 22
              y: 134
              z: -1
              Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.InOutSine } }
              Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.InOutSine } }
            }

            // The only interactive surface is the cat itself; normal desktop
            // clicks outside it still pass through the Bottom layer.
            MouseArea {
              width: root.spriteWidth
              height: root.catHitboxHeight
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: Qt.OpenHandCursor
              onPositionChanged: function(mouse) {
                if (pressed) {
                  root.catX = Motion.CatMotion.clamp(catWalker.x + mouse.x - root.dragOffsetX, 0, catStage.width - root.spriteWidth)
                  root.catY = Motion.CatMotion.clamp(catWalker.y + mouse.y - root.dragOffsetY, 0, catStage.height - root.spriteHeight)
                  root.catVelocityX = 0; root.catVelocityY = 0
                } else root.moveCatToward(catWalker.x + mouse.x, catWalker.y + mouse.y)
              }
              onPressed: function(mouse) {
                root.catDragging = true
                root.dragOffsetX = mouse.x
                root.dragOffsetY = mouse.y
                cursorShape = Qt.ClosedHandCursor
                root.moveCatToward(catWalker.x + mouse.x, catWalker.y + mouse.y)
              }
              onReleased: {
                root.catDragging = false
                cursorShape = Qt.OpenHandCursor
                // Releasing the cat leaves it on the floor rather than
                // launching a sudden jump.
                root.catVelocityY = 0
                root.catY = Motion.CatMotion.clamp(root.catY, 0, catStage.height - root.spriteHeight)
              }
              onCanceled: { root.catDragging = false; root.catVelocityX = 0; root.catVelocityY = 0; cursorShape = Qt.OpenHandCursor }
              onEntered: root.cursorDistance = 0
              onExited: root.cursorDistance = 9999
            }
          }
        }
      }
    }
  }
}
