#cs =========================================================================
   MIDI F4W4 STUDIO CONFIGURATOR
   -----------------------------------------------------------------------
   Professional configuration utility for the USB-MIDI controller
   featuring 4 Faders, 4 Toggle Switches, and 1 Front LED (USB PID: 0xFF04).

   HARDWARE-MIRROR ARCHITECTURE (Based on hardware.jpg):
     - 4 Vertical Channel Strips:
       * Strip 1: Toggle Switch 4 (top) + Fader 0 / F1 (bottom)
       * Strip 2: Toggle Switch 5 (top) + Fader 1 / F2 (bottom)
       * Strip 3: Toggle Switch 6 (top) + Fader 2 / F3 (bottom)
       * Strip 4: Toggle Switch 7 (top) + Fader 3 / F4 (bottom)
     - Front LED Control Bar (Position 8)
     - Scribble Strips (customizable track labels saved with profiles)
     - Real-time bidirectional MIDI In monitor with live animated faders

   COMMUNICATION & PROTOCOL:
     - Direct HID vendor transport via midiconfig.dll (hiddirect_main)
     - Automatic MachineId resolution: VID & PID (e.g. 4D44FF04)
     - Confirmed permanent Flash save sequence: 7F AF 7F 7F
=========================================================================
#ce
; =========================================================================

#NoTrayIcon
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <ComboConstants.au3>
#include <ButtonConstants.au3>
#include <StaticConstants.au3>
#include <SliderConstants.au3>
#include <File.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>

; -----------------------------------------------------------------------
; ---- Hardware & Protocol Constants ------------------------------------
; -----------------------------------------------------------------------
Global Const $TARGET_PID = "FF04"
Global Const $DEFAULT_VID = "4D44"
Global Const $NUM_POSITIONS = 8 ; 4 faders (0-3) + 4 switches (4-7)
Global Const $LED_POSITION  = 8 ; Dedicated front LED slot
Global Const $NUM_SLOTS     = 9 ; Total addressable slots

Global Const $SLOT_NAMES[$NUM_SLOTS] = [ _
    "Fader 1 (F1)", "Fader 2 (F2)", "Fader 3 (F3)", "Fader 4 (F4)", _
    "Switch 1 (SW1)", "Switch 2 (SW2)", "Switch 3 (SW3)", "Switch 4 (SW4)", _
    "Front LED" _
]

; Supported MIDI message types
Global Const $MSGTYPE_NAMES[7] = [ _
    "Control Change", "Note On", "Note Off", "Bend Change", _
    "Program Change", "Polyphonic Key Pressure", "Channel Pressure" _
]
Global Const $MSGTYPE_CODES[7] = [0xB0, 0x90, 0x80, 0xE0, 0xC0, 0xA0, 0xD0]
Global Const $MSGTYPE_DEFAULT_INDEX = 0 ; Default: "Control Change"

; Hardware Flash write sequence (confirmed from original firmware disassembly)
Global Const $FLASH_INDEX = 0x7F, $FLASH_SPEC = 0xAF, $FLASH_NORMAL = 0x7F, $FLASH_MULTI = 0x7F

; Vendor HID driver DLL
Global Const $VENDOR_DLL_NAME = "midiconfig.dll"
Global $g_sVendorDllPath = @ScriptDir & "\" & $VENDOR_DLL_NAME
Global $g_hVendorDll = 0

; Diagram image and configuration files
Global Const $DIAGRAM_IMAGE_NAME = "hardware.jpg"
Global $g_sSettingsFile = @ScriptDir & "\settings.ini"
Global $g_sProfilesDir  = @ScriptDir & "\profiles"

; WinMM Real-time MIDI In
Global $g_hWinMM = 0
Global $g_hMidiIn = 0
Global Const $CALLBACK_WINDOW = 0x00010000
Global Const $MM_MIM_DATA = 0x03C3
Global $g_aMidiInNames[64]
Global $g_aMidiInDevIds[64]
Global $g_iMidiInDevCount = 0
Global $g_aBoundCC[8] = [1, 2, 3, 4, 5, 6, 7, 8]

; -----------------------------------------------------------------------
; ---- Theme Color Palettes (Dark Studio / Light Studio) ----------------
; -----------------------------------------------------------------------
Global $g_bThemeDark = True

; Dark Studio Palette (High Contrast, OLED friendly)
Global Const $CLR_D_BG           = 0x14161D
Global Const $CLR_D_CARD         = 0x1E222D
Global Const $CLR_D_CARD_BORDER  = 0x384152
Global Const $CLR_D_TEXT_TITLE   = 0x60A5FA ; Electric Blue
Global Const $CLR_D_TEXT_MAIN    = 0xF1F5F9 ; Crisp Off-White
Global Const $CLR_D_TEXT_MUTED   = 0x94A3B8 ; Cool Slate
Global Const $CLR_D_TEXT_LIVE    = 0x38BDF8 ; Sky Blue Indicator
Global Const $CLR_D_INPUT_BG     = 0x0F1117
Global Const $CLR_D_INPUT_TXT    = 0xFFFFFF
Global Const $CLR_D_BTN_BG       = 0x2D3748
Global Const $CLR_D_BTN_TXT      = 0xFFFFFF
Global Const $CLR_D_ACCENT_BLUE  = 0x2563EB
Global Const $CLR_D_ACCENT_GREEN = 0x16A34A
Global Const $CLR_D_ACCENT_RED   = 0xDC2626
Global Const $CLR_D_LOG_BG       = 0x0B0D12
Global Const $CLR_D_LOG_TXT      = 0x4ADE80 ; Terminal Phosphor Green

; Light Studio Palette (Inspired by brushed white aluminum faceplate)
Global Const $CLR_L_BG           = 0xEEF2F6
Global Const $CLR_L_CARD         = 0xFFFFFF
Global Const $CLR_L_CARD_BORDER  = 0xCBD5E1
Global Const $CLR_L_TEXT_TITLE   = 0x1E40AF ; Deep Studio Blue
Global Const $CLR_L_TEXT_MAIN    = 0x1E293B ; Dark Charcoal
Global Const $CLR_L_TEXT_MUTED   = 0x64748B ; Slate
Global Const $CLR_L_TEXT_LIVE    = 0x0284C7 ; Blue Indicator
Global Const $CLR_L_INPUT_BG     = 0xF8FAFC
Global Const $CLR_L_INPUT_TXT    = 0x0F172A
Global Const $CLR_L_BTN_BG       = 0xE2E8F0
Global Const $CLR_L_BTN_TXT      = 0x1E293B
Global Const $CLR_L_ACCENT_BLUE  = 0x3B82F6
Global Const $CLR_L_ACCENT_GREEN = 0x22C55E
Global Const $CLR_L_ACCENT_RED   = 0xEF4444
Global Const $CLR_L_LOG_BG       = 0xF8FAFC
Global Const $CLR_L_LOG_TXT      = 0x15803D ; Dark Forest Green

; -----------------------------------------------------------------------
; ---- Runtime State & Data Model ---------------------------------------
; -----------------------------------------------------------------------
Global $g_bSimulation = True
Global $g_sDetectedVid = $DEFAULT_VID
Global $g_sConfirmedVid = ""
Global $g_sMachineId = $DEFAULT_VID & $TARGET_PID
Global $g_bDeviceConnected = False
Global $g_sDeviceHardwareId = ""
Global $g_sCurrentProfilePath = ""
Global $g_sCurrentProfileName = "Kontakt_Orchestral"
Global $g_bAutoScrollLog = True
Global $g_iCurrentMidiInDev = -1

; Slot data: [MsgTypeIndex, Channel, Value, Label, Comment]
Global $g_aSlots[$NUM_SLOTS][5]
InitializeSlotDefaults()

; Live MIDI values tracking (0-127)
Global $g_aLiveMidiVal[$NUM_SLOTS]
For $i = 0 To $NUM_SLOTS - 1
    $g_aLiveMidiVal[$i] = -1
Next

; -----------------------------------------------------------------------
; ---- GUI Control Handles ----------------------------------------------
; -----------------------------------------------------------------------
Global $g_hGui = 0

; Top bar controls
Global $g_idTitleLabel, $g_idBadgeDevice, $g_idBtnRefreshDev
Global $g_idCheckSim, $g_idBtnTheme, $g_idComboMidiIn

; 4 Channel strip controls
Global $g_idScribble[4]
Global $g_idGrpSwitch[4], $g_idGrpFade[4]
Global $g_idType[$NUM_SLOTS]
Global $g_idChan[$NUM_SLOTS]
Global $g_idVal[$NUM_SLOTS]
Global $g_idBtnSet[$NUM_SLOTS]
Global $g_idLiveLbl[$NUM_SLOTS]
Global $g_idSlider[4]

; Front LED controls
Global $g_idLedGroup, $g_idLedType, $g_idLedChan, $g_idLedSlider, $g_idLedPctLbl, $g_idBtnSetLed

; Global action buttons
Global $g_idBtnApplyAll, $g_idBtnFlashSave, $g_idBtnSetAllChan, $g_idBtnDiag

; Profiles management
Global $g_idProfGroup, $g_idComboProfiles, $g_idProfNameInput, $g_idBtnProfNew, $g_idBtnProfSave, $g_idBtnProfSaveAs

; Event log and MIDI monitor
Global $g_idLogGroup, $g_idLogEdit, $g_idCheckLogScroll, $g_idBtnClearLog

; Dynamic theme control registry
Global $g_aAllLabels[120],  $g_iLabelCount = 0
Global $g_aAllInputs[60],   $g_iInputCount = 0
Global $g_aAllButtons[60],  $g_iButtonCount = 0
Global $g_aAllGroups[30],   $g_iGroupCount = 0
Global $g_aAllChecks[10],   $g_iCheckCount = 0

; -----------------------------------------------------------------------
; ---- Startup Sequence -------------------------------------------------
; -----------------------------------------------------------------------
If Not FileExists($g_sProfilesDir) Then DirCreate($g_sProfilesDir)
LoadSettings()
BuildMainGUI()
ApplyThemeColors()
EnsureVendorDll()
OpenMidiWinMM()
DetectDevice()
PopulateMidiInPorts()

; Auto-load active or first profile
Local $sInitialProf = $g_sProfilesDir & "\" & $g_sCurrentProfileName & ".ini"
If FileExists($sInitialProf) Then
    LoadProfileFromFile($sInitialProf, False)
Else
    Local $aIniFiles = _FileListToArray($g_sProfilesDir, "*.ini", $FLTA_FILES)
    If IsArray($aIniFiles) And $aIniFiles[0] > 0 Then
        LoadProfileFromFile($g_sProfilesDir & "\" & $aIniFiles[1], False)
    EndIf
EndIf

MainLoop()

; =========================================================================
; DATA MODEL DEFAULTS
; =========================================================================
Func InitializeSlotDefaults()
    ; Faders (0-3): CC 1, 11, 7, 21 on Channel 1
    Local $aDefCC[4]   = [1, 11, 7, 21]
    Local $aDefLblF[4] = ["Modulation", "Expression", "Volume", "Vibrato"]
    For $i = 0 To 3
        $g_aSlots[$i][0] = 0 ; Control Change
        $g_aSlots[$i][1] = 1 ; Channel 1
        $g_aSlots[$i][2] = $aDefCC[$i]
        $g_aSlots[$i][3] = $aDefLblF[$i]
        $g_aSlots[$i][4] = ""
    Next

    ; Switches (4-7): CC 64, 65, 66, 67 on Channel 1
    Local $aDefSW[4]   = [64, 65, 66, 67]
    Local $aDefLblS[4] = ["Sustain", "Portamento", "Sostenuto", "Soft Pedal"]
    For $i = 0 To 3
        Local $sIdx = $i + 4
        $g_aSlots[$sIdx][0] = 0 ; Control Change
        $g_aSlots[$sIdx][1] = 1 ; Channel 1
        $g_aSlots[$sIdx][2] = $aDefSW[$i]
        $g_aSlots[$sIdx][3] = $aDefLblS[$i]
        $g_aSlots[$sIdx][4] = ""
    Next

    ; Front LED (8): Note On, Channel 1, Brightness 80
    $g_aSlots[$LED_POSITION][0] = 1 ; Note On
    $g_aSlots[$LED_POSITION][1] = 1
    $g_aSlots[$LED_POSITION][2] = 80
    $g_aSlots[$LED_POSITION][3] = "Front LED"
    $g_aSlots[$LED_POSITION][4] = "LED Brightness"
EndFunc

; =========================================================================
; GUI BUILDER (Hardware Mirror)
; =========================================================================
Func BuildMainGUI()
    Local $iW = 860, $iH = 820
    $g_hGui = GUICreate("MIDI F4W4 Studio Configurator", $iW, $iH, -1, -1, BitOR($WS_MINIMIZEBOX, $WS_CAPTION, $WS_POPUP, $WS_SYSMENU))
    GUISetFont(9, 400, 0, "Segoe UI")

    ; -------------------------------------------------------------------
    ; 1. TOP HEADER (Title, Device Status, Simulation, Theme, MIDI In)
    ; -------------------------------------------------------------------
    $g_idTitleLabel = GUICtrlCreateLabel("MIDI F4W4 STUDIO", 20, 12, 180, 24)
    GUICtrlSetFont(-1, 12, 700, 0, "Segoe UI")
    _RegLabel($g_idTitleLabel)

    $g_idBadgeDevice = GUICtrlCreateLabel("● OFFLINE", 205, 14, 185, 20, $SS_CENTER)
    GUICtrlSetFont(-1, 9, 600)
    GUICtrlSetColor(-1, 0xEF4444)

    $g_idBtnRefreshDev = GUICtrlCreateButton("Refresh", 395, 12, 75, 24)
    _RegBtn($g_idBtnRefreshDev)

    $g_idCheckSim = GUICtrlCreateCheckbox("Simulation", 480, 14, 85, 20)
    If $g_bSimulation Then GUICtrlSetState($g_idCheckSim, $GUI_CHECKED)
    _RegCheck($g_idCheckSim)

    $g_idBtnTheme = GUICtrlCreateButton($g_bThemeDark ? "Light Theme" : "Dark Theme", 575, 12, 85, 24)
    _RegBtn($g_idBtnTheme)

    Local $idMidiLbl = GUICtrlCreateLabel("MIDI In:", 668, 15, 45, 20)
    _RegLabel($idMidiLbl)

    $g_idComboMidiIn = GUICtrlCreateCombo("", 718, 12, 122, 120, $CBS_DROPDOWNLIST)
    _RegInput($g_idComboMidiIn)

    ; -------------------------------------------------------------------
    ; 2. PHYSICAL CHANNEL STRIPS 1 TO 4 (Hardware Mirror)
    ; -------------------------------------------------------------------
    Local $iColW = 195, $iGap = 10, $iStartX = 20
    For $col = 0 To 3
        Local $iX = $iStartX + $col * ($iColW + $iGap)
        Local $iFaderIdx = $col       ; 0, 1, 2, 3
        Local $iSwitchIdx = $col + 4   ; 4, 5, 6, 7

        ; Scribble Strip (Customizable Track / Parameter Name)
        Local $idTrackLbl = GUICtrlCreateLabel("Channel " & ($col + 1), $iX, 42, 60, 16)
        GUICtrlSetFont(-1, 8, 600)
        _RegLabel($idTrackLbl)

        $g_idScribble[$col] = GUICtrlCreateInput($g_aSlots[$iFaderIdx][3], $iX + 65, 40, $iColW - 65, 20)
        _RegInput($g_idScribble[$col])

        ; --- TOGGLE SWITCH UNIT (SWITCH 4-7) ---
        $g_idGrpSwitch[$col] = GUICtrlCreateGroup("SWITCH " & $iSwitchIdx & " (Toggle)", $iX, 64, $iColW, 145)
        _RegGroup($g_idGrpSwitch[$col])

        Local $idLblSwType = GUICtrlCreateLabel("Type:", $iX + 10, 84, 40, 18)
        _RegLabel($idLblSwType)
        $g_idType[$iSwitchIdx] = GUICtrlCreateCombo("", $iX + 55, 82, $iColW - 65, 100, $CBS_DROPDOWNLIST)
        PopulateTypeCombo($g_idType[$iSwitchIdx], $g_aSlots[$iSwitchIdx][0])
        _RegInput($g_idType[$iSwitchIdx])

        Local $idLblSwCh = GUICtrlCreateLabel("Channel:", $iX + 10, 112, 48, 18)
        _RegLabel($idLblSwCh)
        $g_idChan[$iSwitchIdx] = GUICtrlCreateInput($g_aSlots[$iSwitchIdx][1], $iX + 60, 110, 38, 20)
        _RegInput($g_idChan[$iSwitchIdx])

        Local $idLblSwVal = GUICtrlCreateLabel("CC/Note:", $iX + 104, 112, 50, 18)
        _RegLabel($idLblSwVal)
        $g_idVal[$iSwitchIdx] = GUICtrlCreateInput($g_aSlots[$iSwitchIdx][2], $iX + 155, 110, 30, 20)
        _RegInput($g_idVal[$iSwitchIdx])

        $g_idLiveLbl[$iSwitchIdx] = GUICtrlCreateLabel("Live: --", $iX + 6, 140, 88, 18)
        GUICtrlSetFont(-1, 8, 600)
        _RegLabel($g_idLiveLbl[$iSwitchIdx])

        $g_idBtnSet[$iSwitchIdx] = GUICtrlCreateButton("Set Switch", $iX + 96, 137, $iColW - 104, 22)
        _RegBtn($g_idBtnSet[$iSwitchIdx])
        GUICtrlCreateGroup("", -99, -99, 1, 1)

        ; --- VERTICAL FADER UNIT (0-3 / F1-F4) ---
        $g_idGrpFade[$col] = GUICtrlCreateGroup("FADER " & $iFaderIdx & " (F" & ($col + 1) & ")", $iX, 215, $iColW, 300)
        _RegGroup($g_idGrpFade[$col])

        Local $idLblFdType = GUICtrlCreateLabel("Type:", $iX + 10, 235, 40, 18)
        _RegLabel($idLblFdType)
        $g_idType[$iFaderIdx] = GUICtrlCreateCombo("", $iX + 55, 233, $iColW - 65, 100, $CBS_DROPDOWNLIST)
        PopulateTypeCombo($g_idType[$iFaderIdx], $g_aSlots[$iFaderIdx][0])
        _RegInput($g_idType[$iFaderIdx])

        Local $idLblFdCh = GUICtrlCreateLabel("Channel:", $iX + 10, 263, 48, 18)
        _RegLabel($idLblFdCh)
        $g_idChan[$iFaderIdx] = GUICtrlCreateInput($g_aSlots[$iFaderIdx][1], $iX + 60, 261, 38, 20)
        _RegInput($g_idChan[$iFaderIdx])

        Local $idLblFdVal = GUICtrlCreateLabel("CC Num:", $iX + 104, 263, 50, 18)
        _RegLabel($idLblFdVal)
        $g_idVal[$iFaderIdx] = GUICtrlCreateInput($g_aSlots[$iFaderIdx][2], $iX + 155, 261, 30, 20)
        _RegInput($g_idVal[$iFaderIdx])

        ; Vertical Graphic Fader Slider (Inverted: top = 127, bottom = 0)
        $g_idSlider[$iFaderIdx] = GUICtrlCreateSlider($iX + ($iColW - 36) / 2, 290, 36, 155, BitOR($TBS_VERT, $TBS_AUTOTICKS, $TBS_BOTH))
        GUICtrlSetLimit($g_idSlider[$iFaderIdx], 127, 0)
        GUICtrlSetData($g_idSlider[$iFaderIdx], 127) ; At bottom by default (0 value)

        ; Visual Scale markings
        Local $idScaleMax = GUICtrlCreateLabel("127", $iX + 15, 292, 25, 14)
        GUICtrlSetFont(-1, 7)
        _RegLabel($idScaleMax)

        Local $idScaleMid = GUICtrlCreateLabel("64", $iX + 18, 360, 25, 14)
        GUICtrlSetFont(-1, 7)
        _RegLabel($idScaleMid)

        Local $idScaleMin = GUICtrlCreateLabel("0", $iX + 22, 432, 20, 14)
        GUICtrlSetFont(-1, 7)
        _RegLabel($idScaleMin)

        $g_idLiveLbl[$iFaderIdx] = GUICtrlCreateLabel("Live: 0", $iX + 6, 455, 88, 18)
        GUICtrlSetFont(-1, 8, 600)
        _RegLabel($g_idLiveLbl[$iFaderIdx])

        $g_idBtnSet[$iFaderIdx] = GUICtrlCreateButton("Set Fader", $iX + 96, 452, $iColW - 104, 22)
        _RegBtn($g_idBtnSet[$iFaderIdx])
        GUICtrlCreateGroup("", -99, -99, 1, 1)
    Next

    ; -------------------------------------------------------------------
    ; 3. FRONT LED UNIT (Position 8)
    ; -------------------------------------------------------------------
    $g_idLedGroup = GUICtrlCreateGroup("FRONT LED (Position 8)", 20, 520, $iW - 40, 52)
    _RegGroup($g_idLedGroup)

    Local $idLedStateLbl = GUICtrlCreateLabel("State:", 35, 542, 35, 18)
    _RegLabel($idLedStateLbl)
    $g_idLedType = GUICtrlCreateCombo("", 72, 539, 110, 80, $CBS_DROPDOWNLIST)
    GUICtrlSetData($g_idLedType, "On (Note On)|Off (Note Off)", "On (Note On)")
    _RegInput($g_idLedType)

    Local $idLedChLbl = GUICtrlCreateLabel("Channel / Bank:", 192, 542, 85, 18)
    _RegLabel($idLedChLbl)
    $g_idLedChan = GUICtrlCreateInput("1", 280, 539, 35, 20)
    _RegInput($g_idLedChan)

    Local $idLedBrtLbl = GUICtrlCreateLabel("Brightness:", 330, 542, 65, 18)
    _RegLabel($idLedBrtLbl)

    $g_idLedSlider = GUICtrlCreateSlider(400, 538, 225, 26, $TBS_AUTOTICKS)
    GUICtrlSetLimit($g_idLedSlider, 127, 0)
    GUICtrlSetData($g_idLedSlider, $g_aSlots[$LED_POSITION][2])

    $g_idLedPctLbl = GUICtrlCreateLabel("80 (63%)", 635, 542, 75, 18)
    GUICtrlSetFont(-1, 8, 600)
    _RegLabel($g_idLedPctLbl)

    $g_idBtnSetLed = GUICtrlCreateButton("Set LED", 725, 537, 105, 24)
    _RegBtn($g_idBtnSetLed)
    GUICtrlCreateGroup("", -99, -99, 1, 1)

    ; -------------------------------------------------------------------
    ; 4. GLOBAL ACTION TOOLBAR & PROFILES MANAGER
    ; -------------------------------------------------------------------
    $g_idBtnApplyAll   = GUICtrlCreateButton("APPLY ALL (RAM)", 20, 578, 200, 30)
    GUICtrlSetFont(-1, 9, 700)
    _RegBtn($g_idBtnApplyAll)

    $g_idBtnFlashSave  = GUICtrlCreateButton("SAVE TO FLASH", 230, 578, 200, 30)
    GUICtrlSetFont(-1, 9, 700)
    _RegBtn($g_idBtnFlashSave)

    $g_idBtnSetAllChan = GUICtrlCreateButton("Set All Channels...", 440, 578, 180, 30)
    _RegBtn($g_idBtnSetAllChan)

    $g_idBtnDiag = GUICtrlCreateButton("Hardware Diagram", 630, 578, 210, 30)
    _RegBtn($g_idBtnDiag)

    ; Profiles Management Panel
    $g_idProfGroup = GUICtrlCreateGroup("User Profiles", 20, 613, $iW - 40, 50)
    _RegGroup($g_idProfGroup)

    Local $idProfLbl = GUICtrlCreateLabel("Profile:", 35, 632, 45, 18)
    _RegLabel($idProfLbl)

    $g_idComboProfiles = GUICtrlCreateCombo("", 85, 629, 260, 150, $CBS_DROPDOWNLIST)
    _RegInput($g_idComboProfiles)

    $g_idProfNameInput = GUICtrlCreateInput($g_sCurrentProfileName, 355, 629, 215, 20)
    _RegInput($g_idProfNameInput)

    $g_idBtnProfNew    = GUICtrlCreateButton("New", 580, 627, 75, 24)
    _RegBtn($g_idBtnProfNew)

    $g_idBtnProfSave   = GUICtrlCreateButton("Save", 665, 627, 75, 24)
    _RegBtn($g_idBtnProfSave)

    $g_idBtnProfSaveAs = GUICtrlCreateButton("Save As...", 750, 627, 90, 24)
    _RegBtn($g_idBtnProfSaveAs)
    GUICtrlCreateGroup("", -99, -99, 1, 1)

    ; -------------------------------------------------------------------
    ; 5. LIVE MIDI MONITOR & EVENT LOG
    ; -------------------------------------------------------------------
    $g_idLogGroup = GUICtrlCreateGroup("Live MIDI Monitor && Event Log", 20, 668, $iW - 40, 142)
    _RegGroup($g_idLogGroup)

    $g_idCheckLogScroll = GUICtrlCreateCheckbox("Auto-scroll", 620, 683, 100, 18)
    If $g_bAutoScrollLog Then GUICtrlSetState($g_idCheckLogScroll, $GUI_CHECKED)
    _RegCheck($g_idCheckLogScroll)

    $g_idBtnClearLog = GUICtrlCreateButton("Clear Log", 735, 681, 95, 20)
    _RegBtn($g_idBtnClearLog)

    $g_idLogEdit = GUICtrlCreateEdit("", 30, 703, $iW - 60, 98, BitOR($ES_READONLY, $ES_MULTILINE, $WS_VSCROLL))
    GUICtrlSetFont($g_idLogEdit, 8.5, 400, 0, "Consolas")
    GUICtrlSendMsg($g_idLogEdit, 0x00C5, 0x7FFFFFFF, 0) ; EM_SETLIMITTEXT to max capacity
    _RegInput($g_idLogEdit)
    GUICtrlCreateGroup("", -99, -99, 1, 1)

    ; Register Windows MM_MIM_DATA message
    GUIRegisterMsg($MM_MIM_DATA, "WM_MIM_DATA_HANDLER")

    PopulateProfilesCombo($g_sCurrentProfileName)

    GUISetState(@SW_SHOW, $g_hGui)
    RefreshSimBadge()
    LogMsg("MIDI F4W4 Studio Configurator initialized.")
EndFunc

; =========================================================================
; DYNAMIC THEME ENGINE (Dark / Light)
; =========================================================================
Func _RegLabel($id)
    $g_aAllLabels[$g_iLabelCount] = $id
    $g_iLabelCount += 1
EndFunc

Func _RegInput($id)
    $g_aAllInputs[$g_iInputCount] = $id
    $g_iInputCount += 1
EndFunc

Func _RegBtn($id)
    $g_aAllButtons[$g_iButtonCount] = $id
    $g_iButtonCount += 1
EndFunc

Func _RegGroup($id)
    $g_aAllGroups[$g_iGroupCount] = $id
    $g_iGroupCount += 1
EndFunc

Func _RegCheck($id)
    $g_aAllChecks[$g_iCheckCount] = $id
    $g_iCheckCount += 1
EndFunc

Func ApplyThemeColors()
    Local $cBg        = $g_bThemeDark ? $CLR_D_BG : $CLR_L_BG
    Local $cCard      = $g_bThemeDark ? $CLR_D_CARD : $CLR_L_CARD
    Local $cTextMain  = $g_bThemeDark ? $CLR_D_TEXT_MAIN : $CLR_L_TEXT_MAIN
    Local $cTextMuted = $g_bThemeDark ? $CLR_D_TEXT_MUTED : $CLR_L_TEXT_MUTED
    Local $cTextTitle = $g_bThemeDark ? $CLR_D_TEXT_TITLE : $CLR_L_TEXT_TITLE
    Local $cTextLive  = $g_bThemeDark ? $CLR_D_TEXT_LIVE : $CLR_L_TEXT_LIVE
    Local $cInputBg   = $g_bThemeDark ? $CLR_D_INPUT_BG : $CLR_L_INPUT_BG
    Local $cInputTxt  = $g_bThemeDark ? $CLR_D_INPUT_TXT : $CLR_L_INPUT_TXT
    Local $cBtnBg     = $g_bThemeDark ? $CLR_D_BTN_BG : $CLR_L_BTN_BG
    Local $cBtnTxt    = $g_bThemeDark ? $CLR_D_BTN_TXT : $CLR_L_BTN_TXT
    Local $cLogBg     = $g_bThemeDark ? $CLR_D_LOG_BG : $CLR_L_LOG_BG
    Local $cLogTxt    = $g_bThemeDark ? $CLR_D_LOG_TXT : $CLR_L_LOG_TXT

    GUISetBkColor($cBg, $g_hGui)

    ; Title header
    GUICtrlSetColor($g_idTitleLabel, $cTextTitle)
    GUICtrlSetBkColor($g_idTitleLabel, $cBg)

    ; Theme button text
    GUICtrlSetData($g_idBtnTheme, $g_bThemeDark ? "Light Theme" : "Dark Theme")

    ; Checkboxes (Disable UxTheme so colors render with maximum contrast)
    For $i = 0 To $g_iCheckCount - 1
        Local $id = $g_aAllChecks[$i]
        DllCall("uxtheme.dll", "int", "SetWindowTheme", "hwnd", GUICtrlGetHandle($id), "wstr", "", "wstr", "")
        GUICtrlSetColor($id, $cTextMain)
        GUICtrlSetBkColor($id, $cBg)
    Next

    ; Group boxes (Disable UxTheme so group caption text is bright and legible)
    For $i = 0 To $g_iGroupCount - 1
        Local $id = $g_aAllGroups[$i]
        DllCall("uxtheme.dll", "int", "SetWindowTheme", "hwnd", GUICtrlGetHandle($id), "wstr", "", "wstr", "")
        GUICtrlSetColor($id, $cTextTitle)
        GUICtrlSetBkColor($id, $cBg)
    Next

    ; Standard text labels
    For $i = 0 To $g_iLabelCount - 1
        Local $id = $g_aAllLabels[$i]
        GUICtrlSetColor($id, $cTextMain)
        GUICtrlSetBkColor($id, $cBg)
    Next

    ; Live labels (Electric Cyan in dark mode for extra visibility)
    For $i = 0 To $NUM_POSITIONS - 1
        GUICtrlSetColor($g_idLiveLbl[$i], $cTextLive)
        GUICtrlSetBkColor($g_idLiveLbl[$i], $cBg)
    Next
    GUICtrlSetColor($g_idLedPctLbl, $cTextLive)
    GUICtrlSetBkColor($g_idLedPctLbl, $cBg)

    ; Inputs and drop-down lists
    For $i = 0 To $g_iInputCount - 1
        Local $id = $g_aAllInputs[$i]
        If $id = $g_idLogEdit Then
            GUICtrlSetBkColor($id, $cLogBg)
            GUICtrlSetColor($id, $cLogTxt)
        Else
            GUICtrlSetBkColor($id, $cInputBg)
            GUICtrlSetColor($id, $cInputTxt)
        EndIf
    Next

    ; Action buttons
    For $i = 0 To $g_iButtonCount - 1
        Local $id = $g_aAllButtons[$i]
        If $id = $g_idBtnApplyAll Then
            GUICtrlSetBkColor($id, $g_bThemeDark ? $CLR_D_ACCENT_BLUE : $CLR_L_ACCENT_BLUE)
            GUICtrlSetColor($id, 0xFFFFFF)
        ElseIf $id = $g_idBtnFlashSave Then
            GUICtrlSetBkColor($id, $g_bThemeDark ? $CLR_D_ACCENT_RED : $CLR_L_ACCENT_RED)
            GUICtrlSetColor($id, 0xFFFFFF)
        Else
            GUICtrlSetBkColor($id, $cBtnBg)
            GUICtrlSetColor($id, $cBtnTxt)
        EndIf
    Next

    ; Vertical fader sliders
    For $i = 0 To 3
        GUICtrlSetBkColor($g_idSlider[$i], $cBg)
    Next
    GUICtrlSetBkColor($g_idLedSlider, $cBg)
EndFunc

Func ToggleTheme()
    $g_bThemeDark = Not $g_bThemeDark
    ApplyThemeColors()
    SaveSettings()
    LogMsg("Theme switched to: " & ($g_bThemeDark ? "Dark Studio" : "Light Studio"))
EndFunc

Func PopulateTypeCombo($idCombo, $iDefaultIndex)
    Local $sList = ""
    For $i = 0 To UBound($MSGTYPE_NAMES) - 1
        $sList &= $MSGTYPE_NAMES[$i] & "|"
    Next
    $sList = StringTrimRight($sList, 1)
    GUICtrlSetData($idCombo, $sList, $MSGTYPE_NAMES[$iDefaultIndex])
EndFunc

; =========================================================================
; DEVICE DETECTION & PORT MANAGEMENT
; =========================================================================
Func DetectDevice()
    LogMsg("Searching for USB device (PID " & $TARGET_PID & ")...")
    $g_bDeviceConnected = False
    $g_sDeviceHardwareId = ""

    Local $oWMI = ObjGet("winmgmts:\\.\root\cimv2")
    If IsObj($oWMI) Then
        Local $oItems = $oWMI.ExecQuery("SELECT * FROM Win32_PnPEntity WHERE DeviceID LIKE '%PID_" & $TARGET_PID & "%'")
        For $oItem In $oItems
            Local $sId = $oItem.DeviceID
            If StringInStr($sId, "PID_" & $TARGET_PID) Then
                $g_bDeviceConnected = True
                $g_sDeviceHardwareId = $sId
                Local $aMatch = StringRegExp($sId, "VID_([0-9A-Fa-f]{4})", 1)
                If IsArray($aMatch) Then
                    $g_sDetectedVid = StringUpper($aMatch[0])
                EndIf
                ExitLoop
            EndIf
        Next
    EndIf

    ; Vendor DLL verification
    If Not $g_bDeviceConnected And $g_hVendorDll <> 0 Then
        Local $aRet = DllCall($g_hVendorDll, "byte:cdecl", "compare_usb_device_id_mathing_multi", _
            "ushort", Number("0x" & $DEFAULT_VID), "ushort", Number("0x" & $TARGET_PID))
        If Not @error And $aRet[0] <> 0 Then
            $g_bDeviceConnected = True
            $g_sDetectedVid = $DEFAULT_VID
        EndIf
    EndIf

    If $g_sConfirmedVid <> "" Then $g_sDetectedVid = $g_sConfirmedVid
    $g_sMachineId = $g_sDetectedVid & $TARGET_PID

    If $g_bDeviceConnected Then
        GUICtrlSetData($g_idBadgeDevice, "● ONLINE (" & $g_sDetectedVid & ":" & $TARGET_PID & ")")
        GUICtrlSetColor($g_idBadgeDevice, 0x22C55E)
        LogMsg("Controller CONNECTED! VID=" & $g_sDetectedVid & ", MachineId=" & $g_sMachineId)
    Else
        GUICtrlSetData($g_idBadgeDevice, "● OFFLINE")
        GUICtrlSetColor($g_idBadgeDevice, 0xEF4444)
        LogMsg("No controller detected (PID " & $TARGET_PID & "). Simulation mode recommended.")
    EndIf
    RefreshSimBadge()
EndFunc

Func RefreshSimBadge()
    Local $sTitle = "MIDI F4W4 Studio Configurator"
    If $g_bSimulation Then
        $sTitle &= " [SIMULATION MODE]"
    Else
        $sTitle &= " [LIVE HARDWARE MODE]"
    EndIf
    WinSetTitle($g_hGui, "", $sTitle)
EndFunc

; =========================================================================
; REAL-TIME MIDI IN (WinMM API)
; =========================================================================
Func OpenMidiWinMM()
    If $g_hWinMM = 0 Then
        $g_hWinMM = DllOpen("winmm.dll")
    EndIf
EndFunc

Func PopulateMidiInPorts()
    If $g_hWinMM = 0 Then Return
    Local $aRet = DllCall($g_hWinMM, "uint", "midiInGetNumDevs")
    If @error Then Return
    Local $iDevCount = $aRet[0]

    $g_iMidiInDevCount = 0
    Local $sComboList = "None (Disabled)|"
    Local $tCaps = DllStructCreate("word wMid;word wPid;uint vDriverVersion;wchar szPname[32];dword dwSupport")
    Local $iAutoSelectIdx = -1

    For $i = 0 To $iDevCount - 1
        Local $aCapsRet = DllCall($g_hWinMM, "uint", "midiInGetDevCapsW", "uint_ptr", $i, "struct*", $tCaps, "uint", DllStructGetSize($tCaps))
        If Not @error And $aCapsRet[0] = 0 Then
            Local $sName = DllStructGetData($tCaps, "szPname")
            $g_aMidiInNames[$g_iMidiInDevCount] = $sName
            $g_aMidiInDevIds[$g_iMidiInDevCount] = $i
            $g_iMidiInDevCount += 1
            $sComboList &= $sName & "|"

            ; Priority 1: Match TARGET_PID (FF04), DEFAULT_VID (4D44), or F4W4
            If StringInStr($sName, $TARGET_PID) Or StringInStr($sName, $DEFAULT_VID) Or StringInStr($sName, "F4W4") Then
                $iAutoSelectIdx = $g_iMidiInDevCount - 1
            ; Priority 2: Fallback to USB or MIDI keyword if no exact match yet
            ElseIf $iAutoSelectIdx = -1 And (StringInStr($sName, "USB") Or StringInStr($sName, "MIDI")) Then
                $iAutoSelectIdx = $g_iMidiInDevCount - 1
            EndIf
        EndIf
    Next
    $sComboList = StringTrimRight($sComboList, 1)
    GUICtrlSetData($g_idComboMidiIn, "")
    GUICtrlSetData($g_idComboMidiIn, $sComboList)

    If $iAutoSelectIdx >= 0 Then
        GUICtrlSetData($g_idComboMidiIn, $g_aMidiInNames[$iAutoSelectIdx])
        SwitchMidiInDevice($g_aMidiInDevIds[$iAutoSelectIdx])
    Else
        GUICtrlSetData($g_idComboMidiIn, "None (Disabled)")
        CloseMidiIn()
    EndIf
EndFunc

Func SwitchMidiInDevice($iDevId)
    CloseMidiIn()
    If $iDevId < 0 Then
        LogMsg("MIDI In port closed.")
        Return
    EndIf

    OpenMidiWinMM()
    Local $aRet = DllCall($g_hWinMM, "uint", "midiInOpen", "handle*", 0, "uint", $iDevId, "hwnd", $g_hGui, "dword_ptr", 0, "dword", $CALLBACK_WINDOW)
    If @error Or $aRet[0] <> 0 Then
        LogMsg("WARNING: Failed to open MIDI In device #" & $iDevId)
        Return
    EndIf

    $g_hMidiIn = $aRet[1]
    DllCall($g_hWinMM, "uint", "midiInStart", "handle", $g_hMidiIn)
    $g_iCurrentMidiInDev = $iDevId
    LogMsg("MIDI In port opened (" & $g_aMidiInNames[_GetMidiDevNameIndex($iDevId)] & " - Dev " & $iDevId & "). Real-time monitoring active!")
EndFunc

Func _GetMidiDevNameIndex($iDevId)
    For $k = 0 To $g_iMidiInDevCount - 1
        If $g_aMidiInDevIds[$k] = $iDevId Then Return $k
    Next
    Return 0
EndFunc

Func CloseMidiIn()
    If $g_hMidiIn <> 0 Then
        DllCall($g_hWinMM, "uint", "midiInStop", "handle", $g_hMidiIn)
        DllCall($g_hWinMM, "uint", "midiInReset", "handle", $g_hMidiIn)
        DllCall($g_hWinMM, "uint", "midiInClose", "handle", $g_hMidiIn)
        $g_hMidiIn = 0
        $g_iCurrentMidiInDev = -1
    EndIf
EndFunc

Func WM_MIM_DATA_HANDLER($hWnd, $iMsg, $wParam, $lParam)
    If $iMsg <> $MM_MIM_DATA Then Return $GUI_RUNDEFMSG

    Local $iStatus = BitAND($lParam, 0xFF)
    Local $iData1  = BitAND(BitShift($lParam, 8), 0xFF)  ; CC num or note
    Local $iData2  = BitAND(BitShift($lParam, 16), 0xFF) ; Value 0-127

    Local $iTypeNibble = BitAND($iStatus, 0xF0)
    Local $iChannel    = BitAND($iStatus, 0x0F) + 1

    Local $iTargetSlot = -1

    ; --- NIVEAU 1 : Correspondance exacte avec le profil actif (Type, Canal, CC/Note) ---
    For $i = 0 To 7
        Local $iSlotType = $MSGTYPE_CODES[$g_aSlots[$i][0]]
        Local $iSlotChan = $g_aSlots[$i][1]
        Local $iSlotVal  = $g_aSlots[$i][2]
        If $iTypeNibble = $iSlotType And $iChannel = $iSlotChan And $iData1 = $iSlotVal Then
            $iTargetSlot = $i
            ExitLoop
        EndIf
    Next

    ; --- NIVEAU 2 : Correspondance par CC/Note dans le profil actif (canal ignore) ---
    If $iTargetSlot = -1 Then
        For $i = 0 To 7
            Local $iSlotType = $MSGTYPE_CODES[$g_aSlots[$i][0]]
            Local $iSlotVal  = $g_aSlots[$i][2]
            If $iTypeNibble = $iSlotType And $iData1 = $iSlotVal Then
                $iTargetSlot = $i
                ExitLoop
            EndIf
        Next
    EndIf

    ; --- NIVEAU 3 : Correspondance Materielle Usine (controleur redemarre ou RAM perdue) ---
    ; Faders physiques 1 a 4 = CC 1 a 4. Switches 1 a 4 = CC 5 a 8.
    If $iTargetSlot = -1 And $iTypeNibble = 0xB0 Then
        If $iData1 >= 1 And $iData1 <= 4 Then
            $iTargetSlot = $iData1 - 1 ; Faders 0, 1, 2, 3
        ElseIf $iData1 >= 5 And $iData1 <= 8 Then
            $iTargetSlot = $iData1 - 1 ; Switches 4, 5, 6, 7
        EndIf
    EndIf

    ; --- NIVEAU 4 : Table de liaison dynamique en direct ---
    If $iTargetSlot = -1 Then
        For $i = 0 To 7
            If $g_aBoundCC[$i] = $iData1 Then
                $iTargetSlot = $i
                ExitLoop
            EndIf
        Next
    EndIf

    ; Si la tranche est identifiee, on anime l'interface en direct !
    If $iTargetSlot >= 0 Then
        $g_aLiveMidiVal[$iTargetSlot] = $iData2
        $g_aBoundCC[$iTargetSlot] = $iData1

        If $iTargetSlot <= 3 Then
            ; Faders 0-3: animer le slider vertical (inverse: 127 - valeur)
            GUICtrlSetData($g_idSlider[$iTargetSlot], 127 - $iData2)
            GUICtrlSetData($g_idLiveLbl[$iTargetSlot], "Live: " & $iData2 & " [CC " & $iData1 & "]")
        Else
            ; Switches 4-7: afficher valeur et CC
            GUICtrlSetData($g_idLiveLbl[$iTargetSlot], "Live: " & $iData2 & " [CC " & $iData1 & "]")
        EndIf

        Local $sName = ($g_aSlots[$iTargetSlot][3] <> "") ? $g_aSlots[$iTargetSlot][3] : $SLOT_NAMES[$iTargetSlot]
        LogMsg("[MIDI IN] " & $sName & " (Pos " & $iTargetSlot & ") -> CC " & $iData1 & " = " & $iData2 & " (Ch " & $iChannel & ")")
        Return $GUI_RUNDEFMSG
    EndIf

    LogMsg("[MIDI IN] Ch " & $iChannel & " | Status: " & Hex($iStatus, 2) & " | D1: " & $iData1 & " | D2: " & $iData2)
    Return $GUI_RUNDEFMSG
EndFunc

; =========================================================================
; VENDOR HID TRANSPORT (midiconfig.dll)
; =========================================================================
Func EnsureVendorDll()
    If Not FileExists($g_sVendorDllPath) Then
        LogMsg("WARNING: " & $VENDOR_DLL_NAME & " not found in " & @ScriptDir)
        Return 0
    EndIf
    If $g_hVendorDll = 0 Then
        $g_hVendorDll = DllOpen($g_sVendorDllPath)
        If @error Or $g_hVendorDll = -1 Then
            LogMsg("ERROR: Failed to load " & $VENDOR_DLL_NAME)
            $g_hVendorDll = 0
            Return 0
        EndIf
    EndIf
    Return $g_hVendorDll
EndFunc

Func SendVendorCommand($iIndex, $iSpec, $iNormal, $iMulti, $sLabel = "")
    Local $sDesc = "idx=" & Hex($iIndex, 2) & " spec=" & Hex($iSpec, 2) & _
                   " norm=" & Hex($iNormal, 2) & " multi=" & Hex($iMulti, 2)

    If $g_bSimulation Then
        LogMsg("[SIMULATION] " & $sLabel & " -> " & $sDesc)
        Return True
    EndIf

    If Not $g_bDeviceConnected Then
        LogMsg("ERROR: Controller not detected. Action aborted for " & $sLabel)
        Return False
    EndIf

    Local $hDll = EnsureVendorDll()
    If $hDll = 0 Then Return False

    Local $aRet = DllCall($hDll, "int:cdecl", "hiddirect_main", _
        "str", $g_sMachineId, "byte", $iIndex, "byte", $iSpec, "byte", $iNormal, "byte", $iMulti)
    If @error Then
        LogMsg("ERROR: DllCall failed (@error=" & @error & ") for " & $sLabel)
        Return False
    EndIf

    LogMsg("SENT: " & $sLabel & " (" & $sDesc & ") -> ret=" & $aRet[0])
    Return True
EndFunc

; =========================================================================
; ACTIONS (SET, APPLY ALL, FLASH SAVE)
; =========================================================================
Func ReadSlotFromUI($iSlot)
    Local $iTypeIdx = MsgTypeNameToIndex(GUICtrlRead($g_idType[$iSlot]))
    If $iTypeIdx = -1 Then $iTypeIdx = 0

    Local $iChan = Number(GUICtrlRead($g_idChan[$iSlot]))
    Local $iVal  = Number(GUICtrlRead($g_idVal[$iSlot]))

    If $iChan < 1 Or $iChan > 16 Then
        MsgBox($MB_ICONWARNING, "Validation Error", "MIDI Channel must be between 1 and 16.")
        Return False
    EndIf
    If $iVal < 0 Or $iVal > 127 Then
        MsgBox($MB_ICONWARNING, "Validation Error", "CC / Note number must be between 0 and 127.")
        Return False
    EndIf

    $g_aSlots[$iSlot][0] = $iTypeIdx
    $g_aSlots[$iSlot][1] = $iChan
    $g_aSlots[$iSlot][2] = $iVal
    If $iSlot <= 3 Then
        $g_aSlots[$iSlot][3] = GUICtrlRead($g_idScribble[$iSlot])
    EndIf
    Return True
EndFunc

Func ApplySingleSlot($iSlot)
    If Not ReadSlotFromUI($iSlot) Then Return

    Local $iMsgCode = $MSGTYPE_CODES[$g_aSlots[$iSlot][0]]
    Local $iChan    = $g_aSlots[$iSlot][1]
    Local $iVal     = $g_aSlots[$iSlot][2]

    Local $iSpec   = BitOR($iMsgCode, $iChan - 1)
    Local $iNormal = BitAND($iVal, 0x7F)
    Local $iMulti  = $iNormal
    Local $iIdx    = BitAND($iSlot, 0x7F)

    Local $sLbl = $SLOT_NAMES[$iSlot]
    If $iSlot <= 3 And $g_aSlots[$iSlot][3] <> "" Then $sLbl &= " [" & $g_aSlots[$iSlot][3] & "]"

    SendVendorCommand($iIdx, $iSpec, $iNormal, $iMulti, "Set " & $sLbl)
    If $iSlot <= 7 Then
        $g_aBoundCC[$iSlot] = $iVal
        GUICtrlSetData($g_idLiveLbl[$iSlot], "Live: -- [CC " & $iVal & "]")
    EndIf
EndFunc

Func ApplyAllSlots()
    LogMsg("=== APPLYING ALL SETTINGS TO CONTROLLER (9 slots) ===")
    For $i = 0 To $NUM_SLOTS - 1
        If $i = $LED_POSITION Then
            ReadLedFromUI()
        Else
            ReadSlotFromUI($i)
        EndIf

        Local $iMsgCode = $MSGTYPE_CODES[$g_aSlots[$i][0]]
        Local $iChan    = $g_aSlots[$i][1]
        Local $iVal     = $g_aSlots[$i][2]

        Local $iSpec   = BitOR($iMsgCode, $iChan - 1)
        Local $iNormal = BitAND($iVal, 0x7F)
        Local $iMulti  = $iNormal
        Local $iIdx    = BitAND($i, 0x7F)

        Local $sLbl = $SLOT_NAMES[$i]
        If $i <= 3 And $g_aSlots[$i][3] <> "" Then $sLbl &= " (" & $g_aSlots[$i][3] & ")"

        SendVendorCommand($iIdx, $iSpec, $iNormal, $iMulti, "Pos " & $i & ": " & $sLbl)
        If $i <= 7 Then
            $g_aBoundCC[$i] = $iVal
            GUICtrlSetData($g_idLiveLbl[$i], "Live: -- [CC " & $iVal & "]")
        EndIf
        Sleep(25) ; Safe transmission delay between packets
    Next
    LogMsg("=== ALL SLOTS SUCCESSFULLY SENT TO RAM ===")
    MsgBox($MB_ICONINFORMATION, "Configuration Applied", _
        "All 8 controls and the LED were sent to the controller (RAM)." & @CRLF & _
        "To preserve these settings across power cycles, click 'SAVE TO FLASH'.")
EndFunc

Func SaveToFlash()
    Local $sMsg = "You are about to flash this configuration into the controller's permanent non-volatile memory." & @CRLF & @CRLF & _
                  "Hardware command: 7F AF 7F 7F" & @CRLF & _
                  "Target MachineId: " & $g_sMachineId & @CRLF & @CRLF & _
                  "These settings will persist across power cycles and USB reconnects." & @CRLF & @CRLF & _
                  "Do you want to proceed with flashing?"
    If MsgBox(BitOR($MB_YESNO, $MB_ICONQUESTION), "Confirm Hardware Flash Write", $sMsg) <> $IDYES Then
        LogMsg("Flash write cancelled by user.")
        Return
    EndIf

    LogMsg(">>> SENDING PERMANENT FLASH COMMAND (7F AF 7F 7F)...")
    Local $bOk = SendVendorCommand($FLASH_INDEX, $FLASH_SPEC, $FLASH_NORMAL, $FLASH_MULTI, "FLASH PERMANENT SAVE")
    If $bOk Then
        LogMsg(">>> FLASH COMMAND SENT SUCCESSFULLY!")
        MsgBox($MB_ICONINFORMATION, "Hardware Flash Write Successful", "The configuration was successfully written to the controller's permanent memory.")
    EndIf
EndFunc

Func ReadLedFromUI()
    Local $sMode = GUICtrlRead($g_idLedType)
    $g_aSlots[$LED_POSITION][0] = StringInStr($sMode, "Off") ? 2 : 1 ; Note On or Note Off
    $g_aSlots[$LED_POSITION][1] = Number(GUICtrlRead($g_idLedChan))
    $g_aSlots[$LED_POSITION][2] = GUICtrlRead($g_idLedSlider)
EndFunc

Func ApplyLedSlot()
    ReadLedFromUI()
    Local $iMsgCode = $MSGTYPE_CODES[$g_aSlots[$LED_POSITION][0]]
    Local $iChan    = $g_aSlots[$LED_POSITION][1]
    Local $iVal     = $g_aSlots[$LED_POSITION][2]

    Local $iSpec   = BitOR($iMsgCode, $iChan - 1)
    Local $iNormal = BitAND($iVal, 0x7F)
    Local $iMulti  = $iNormal
    Local $iIdx    = BitAND($LED_POSITION, 0x7F)

    SendVendorCommand($iIdx, $iSpec, $iNormal, $iMulti, "Set Front LED")
EndFunc

Func SetAllChannels()
    Local $sChan = InputBox("Set Global MIDI Channel", "Enter MIDI Channel for all 8 controls (1 to 16):", "1", "", 260, 130)
    If @error Then Return
    Local $iCh = Number($sChan)
    If $iCh < 1 Or $iCh > 16 Then
        MsgBox($MB_ICONERROR, "Error", "MIDI Channel must be between 1 and 16.")
        Return
    EndIf

    For $i = 0 To 7
        GUICtrlSetData($g_idChan[$i], $iCh)
        $g_aSlots[$i][1] = $iCh
    Next
    GUICtrlSetData($g_idLedChan, $iCh)
    $g_aSlots[$LED_POSITION][1] = $iCh
    LogMsg("All controls updated to MIDI Channel " & $iCh)
EndFunc

; =========================================================================
; PROFILES MANAGEMENT (profiles\ Subfolder & 1-Click Dropdown)
; =========================================================================
Func PopulateProfilesCombo($sSelectName = "")
    If Not FileExists($g_sProfilesDir) Then DirCreate($g_sProfilesDir)
    Local $aFiles = _FileListToArray($g_sProfilesDir, "*.ini", $FLTA_FILES)
    Local $sList = ""
    If IsArray($aFiles) Then
        For $i = 1 To $aFiles[0]
            Local $sBase = StringRegExpReplace($aFiles[$i], "(?i)\.ini$", "")
            $sList &= $sBase & "|"
        Next
    EndIf
    $sList = StringTrimRight($sList, 1)

    If $sSelectName = "" Then
        If IsArray($aFiles) And $aFiles[0] > 0 Then
            $sSelectName = StringRegExpReplace($aFiles[1], "(?i)\.ini$", "")
        EndIf
    EndIf

    GUICtrlSetData($g_idComboProfiles, "")
    GUICtrlSetData($g_idComboProfiles, $sList, $sSelectName)
EndFunc

Func LoadProfileFromFile($sFile, $bShowAlert = True)
    If Not FileExists($sFile) Then Return

    Local $sTarget = IniRead($sFile, "Meta", "Target", "")
    If $sTarget <> "" And $sTarget <> $TARGET_PID Then
        If MsgBox(BitOR($MB_YESNO, $MB_ICONWARNING), "Profile Mismatch", _
            "This profile targets '" & $sTarget & "' but this tool is configured for PID " & $TARGET_PID & ". Load anyway?") <> $IDYES Then Return
    EndIf

    For $i = 0 To $NUM_SLOTS - 1
        Local $sSec = "Pos" & $i
        Local $sTypeStr = IniRead($sFile, $sSec, "MsgType", "Control Change")
        Local $iTypeIdx = MsgTypeNameToIndex($sTypeStr)
        If $iTypeIdx = -1 Then $iTypeIdx = 0

        $g_aSlots[$i][0] = $iTypeIdx
        $g_aSlots[$i][1] = Number(IniRead($sFile, $sSec, "Channel", "1"))
        $g_aSlots[$i][2] = Number(IniRead($sFile, $sSec, "Value", "0"))
        $g_aSlots[$i][3] = IniRead($sFile, $sSec, "Label", "")
        $g_aSlots[$i][4] = IniRead($sFile, $sSec, "Comment", "")

        If $i <= 7 Then
            GUICtrlSetData($g_idType[$i], $MSGTYPE_NAMES[$g_aSlots[$i][0]])
            GUICtrlSetData($g_idChan[$i], $g_aSlots[$i][1])
            GUICtrlSetData($g_idVal[$i],  $g_aSlots[$i][2])
            $g_aBoundCC[$i] = $g_aSlots[$i][2]
            GUICtrlSetData($g_idLiveLbl[$i], "Live: -- [CC " & $g_aSlots[$i][2] & "]")
            If $i <= 3 Then
                GUICtrlSetData($g_idScribble[$i], $g_aSlots[$i][3])
                GUICtrlSetData($g_idSlider[$i], 127) ; default bottom position
            EndIf
        Else
            ; LED
            Local $sLedMode = ($g_aSlots[$LED_POSITION][0] = 2) ? "Off (Note Off)" : "On (Note On)"
            GUICtrlSetData($g_idLedType, $sLedMode)
            GUICtrlSetData($g_idLedChan, $g_aSlots[$LED_POSITION][1])
            GUICtrlSetData($g_idLedSlider, $g_aSlots[$LED_POSITION][2])
            UpdateLedPctDisplay($g_aSlots[$LED_POSITION][2])
        EndIf
    Next

    $g_sCurrentProfilePath = $sFile
    Local $sBase = StringRegExpReplace($sFile, "^.*\\|(?i)\.ini$", "")
    Local $sName = IniRead($sFile, "Meta", "ProfileName", $sBase)
    $g_sCurrentProfileName = $sName
    GUICtrlSetData($g_idProfNameInput, $sName)
    GUICtrlSetData($g_idComboProfiles, $sBase)
    LogMsg("Profile loaded: " & $sFile)
    If $bShowAlert Then MsgBox($MB_ICONINFORMATION, "Profile Loaded", "Profile '" & $sName & "' loaded into interface.")
EndFunc

Func SaveProfile($bSaveAs = False)
    For $i = 0 To 7
        ReadSlotFromUI($i)
    Next
    ReadLedFromUI()

    Local $sName = GUICtrlRead($g_idProfNameInput)
    If $sName = "" Then $sName = "Custom_Profile"

    Local $sFile = $g_sCurrentProfilePath
    If $bSaveAs Or $sFile = "" Then
        Local $sNewName = InputBox("Save Profile As", "Enter a name for the new profile:", $sName, "", 280, 130)
        If @error Or $sNewName = "" Then Return
        $sName = $sNewName
        $sFile = $g_sProfilesDir & "\" & $sName & ".ini"
    EndIf

    IniWrite($sFile, "Meta", "ProfileName", $sName)
    IniWrite($sFile, "Meta", "Target", $TARGET_PID)

    For $i = 0 To $NUM_SLOTS - 1
        Local $sSec = "Pos" & $i
        IniWrite($sFile, $sSec, "MsgType", $MSGTYPE_NAMES[$g_aSlots[$i][0]])
        IniWrite($sFile, $sSec, "Channel", $g_aSlots[$i][1])
        IniWrite($sFile, $sSec, "Value",   $g_aSlots[$i][2])
        IniWrite($sFile, $sSec, "Label",   $g_aSlots[$i][3])
        IniWrite($sFile, $sSec, "Comment", $g_aSlots[$i][4])
    Next

    $g_sCurrentProfilePath = $sFile
    $g_sCurrentProfileName = $sName
    PopulateProfilesCombo($sName)
    LogMsg("Profile saved: " & $sFile)
    MsgBox($MB_ICONINFORMATION, "Profile Saved", "Profile '" & $sName & "' saved successfully.")
EndFunc

Func NewProfile()
    InitializeSlotDefaults()
    For $i = 0 To 7
        GUICtrlSetData($g_idType[$i], $MSGTYPE_NAMES[$g_aSlots[$i][0]])
        GUICtrlSetData($g_idChan[$i], $g_aSlots[$i][1])
        GUICtrlSetData($g_idVal[$i],  $g_aSlots[$i][2])
        If $i <= 3 Then
            GUICtrlSetData($g_idScribble[$i], $g_aSlots[$i][3])
            GUICtrlSetData($g_idSlider[$i], 127)
            GUICtrlSetData($g_idLiveLbl[$i], "Live: --")
        EndIf
    Next
    GUICtrlSetData($g_idLedType, "On (Note On)")
    GUICtrlSetData($g_idLedChan, 1)
    GUICtrlSetData($g_idLedSlider, 80)
    UpdateLedPctDisplay(80)

    $g_sCurrentProfilePath = ""
    $g_sCurrentProfileName = "(new, unsaved)"
    GUICtrlSetData($g_idProfNameInput, $g_sCurrentProfileName)
    LogMsg("New blank profile created.")
EndFunc

; =========================================================================
; UTILITY & LOGGING FUNCTIONS
; =========================================================================
Func UpdateLedPctDisplay($iVal)
    Local $iPct = Round(($iVal / 127) * 100)
    GUICtrlSetData($g_idLedPctLbl, $iVal & " (" & $iPct & "%)")
EndFunc

Func MsgTypeNameToIndex($sName)
    For $i = 0 To UBound($MSGTYPE_NAMES) - 1
        If $MSGTYPE_NAMES[$i] = $sName Then Return $i
    Next
    Return -1
EndFunc

Func LogMsg($sText)
    Local Const $iMaxLogLines = 500
    Local Const $iTrimLogLines = 100

    ; Circular buffer: prune oldest lines if count exceeds limit
    Local $iLines = GUICtrlSendMsg($g_idLogEdit, 0x00BA, 0, 0) ; EM_GETLINECOUNT
    If $iLines > $iMaxLogLines Then
        Local $iCharEnd = GUICtrlSendMsg($g_idLogEdit, 0x00BB, $iTrimLogLines, 0) ; EM_LINEINDEX of line 100
        If $iCharEnd > 0 Then
            GUICtrlSendMsg($g_idLogEdit, 0x00B1, 0, $iCharEnd) ; EM_SETSEL 0 to line 100
            GUICtrlSendMsg($g_idLogEdit, 0x00C2, False, "")     ; EM_REPLACESEL delete oldest lines
        EndIf
    EndIf

    Local $sTimestamp = "[" & @HOUR & ":" & @MIN & ":" & @SEC & "] "
    Local $sFull = $sTimestamp & $sText & @CRLF
    ; Fast append to edit control without re-reading whole buffer
    GUICtrlSendMsg($g_idLogEdit, 0x00B1, -1, -1) ; EM_SETSEL to end
    GUICtrlSendMsg($g_idLogEdit, 0x00C2, False, $sFull) ; EM_REPLACESEL
    If $g_bAutoScrollLog Then
        GUICtrlSendMsg($g_idLogEdit, 0x00B7, 0, 0)         ; EM_SCROLLCARET
    EndIf
EndFunc

Func ShowDiagram()
    Local $sPath = @ScriptDir & "\" & $DIAGRAM_IMAGE_NAME
    If Not FileExists($sPath) Then
        MsgBox($MB_ICONINFORMATION, "Diagram Missing", "Image '" & $DIAGRAM_IMAGE_NAME & "' was not found in the application directory.")
        Return
    EndIf
    ShellExecute($sPath)
EndFunc

Func LoadSettings()
    If Not FileExists($g_sSettingsFile) Then Return
    $g_bSimulation = (IniRead($g_sSettingsFile, "Settings", "Simulation", "1") = "1")
    $g_sConfirmedVid = IniRead($g_sSettingsFile, "Settings", "ConfirmedVID", "")
    $g_bThemeDark = (IniRead($g_sSettingsFile, "Settings", "Theme", "dark") = "dark")
EndFunc

Func SaveSettings()
    IniWrite($g_sSettingsFile, "Settings", "Simulation", $g_bSimulation ? "1" : "0")
    IniWrite($g_sSettingsFile, "Settings", "ConfirmedVID", $g_sConfirmedVid)
    IniWrite($g_sSettingsFile, "Settings", "Theme", $g_bThemeDark ? "dark" : "light")
EndFunc

Func _ShutdownApp()
    SaveSettings()
    CloseMidiIn()
    If $g_hWinMM <> 0 Then DllClose($g_hWinMM)
    If $g_hVendorDll <> 0 Then DllClose($g_hVendorDll)
EndFunc

; =========================================================================
; MAIN EVENT LOOP
; =========================================================================
Func MainLoop()
    While 1
        Local $msg = GUIGetMsg()
        If $msg = 0 Then ContinueLoop

        Switch $msg
            Case $GUI_EVENT_CLOSE
                _ShutdownApp()
                Exit

            Case $g_idBtnRefreshDev
                DetectDevice()
                PopulateMidiInPorts()

            Case $g_idCheckSim
                $g_bSimulation = (GUICtrlRead($g_idCheckSim) = $GUI_CHECKED)
                RefreshSimBadge()
                SaveSettings()
                LogMsg("Simulation Mode: " & ($g_bSimulation ? "ENABLED (safe preview, no data sent)" : "DISABLED (Live hardware write enabled!)"))

            Case $g_idBtnTheme
                ToggleTheme()

            Case $g_idComboMidiIn
                Local $sSel = GUICtrlRead($g_idComboMidiIn)
                If $sSel = "None (Disabled)" Or $sSel = "" Then
                    CloseMidiIn()
                Else
                    For $k = 0 To $g_iMidiInDevCount - 1
                        If $g_aMidiInNames[$k] = $sSel Then
                            SwitchMidiInDevice($g_aMidiInDevIds[$k])
                            ExitLoop
                        EndIf
                    Next
                EndIf

            Case $g_idComboProfiles
                Local $sSelProfile = GUICtrlRead($g_idComboProfiles)
                If $sSelProfile <> "" Then
                    Local $sFile = $g_sProfilesDir & "\" & $sSelProfile & ".ini"
                    If FileExists($sFile) Then
                        LoadProfileFromFile($sFile, False)
                    EndIf
                EndIf

            Case $g_idBtnDiag
                ShowDiagram()

            Case $g_idBtnApplyAll
                ApplyAllSlots()

            Case $g_idBtnFlashSave
                SaveToFlash()

            Case $g_idBtnSetAllChan
                SetAllChannels()

            Case $g_idBtnSetLed
                ApplyLedSlot()

            Case $g_idLedSlider
                Local $iVal = GUICtrlRead($g_idLedSlider)
                UpdateLedPctDisplay($iVal)

            ; Single-slot Set buttons (0 to 7)
            Case $g_idBtnSet[0], $g_idBtnSet[1], $g_idBtnSet[2], $g_idBtnSet[3], _
                 $g_idBtnSet[4], $g_idBtnSet[5], $g_idBtnSet[6], $g_idBtnSet[7]
                For $s = 0 To 7
                    If $msg = $g_idBtnSet[$s] Then
                        ApplySingleSlot($s)
                        ExitLoop
                    EndIf
                Next

            ; Click on Live label to sync detected hardware CC into target box
            Case $g_idLiveLbl[0], $g_idLiveLbl[1], $g_idLiveLbl[2], $g_idLiveLbl[3], _
                 $g_idLiveLbl[4], $g_idLiveLbl[5], $g_idLiveLbl[6], $g_idLiveLbl[7]
                For $s = 0 To 7
                    If $msg = $g_idLiveLbl[$s] Then
                        If $g_aBoundCC[$s] > 0 Then
                            GUICtrlSetData($g_idVal[$s], $g_aBoundCC[$s])
                            LogMsg("Synced " & $SLOT_NAMES[$s] & " target CC to detected hardware CC " & $g_aBoundCC[$s])
                        EndIf
                        ExitLoop
                    EndIf
                Next

            ; Vertical sliders moved by user
            Case $g_idSlider[0], $g_idSlider[1], $g_idSlider[2], $g_idSlider[3]
                For $f = 0 To 3
                    If $msg = $g_idSlider[$f] Then
                        Local $iMidiVal = 127 - GUICtrlRead($g_idSlider[$f])
                        GUICtrlSetData($g_idLiveLbl[$f], "Val: " & $iMidiVal)
                        ExitLoop
                    EndIf
                Next

            ; Profiles management
            Case $g_idBtnProfNew
                NewProfile()

            Case $g_idBtnProfSave
                SaveProfile(False)

            Case $g_idBtnProfSaveAs
                SaveProfile(True)

            ; Logs
            Case $g_idCheckLogScroll
                $g_bAutoScrollLog = (GUICtrlRead($g_idCheckLogScroll) = $GUI_CHECKED)

            Case $g_idBtnClearLog
                GUICtrlSetData($g_idLogEdit, "")
        EndSwitch
    WEnd
EndFunc
