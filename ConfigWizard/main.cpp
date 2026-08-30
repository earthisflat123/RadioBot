//#@AUTOHEADER@BEGIN@
/**********************************************************************\
                          ShoutIRC RadioBot
           Copyright 2004-2020 Drift Solutions / Indy Sams
        More information available at https://www.shoutirc.com
                                                                      |
                    This file is part of RadioBot.                    |
                                                                      |
   RadioBot is free software: you can redistribute it and/or modify   |
 it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
                 (at your option) any later version.                  |
                                                                      |
     RadioBot is distributed in the hope that it will be useful,      |
    but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
             GNU General Public License for more details.
                                                                      |
  You should have received a copy of the GNU General Public License
  along with RadioBot. If not, see <https://www.gnu.org/licenses/>.
\**********************************************************************/
//@AUTOHEADER@END@

#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <shellapi.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shlobj.h>

#pragma comment(lib, "shell32.lib")
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include "resource.h"
#include "../Common/DriftWindowingToolkit/dwt.h"

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "comdlg32.lib")

using namespace std;

#define MAX_VALUE 256
#define MAX_CONFIG 8192

static char s_outPath[MAX_PATH] = "ircbot.conf";

static void CopyArg(char * dest, size_t destSize, const char * src) {
    if (!src || !*src) { dest[0] = 0; return; }
    size_t i = 0;
    while (i + 1 < destSize && src[i]) {
        dest[i] = src[i];
        i++;
    }
    dest[i] = 0;
}

static void ParseCommandLine() {
    int argc;
    LPWSTR * argvW = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argvW) {
        for (int i = 1; i < argc - 1; i++) {
            if (!_wcsicmp(argvW[i], L"-o")) {
                char buf[MAX_PATH];
                int n = WideCharToMultiByte(CP_ACP, 0, argvW[i + 1], -1, buf, sizeof(buf), NULL, NULL);
                if (n > 0) {
                    CopyArg(s_outPath, sizeof(s_outPath), buf);
                }
                break;
            }
        }
        LocalFree(argvW);
    }
}

static int GetDlgItemTextLen(HWND hWnd, int id, char * buf, int size) {
    HWND hEdit = GetDlgItem(hWnd, id);
    return GetWindowTextA(hEdit, buf, size);
}

static int GetDlgItemIntValue(HWND hWnd, int id) {
    char buf[32] = {0};
    GetDlgItemTextLen(hWnd, id, buf, sizeof(buf));
    return atoi(buf);
}

static bool WriteConfig(HWND hWnd) {
    char nick[MAX_VALUE] = {0};
    char ircHost[MAX_VALUE] = {0};
    char ircPort[32] = {0};
    bool ircSsl = (IsDlgButtonChecked(hWnd, IDC_IRC_SSL) == BST_CHECKED);
    char ircChan[MAX_VALUE] = {0};
    char scType[MAX_VALUE] = {0};
    char scHost[MAX_VALUE] = {0};
    char scPort[32] = {0};
    char scUser[MAX_VALUE] = {0};
    char scPass[MAX_VALUE] = {0};
    char scMount[MAX_VALUE] = {0};
    char scStreamID[32] = {0};

    GetDlgItemTextLen(hWnd, IDC_NICK, nick, sizeof(nick));
    GetDlgItemTextLen(hWnd, IDC_IRC_HOST, ircHost, sizeof(ircHost));
    GetDlgItemTextLen(hWnd, IDC_IRC_PORT, ircPort, sizeof(ircPort));
    GetDlgItemTextLen(hWnd, IDC_IRC_CHAN, ircChan, sizeof(ircChan));

    HWND hType = GetDlgItem(hWnd, IDC_SC_TYPE);
    int sel = (int)SendMessageA(hType, CB_GETCURSEL, 0, 0);
    if (sel == CB_ERR) sel = 0;
    SendMessageA(hType, CB_GETLBTEXT, sel, (LPARAM)scType);

    GetDlgItemTextLen(hWnd, IDC_SC_HOST, scHost, sizeof(scHost));
    GetDlgItemTextLen(hWnd, IDC_SC_PORT, scPort, sizeof(scPort));
    GetDlgItemTextLen(hWnd, IDC_SC_USER, scUser, sizeof(scUser));
    GetDlgItemTextLen(hWnd, IDC_SC_PASS, scPass, sizeof(scPass));
    GetDlgItemTextLen(hWnd, IDC_SC_MOUNT, scMount, sizeof(scMount));
    GetDlgItemTextLen(hWnd, IDC_SC_STREAMID, scStreamID, sizeof(scStreamID));

    // Basic validation
    if (nick[0] == 0 || ircHost[0] == 0 || ircChan[0] == 0 || scHost[0] == 0) {
        MessageBoxA(hWnd, "Bot nickname, IRC server, channel, and sound server hostname are required.", "Validation", MB_OK | MB_ICONERROR);
        return false;
    }

    int nIrcPort = atoi(ircPort);
    if (nIrcPort <= 0 || nIrcPort > 65535) nIrcPort = 6667;
    int nScPort = atoi(scPort);
    if (nScPort <= 0 || nScPort > 65535) nScPort = 8000;
    int nStreamID = atoi(scStreamID);
    if (nStreamID < 1) nStreamID = 1;

    char config[MAX_CONFIG] = {0};
    _snprintf(config, sizeof(config),
        "# RadioBot v5 Config File\r\n"
        "# Generated by RadioBot Windows installer\r\n"
        "\r\n"
        "// This is the Base Block, it is the basic bot configuration, and of course is necessary\r\n"
        "Base {\r\n"
        "    Nick %s\r\n"
        "    Fork 0\r\n"
        "    OnlineBackup 0\r\n"
        "    LogFile ircbot.log\r\n"
        "    SecsBetweenUpdates 30\r\n"
        "    DoSpam 1\r\n"
        "    DoOnjoin 1\r\n"
        "    DoTopic 1\r\n"
        "    AutoRegOnHello 0\r\n"
        "    EnableRequestSystem 1\r\n"
        "    EnableRating 1\r\n"
        "    AllowPMRequests 1\r\n"
        "    RemotePort 10001\r\n"
        "    PullNameFromAnyServer 0\r\n"
        "    MultiSoundServer 0\r\n"
        "    DJName Standard\r\n"
        "    SendQ 300\r\n"
        "    SSL_Cert ircbot.pem\r\n"
        "    BackupDays 14\r\n"
        "};\r\n"
        "\r\n"
        "// IRC Block\r\n"
        "IRC {\r\n"
        "    Server0 {\r\n"
        "        Host %s\r\n"
        "        Port %d\r\n"
        "        SSL %d\r\n"
        "        Channel0 {\r\n"
        "            Channel %s\r\n"
        "            DoSpam 1\r\n"
        "            DoOnjoin 1\r\n"
        "            DoTopic 1\r\n"
        "        };\r\n"
        "    };\r\n"
        "};\r\n"
        "\r\n"
        "// Stream Server Block\r\n"
        "SS {\r\n"
        "    Server0 {\r\n"
        "        Type %s\r\n"
        "        Host %s\r\n"
        "        Port %d\r\n"
        "        // StreamID only needed for Shoutcast v2, defaults to 1\r\n"
        "        StreamID %d\r\n"
        "        // Mount/User are only used for icecast, you don't have to fill them out for shoutcast\r\n"
        "        // Pass is only used for icecast and shoutcast2\r\n"
        "        Mount %s\r\n"
        "        User %s\r\n",
        nick, ircHost, nIrcPort, ircSsl ? 1 : 0, ircChan,
        scType, scHost, nScPort, nStreamID, scMount, scUser);

    size_t len = strlen(config);

    if (scPass[0]) {
        char passLine[320] = {0};
        _snprintf(passLine, sizeof(passLine), "        Pass %s\r\n", scPass);
        size_t passLen = strlen(passLine);
        if (len + passLen < sizeof(config) - 128) {
            strcat(config, passLine);
            len += passLen;
        }
    } else {
        const char * passComment = "#        Pass your_stream_password\r\n";
        size_t clen = strlen(passComment);
        if (len + clen < sizeof(config) - 128) {
            strcat(config, passComment);
            len += clen;
        }
    }

    const char * tail =
        "    };\r\n"
        "};\r\n"
        "\r\n"
        "Plugin {\r\n"
        "    Module0         plugins/TTS_Services.%soext%\r\n"
        "#    Module1         plugins/AutoDJ.%soext%\r\n"
        "#    Module1         plugins/SimpleDJ.%soext%\r\n"
        "#    Module1         plugins/SAM.%soext%\r\n"
        "#    Module2         plugins/DCC.%soext%\r\n"
        "    Module3         plugins/Welcome.%soext%\r\n"
        "};\r\n"
        "\r\n"
        "// Go to https://wiki.shoutirc.com/ for more information on available plugins and how to configure them\r\n"
        "// and other configuration options.\r\n";

    size_t tailLen = strlen(tail);
    if (len + tailLen >= sizeof(config)) {
        MessageBoxA(hWnd, "Configuration too large to write.", "Error", MB_OK | MB_ICONERROR);
        return false;
    }
    strcat(config, tail);

    FILE * fp = fopen(s_outPath, "wb");
    if (!fp) {
        MessageBoxA(hWnd, "Could not open output file for writing.", "Error", MB_OK | MB_ICONERROR);
        return false;
    }
    fwrite(config, 1, strlen(config), fp);
    fclose(fp);
    return true;
}

static bool ImportConfig(HWND hWnd) {
    char fileName[MAX_PATH] = {0};
    OPENFILENAMEA ofn = {0};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = hWnd;
    ofn.lpstrFilter = "ircbot.conf\0ircbot.conf\0All Files\0*.*\0";
    ofn.lpstrFile = fileName;
    ofn.nMaxFile = sizeof(fileName);
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    ofn.lpstrTitle = "Import existing ircbot.conf";
    if (!GetOpenFileNameA(&ofn)) {
        return false;
    }

    FILE * in = fopen(fileName, "rb");
    if (!in) {
        MessageBoxA(hWnd, "Could not open the selected file.", "Import Error", MB_OK | MB_ICONERROR);
        return false;
    }
    fseek(in, 0, SEEK_END);
    long size = ftell(in);
    fseek(in, 0, SEEK_SET);
    if (size < 0 || size > 1024 * 1024) {
        fclose(in);
        MessageBoxA(hWnd, "Selected file is too large or invalid.", "Import Error", MB_OK | MB_ICONERROR);
        return false;
    }
    char * buf = (char *)malloc(size + 1);
    if (!buf) { fclose(in); return false; }
    size_t r = fread(buf, 1, size, in);
    fclose(in);
    buf[r] = 0;

    FILE * out = fopen(s_outPath, "wb");
    if (!out) {
        free(buf);
        MessageBoxA(hWnd, "Could not open output file for writing.", "Error", MB_OK | MB_ICONERROR);
        return false;
    }
    fwrite(buf, 1, r, out);
    fclose(out);
    free(buf);
    return true;
}

static void InitControls(HWND hWnd) {
    HWND hType = GetDlgItem(hWnd, IDC_SC_TYPE);
    SendMessageA(hType, CB_ADDSTRING, 0, (LPARAM)"shoutcast");
    SendMessageA(hType, CB_ADDSTRING, 0, (LPARAM)"shoutcast2");
    SendMessageA(hType, CB_ADDSTRING, 0, (LPARAM)"icecast");
    SendMessageA(hType, CB_SETCURSEL, 0, 0);

    SetDlgItemTextA(hWnd, IDC_NICK, "RadioBot");
    SetDlgItemTextA(hWnd, IDC_IRC_HOST, "irc.example.com");
    SetDlgItemTextA(hWnd, IDC_IRC_PORT, "6667");
    SetDlgItemTextA(hWnd, IDC_IRC_CHAN, "#channel");
    SetDlgItemTextA(hWnd, IDC_SC_HOST, "stream.example.com");
    SetDlgItemTextA(hWnd, IDC_SC_PORT, "8000");
    SetDlgItemTextA(hWnd, IDC_SC_MOUNT, "/live");
    SetDlgItemTextA(hWnd, IDC_SC_STREAMID, "1");
}

WM_HANDLER(OnInit) {
    InitControls(hWnd);
    return TRUE;
}

WM_HANDLER(OnCommand) {
    if (HIWORD(wParam) == BN_CLICKED) {
        switch (LOWORD(wParam)) {
            case IDOK:
                if (WriteConfig(hWnd)) {
                    EndDialog(hWnd, IDOK);
                }
                return TRUE;
            case IDCANCEL:
                EndDialog(hWnd, IDCANCEL);
                return TRUE;
            case IDC_IMPORT:
                if (ImportConfig(hWnd)) {
                    EndDialog(hWnd, IDOK);
                }
                return TRUE;
        }
    }
    if (HIWORD(wParam) == CBN_SELCHANGE && LOWORD(wParam) == IDC_SC_TYPE) {
        HWND hType = GetDlgItem(hWnd, IDC_SC_TYPE);
        int sel = (int)SendMessageA(hType, CB_GETCURSEL, 0, 0);
        // Mountpoint only really applies to icecast, but we keep the field visible.
        (void)sel;
        return TRUE;
    }
    return FALSE;
}

WM_HANDLER(OnClose) {
    EndDialog(hWnd, IDCANCEL);
    return TRUE;
}

HANDLERS g_Handlers[] = {
    { WM_INITDIALOG, OnInit },
    { WM_COMMAND, OnCommand },
    { WM_CLOSE, OnClose },
    { 0, NULL }
};

INT_PTR CALLBACK DlgProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    return HandleMap(g_Handlers, hWnd, uMsg, wParam, lParam);
}

int __stdcall WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nShowCmd) {
    ParseCommandLine();

    INITCOMMONCONTROLSEX icc;
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_STANDARD_CLASSES | ICC_WIN95_CLASSES;
    InitCommonControlsEx(&icc);

    INT_PTR ret = DialogBoxParamA(hInstance, MAKEINTRESOURCEA(IDD_WIZARD), NULL, DlgProc, 0);
    return (ret == IDOK) ? 0 : 1;
}
