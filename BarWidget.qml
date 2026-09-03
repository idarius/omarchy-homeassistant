import QtQuick
import Quickshell
import Quickshell.Hyprland
import Qt.labs.folderlistmodel
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
  // Meme chemin que `ha-window`, XDG_STATE_HOME compris — il ne l'etait pas.
  readonly property string stateHome: {
    var x = String(Quickshell.env("XDG_STATE_HOME") || "")
    return x.length > 0 ? x : Quickshell.env("HOME") + "/.local/state"
  }
  readonly property string stateDir: root.stateHome + "/omarchy/homeassistant"
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
  // Identification par ADRESSE, publiee par ha-window sous forme de NOM DE
  // FICHIER (voir plus bas, FolderListModel).
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

  // L'ADRESSE EST UN NOM DE FICHIER, PAS UN CONTENU.
  //
  // La version precedente lisait `window-address` avec un `FileView`. Quickshell
  // n'expose AUCUN plafond de taille dessus — verifie dans sa source : un
  // fichier d'etat demesure aurait ete charge en entier DANS LE PROCESSUS DE LA
  // BARRE, et un tube nomme depose a sa place aurait fait attendre l'ouverture.
  // Le widget etait ainsi un second lecteur du meme etat, independant des
  // controles du script et non borne.
  //
  // Le repertoire d'etat contient donc au plus UNE entree VIDE dont le NOM est
  // l'adresse (`0x…`). On ne lit plus que des noms — bornes par le systeme de
  // fichiers — et jamais un contenu.
  //
  // L'entree est a la RACINE de l'etat, pas dans un sous-repertoire `window/`
  // comme en 1.2.0 : ce sous-repertoire etait le seul composant que `ha-window`
  // resolvait encore par son nom, donc le seul qu'il ne pouvait pas verifier.
  // `nameFilters` fait le tri, et le widget ne voit ni `lock`, ni
  // `window-class`, ni les marqueurs internes du script.
  FolderListModel {
    id: windowDir
    folder: "file://" + root.stateDir
    showDirs: false
    showHidden: false
    nameFilters: ["0x*"]
    onCountChanged: root.windowAddress = root.firstValidAddress()
  }

  // PIEGE VERIFIE : quand `folder` designe un repertoire INEXISTANT — le cas
  // d'une installation neuve, avant le premier lancement — FolderListModel
  // retombe silencieusement sur le repertoire courant du processus et en liste
  // le contenu. La validation stricte du nom n'est donc pas un confort : c'est
  // elle qui rend ce repli inoffensif.
  function firstValidAddress() {
    for (var i = 0; i < windowDir.count; i++) {
      var name = String(windowDir.get(i, "fileName") || "")
      if (/^0x[0-9a-f]{1,16}$/.test(name)) return name
    }
    return ""
  }

  // --- actions ------------------------------------------------------------
  //
  // ARGV DIRECT, PAS DE SHELL. `bar.run()` passe par
  // `Quickshell.execDetached(["bash", "-lc", commande])` : un shell de LOGIN,
  // qui source `/etc/profile`, les `profile.d` et `~/.bash_profile` avant
  // d'executer quoi que ce soit. Mesure sur cette machine : **134 ms**, contre
  // 1 ms pour `bash -c`.
  //
  // Ces 134 ms tombaient sur CHAQUE action declenchee par le widget, et sur
  // elles seules : le masquage au clic ailleurs part d'un bind Hyprland, qui
  // n'utilise pas de shell de login. D'ou l'asymetrie constatee — fermer en
  // cliquant l'icone trainait, fermer en cliquant ailleurs non.
  //
  // On passe donc un ARGV, execute directement. C'est aussi une surface en
  // moins : plus aucune valeur de reglage ne traverse une ligne de commande
  // interpretee, donc plus rien a echapper (le `quote()` maison a disparu).
  // `ha-window` valide de toute facon chaque argument de son cote.
  //
  // L'environnement devient celui de la session (celui de quickshell) au lieu
  // de celui d'un shell de login. Verifie : son PATH contient /usr/bin,
  // /usr/local/bin, ~/.local/bin et les exports flatpak, et les quatre
  // dependances (chromium, jq, hyprctl, bash) sont dans /usr/bin.
  function argv(action, extra) {
    var a = [root.script, action,
             "--url", String(url),
             "--width", String(winWidth),
             "--height", String(winHeight),
             "--position", String(position),
             "--margin-x", String(marginX),
             "--margin-y", String(marginY),
             "--anim-ms", String(animMs)]
    if (!autoHide) a.push("--no-click-dismiss")
    // `extra` accepte un drapeau ou un tableau de drapeaux : `openConfig` en
    // passe deux.
    if (extra) {
      if (Array.isArray(extra)) for (var i = 0; i < extra.length; i++) a.push(String(extra[i]))
      else a.push(String(extra))
    }
    return a
  }

  function run(action, extra) {
    if (!root.bar) return
    Quickshell.execDetached(root.argv(action, extra))
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
    // `--no-focus` en plus : sans lui, le `hl.dsp.focus` final de `show` arrive
    // APRES l'ouverture du panneau et emporte le focus CLAVIER sur le
    // navigateur. Le focus grab du panneau garde la souris, donc les fleches
    // des champs numeriques repondaient encore — mais plus aucune frappe.
    if (root.configured && !root.shown) root.run("show", ["--no-click-dismiss", "--no-focus"])
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

  // --- regle `no_anim`, reposee apres un rechargement de config -----------
  //
  // `ha-window` pose sur la fenetre une regle `no_anim = true` via
  // `hyprctl eval`. Sans elle, Hyprland anime CHAQUE image du glissement (~100
  // par seconde) et la position RENDUE prend un decalage lateral durable —
  // mesure a +355 px, identique sur les deux ecrans, que ni un `move`, ni un
  // `resize`, ni un `float` ne resorbent : seule une fenetre neuve repart
  // juste. La vue apparait alors tronquee, d'une largeur qui change a chaque
  // affichage.
  //
  // Or `hyprctl reload` efface les regles de fenetre SANS changer la signature
  // d'instance : le marqueur `noanim.<signature>` survivait au rechargement et
  // `ensure_no_anim` ne reposait plus rien. Le bug s'installait alors jusqu'au
  // prochain `omarchy restart shell`.
  //
  // Hyprland emet `configreloaded>>` sur son socket d'evenements — verifie au
  // `socat`. Le widget l'ecoute et fait reposer la regle.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded" && root.configured) root.run("ensure-noanim")
    }
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
