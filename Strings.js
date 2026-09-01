// Textes de l'interface / user interface strings.
//
// `.pragma library` : le fichier est charge UNE fois et partage par tous les
// composants qui l'importent. Il n'a donc acces a aucun contexte QML — ce sont
// des fonctions pures, ce qui est exactement ce qu'il faut ici.
.pragma library

var STRINGS = {
  en: {
    sectionDashboard:   "DASHBOARD",
    sectionWindow:      "WINDOW",
    sectionBehaviour:   "BEHAVIOUR",
    urlPlaceholder:     "http://homeassistant.local:8123/lovelace/0",
    width:              "Width",
    height:             "Height",
    position:           "Position",
    marginSide:         "Side margin",
    marginVertical:     "Vertical margin",
    openDuration:       "Open duration (ms)",
    hideOnOutsideClick: "Hide on outside click",
    preloadAtStartup:   "Preload at startup",
    language:           "Language",
    langAuto:           "Automatic",
    tooltipUnset:       "Home Assistant — right-click to configure",
    tooltipShow:        "Home Assistant",
    tooltipHide:        "Hide Home Assistant",
    posTopLeft:         "Top left",
    posTop:             "Top center",
    posTopRight:        "Top right",
    posLeft:            "Left",
    posCenter:          "Center",
    posRight:           "Right",
    posBottomLeft:      "Bottom left",
    posBottom:          "Bottom center",
    posBottomRight:     "Bottom right"
  },
  fr: {
    sectionDashboard:   "TABLEAU DE BORD",
    sectionWindow:      "FENETRE",
    sectionBehaviour:   "COMPORTEMENT",
    urlPlaceholder:     "http://homeassistant.local:8123/lovelace/0",
    width:              "Largeur",
    height:             "Hauteur",
    position:           "Emplacement",
    marginSide:         "Marge laterale",
    marginVertical:     "Marge verticale",
    openDuration:       "Duree d'ouverture (ms)",
    hideOnOutsideClick: "Masquer au clic ailleurs",
    preloadAtStartup:   "Prechauffer au demarrage",
    language:           "Langue",
    langAuto:           "Automatique",
    tooltipUnset:       "Home Assistant — clic droit pour configurer",
    tooltipShow:        "Home Assistant",
    tooltipHide:        "Masquer Home Assistant",
    posTopLeft:         "Haut gauche",
    posTop:             "Haut centre",
    posTopRight:        "Haut droite",
    posLeft:            "Gauche",
    posCenter:          "Centre",
    posRight:           "Droite",
    posBottomLeft:      "Bas gauche",
    posBottom:          "Bas centre",
    posBottomRight:     "Bas droite"
  }
}

// Langues proposees dans le panneau. « auto » suit la locale du systeme.
function languageOptions(lang) {
  return [
    { value: "auto", label: t(lang, "langAuto") },
    { value: "en",   label: "English" },
    { value: "fr",   label: "Francais" }
  ]
}

// `setting` vaut auto|en|fr ; `localeName` est ce que rend Qt.locale().name,
// par exemple "fr_FR". Tout ce qui n'est pas connu retombe sur l'anglais.
function resolve(setting, localeName) {
  if (setting === "fr" || setting === "en") return setting
  return String(localeName || "").indexOf("fr") === 0 ? "fr" : "en"
}

function t(lang, key) {
  var table = STRINGS[lang] || STRINGS.en
  var value = table[key]
  if (value === undefined) value = STRINGS.en[key]
  return value === undefined ? key : value
}

function positionOptions(lang) {
  return [
    { value: "top-left",     label: t(lang, "posTopLeft") },
    { value: "top",          label: t(lang, "posTop") },
    { value: "top-right",    label: t(lang, "posTopRight") },
    { value: "left",         label: t(lang, "posLeft") },
    { value: "center",       label: t(lang, "posCenter") },
    { value: "right",        label: t(lang, "posRight") },
    { value: "bottom-left",  label: t(lang, "posBottomLeft") },
    { value: "bottom",       label: t(lang, "posBottom") },
    { value: "bottom-right", label: t(lang, "posBottomRight") }
  ]
}
