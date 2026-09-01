import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import "Strings.js" as Strings

// Icone Home Assistant dans la barre.
//   clic gauche  -> affiche / masque la fenetre
//   clic droit   -> panneau de configuration
//
// La fenetre n'est pas une webview : QtWebEngine fait planter Quickshell
// (« base::CommandLine cannot be properly initialized »), il emporterait la
// barre. C'est une fenetre de navigateur en mode application, rangee dans un
// special workspace Hyprland ; toute la mecanique est dans le script
// ha-window, a cote de ce fichier.
//
// CE WIDGET NE SUPPOSE JAMAIS L'ETAT DE LA FENETRE, IL LE LIT.
// La version precedente suivait un `property bool shown` qu'elle mettait a
// jour elle-meme ; il divergeait des que la fenetre bougeait par un autre
// chemin (raccourci Hyprland, fermeture manuelle, echec du script), et les
// trois defauts connus en decoulaient. L'etat vient maintenant du compositeur.
BarWidget {
  id: root
  moduleName: "io.github.idarius.homeassistant"

  readonly property string script: Qt.resolvedUrl("ha-window").toString().replace("file://", "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/homeassistant"
  readonly property string specialWorkspace: "special:homeassistant"

  readonly property string url: setting("url", "")
  readonly property int winWidth: setting("width", 480)
  readonly property int winHeight: setting("height", 900)
  readonly property string position: setting("position", "top-right")
  // `margin` reste le defaut commun : les reglages par axe ne sont apparus
  // qu'apres, et une configuration existante ne doit pas sauter.
  readonly property int margin: setting("margin", 12)
  readonly property int marginX: setting("marginX", root.margin)
  readonly property int marginY: setting("marginY", root.margin)
  readonly property bool autoHide: setting("autoHide", true)
  readonly property bool prewarm: setting("prewarm", true)
  readonly property bool sharedProfile: setting("sharedProfile", false)

  // Langue de l'interface : auto|en|fr. « auto » suit la locale du systeme
  // (Qt.locale().name, par exemple "fr_FR") et retombe sur l'anglais.
  readonly property string language: setting("language", "auto")
  readonly property string lang: Strings.resolve(root.language, Qt.locale().name)
  function tr(key) { return Strings.t(root.lang, key) }
  readonly property int animMs: setting("animMs", 220)

  // Cote de l'ecran ou la vue se pose : le panneau de reglages ira a l'oppose.
  readonly property bool viewOnRight: String(root.position).indexOf("right") >= 0

  readonly property bool configured: String(url).trim().length > 0

  // --- etat reel de la fenetre -------------------------------------------
  //
  // Identification par ADRESSE, ecrite par ha-window au lancement.
  //
  // Pas par classe : Hyprland.toplevels expose bien `lastIpcObject` (donc la
  // classe), mais il reste vide pour toute fenetre apparue APRES le demarrage
  // du shell — verifie. La fenetre HA est justement lancee en cours de route.
  // Et de toute facon Chromium fabrique sa classe a partir de l'URL, elle
  // changerait donc avec le tableau de bord configure.
  property string windowAddress: ""

  // Une adresse Hyprland est un pointeur, et peut etre reattribuee a une autre
  // fenetre apres fermeture. Ici la consequence se limite a une icone qui
  // ment jusqu'au prochain evenement : ce widget ne fait que LIRE. Le cote
  // dangereux — les dispatchers geometriques — est protege dans ha-window, qui
  // recoupe l'adresse avec la classe memorisee avant d'agir.
  function normalizeAddress(value) {
    var s = String(value || "").trim().toLowerCase()
    return s.indexOf("0x") === 0 ? s.substring(2) : s
  }

  readonly property var haToplevel: {
    var want = root.normalizeAddress(root.windowAddress)
    if (!want) return null
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      if (root.normalizeAddress(values[i].address) === want) return values[i]
    }
    return null
  }

  readonly property bool windowExists: haToplevel !== null

  // « Affichee » = presente ET hors de la reserve.
  // `workspace.name` est suivi en direct par Quickshell, y compris vers et
  // depuis un special workspace — verifie.
  //
  // APPROXIMATION ASSUMEE : un special workspace peut etre OUVERT sur un ecran,
  // et sa fenetre est alors bien visible tout en etant « dans la reserve ».
  // Ce cas n'est pas detectable ici : `HyprlandWorkspace.active` reste a false
  // dans ce cas (verifie), et `Hyprland.monitors` n'a pas pu etre valide hors
  // du processus de la barre — on ne code pas contre une API non lue.
  //
  // C'est sans consequence en pratique :
  //   - ha-window referme systematiquement la reserve apres un `hide` et apres
  //     un lancement, donc le plugin ne cree jamais cet etat ;
  //   - la DECISION du clic ne repose pas sur cette propriete : `toggle()`
  //     delegue au script, qui lui distingue les deux cas.
  // Seule l'icone pourrait mentir, et seulement si la reserve etait ouverte par
  // un moyen exterieur au plugin.
  readonly property bool shown: haToplevel !== null
    && haToplevel.workspace !== null
    && String(haToplevel.workspace.name) !== root.specialWorkspace

  FileView {
    id: addressFile
    path: root.stateDir + "/window-address"
    watchChanges: true
    printErrors: false
    // `text()` est perime dans le signal de changement : passer par reload()
    // puis onLoaded, comme le fait Color.qml.
    onFileChanged: reload()
    onLoaded: root.windowAddress = String(text()).trim()
    onLoadFailed: root.windowAddress = ""
  }

  // --- actions ------------------------------------------------------------
  function args() {
    var a = " --url " + quote(url) +
            " --width " + winWidth +
            " --height " + winHeight +
            " --position " + quote(position) +
            " --margin-x " + marginX +
            " --margin-y " + marginY
    if (sharedProfile) a += " --shared-profile"
    if (!autoHide) a += " --no-click-dismiss"
    a += " --anim-ms " + animMs
    return a
  }

  function quote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function run(action, extra) {
    if (!root.bar) return
    root.bar.run(quote(root.script) + " " + action + root.args()
                 + (extra ? " " + extra : ""))
  }

  // La decision est deleguee au script, seul a connaitre l'etat complet : il
  // sait, lui, distinguer « rangee dans la reserve » de « rangee dans une
  // reserve ouverte a l'ecran ». Le widget ne decide pas, il affiche.
  function toggle() {
    if (!configured) { openConfig(); return }
    run("toggle")
  }

  // --- contrat exige par la barre ----------------------------------------
  //
  // `PopupCard` recoit `owner: hostWidget` (ce widget), et sa fonction close()
  // fait : `if ("close" in owner) owner.close() else root.open = false`.
  //
  // Sans `close()` ici, on tombait donc sur la branche `root.open = false` —
  // une AFFECTATION sur une propriete liee (`open: root.opened`), ce qui
  // DETRUIT la liaison. Le panneau s'ouvrait une fois, puis plus jamais.
  // C'etait la cause du « le clic droit ne fait plus rien ».
  //
  // Bar.findPanelWidget exige `open`/`close`/`opened` sur la racine du widget,
  // et Bar.requestPopout prefere `closeForPopoutSwitch`. Meme contrat que
  // plugins/panels/clock/BarWidget.qml.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Ouvrir les reglages ouvre AUSSI la vue : les changements de taille, de
  // position et de marge se voient alors en direct pendant qu'on les regle.
  function openConfig() {
    var panel = panelLoader.item
    if (!panel) { console.log("HA: panneau non charge"); return }
    if (panel.opened) { panel.close(); return }
    // `--no-click-dismiss` ici, sinon course : `show` pose le bind souris a la
    // FIN de son animation, potentiellement apres le `disarm-click` declenche
    // par l'ouverture du panneau — et un clic dans les reglages refermerait la
    // vue. Le bind sera pose a la fermeture du panneau, par onOpenedChanged.
    if (root.configured && !root.shown) root.run("show", "--no-click-dismiss")
    panel.open()
  }

  // Pendant que le panneau est ouvert, un clic dedans ne doit pas refermer la
  // vue : le bind souris est retire, puis repose a la fermeture.
  onOpenedChanged: root.run(root.opened ? "disarm-click" : "arm-click")

  // --- masquage au clic ailleurs -----------------------------------------
  //
  // PLUS RIEN ICI, volontairement. Le masquage se declenche desormais sur un
  // vrai CLIC, cote ha-window, via un bind souris non consommant pose pendant
  // que la vue est affichee.
  //
  // Pourquoi ce n'est plus le focus : cette machine a `input:follow_mouse = 1`,
  // donc survoler une autre fenetre change le focus — la vue se fermait au
  // simple mouvement de souris, y compris quand on allait vers le panneau de
  // reglages, ce qui faisait disparaitre les deux d'un coup.

  // --- prechauffage -------------------------------------------------------
  // Lance le navigateur en arriere-plan, fenetre cachee, pour que le premier
  // clic soit un simple toggle du compositeur (~80 ms) au lieu d'un demarrage
  // de navigateur (plusieurs secondes).
  Timer {
    id: prewarmTimer
    interval: 4000
    running: root.prewarm && root.configured
    repeat: false
    onTriggered: if (!root.windowExists) root.run("prewarm")
  }

  // --- geometrie ----------------------------------------------------------
  //
  // Rejouee quand un reglage change, puisque le chemin d'affichage ne
  // l'applique volontairement pas (il doit rester sous les 100 ms).
  //
  // `settled` existe parce que les liaisons de reglages s'evaluent une premiere
  // fois au montage du widget : sans ce verrou, chaque demarrage du shell
  // declenchait un `reposition`, qui recalculait la position sur l'ecran alors
  // focalise et deplacait la fenetre toute seule.
  property bool settled: false

  Timer {
    interval: 6000
    running: true
    repeat: false
    onTriggered: root.settled = true
  }

  onWinWidthChanged: repositionTimer.restart()
  onWinHeightChanged: repositionTimer.restart()
  onPositionChanged: repositionTimer.restart()
  onMarginXChanged: repositionTimer.restart()
  onMarginYChanged: repositionTimer.restart()

  Timer {
    id: repositionTimer
    interval: 400
    onTriggered: if (root.settled && root.configured && root.windowExists) root.run("reposition")
  }

  Component.onCompleted: {
    // Peuple la liste pour une fenetre HA qui aurait survecu a un redemarrage
    // du shell ; elle s'alimente ensuite seule sur les evenements Hyprland.
    if (Hyprland.refreshToplevels) Hyprland.refreshToplevels()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Ancre du panneau de reglages, invisible et volontairement hors de la barre.
  //
  // PopupCard centre le panneau sous son ancre, puis BORNE le resultat aux
  // bords de la fenetre de barre (`Math.max(margin, Math.min(...))`, lu dans
  // Ui/PopupCard.qml). Une ancre posee tres loin d'un cote fait donc coller le
  // panneau au bord OPPOSE a la vue : on regle la taille de la fenetre sans
  // que le panneau la recouvre.
  Item {
    id: configAnchor
    parent: button
    y: 0
    width: 1
    height: button.height
    x: root.viewOnRight ? -4000 : 4000
    visible: false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰟐"
    tooltipText: !root.configured
      ? root.tr("tooltipUnset")
      : (root.shown ? root.tr("tooltipHide") : root.tr("tooltipShow"))
    active: root.shown

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openConfig()
      else root.toggle()
    }
  }

  // Reinjecte a chaque changement, pas seulement au chargement : `bar` et
  // `settings` sont poses par la barre APRES la construction du widget, et une
  // injection unique laissait le panneau sans barre — or PopupCard exige `bar`.
  // Meme motif que plugins/panels/clock/BarWidget.qml (injectPanel).
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("hostWidget" in target) target.hostWidget = root
    if ("anchorItem" in target) target.anchorItem = configAnchor
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: "Panel.qml"
    onLoaded: root.injectPanel()
  }
}
