SetCompressor /SOLID lzma
Unicode True
CRCCheck on
RequestExecutionLevel admin

!ifndef PAYLOADDIR
  !define PAYLOADDIR "C:\RadioBot\payload-official"
!endif

!ifndef OUTFILE
  !define OUTFILE "C:\RadioBot\RadioBot-setup.exe"
!endif

Name "RadioBot"
OutFile "${OUTFILE}"
; Match the original installer default location.
InstallDir "$DESKTOP\RadioBot"
InstallDirRegKey HKLM "Software\RadioBot" "InstallDir"
Icon "${PAYLOADDIR}\shoutirc.ico"

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"

!define MUI_ICON "${PAYLOADDIR}\shoutirc.ico"
!define MUI_ABORTWARNING

Var RunWizard
Var hConfigWizard

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
Page custom ConfigPage ConfigPageLeave
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function ConfigPage
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == "error"
    Abort
  ${EndIf}

  !insertmacro MUI_HEADER_TEXT "Configuration" "RadioBot needs an ircbot.conf to start"

  ${NSD_CreateLabel} 0 10 100% 50 "RadioBot needs an ircbot.conf file to run.$\n$\nYou can create one now, import an existing one, or configure it later. Check the box below to run the configuration wizard after the files are copied."
  Pop $0

  ${NSD_CreateCheckBox} 0 70 100% 15 "Run configuration wizard (create or import ircbot.conf)"
  Pop $hConfigWizard
  ${NSD_SetState} $hConfigWizard 0

  nsDialogs::Show
FunctionEnd

Function ConfigPageLeave
  ${NSD_GetState} $hConfigWizard $RunWizard
FunctionEnd

Section "RadioBot" sec_main
  SetOutPath "$INSTDIR"
  SetDetailsPrint none
  File /r "${PAYLOADDIR}\*"
  SetDetailsPrint both

  ; Optional: run the ConfigWizard GUI to create or import ircbot.conf.
  ; Silent installs skip this; the wizard is installed as ConfigWizard.exe.
  IfSilent skip_wizard
  ${If} $RunWizard == 1
    IfFileExists "$INSTDIR\ConfigWizard.exe" 0 skip_wizard
    ExecWait '"$INSTDIR\ConfigWizard.exe" -o "$INSTDIR\ircbot.conf"'
  ${EndIf}
skip_wizard:

  WriteUninstaller "$INSTDIR\uninst.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RadioBot" "DisplayName" "RadioBot"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RadioBot" "UninstallString" '"$INSTDIR\uninst.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RadioBot" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RadioBot" "Publisher" "Drift Solutions"

  CreateDirectory "$SMPROGRAMS\RadioBot"
  CreateShortCut "$SMPROGRAMS\RadioBot\RadioBot.lnk" "$INSTDIR\RadioBot.exe"
  CreateShortCut "$SMPROGRAMS\RadioBot\RadioBot Shell.lnk" "$INSTDIR\RadioBot_Shell.exe"
  CreateShortCut "$SMPROGRAMS\RadioBot\Uninstall RadioBot.lnk" "$INSTDIR\uninst.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\uninst.exe"
  RMDir /r /REBOOTOK "$INSTDIR"
  RMDir /r /REBOOTOK "$SMPROGRAMS\RadioBot"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RadioBot"
  DeleteRegKey HKLM "Software\RadioBot"
SectionEnd
