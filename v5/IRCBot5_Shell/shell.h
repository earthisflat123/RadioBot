//@AUTOHEADER@BEGIN@
/**********************************************************************\
|                          ShoutIRC RadioBot                           |
|           Copyright 2004-2020 Drift Solutions / Indy Sams            |
|        More information available at https://www.shoutirc.com        |
|                                                                      |
|                    This file is part of RadioBot.                    |
|                                                                      |
|   RadioBot is free software: you can redistribute it and/or modify   |
| it under the terms of the GNU General Public License as published by |
|  the Free Software Foundation, either version 3 of the License, or   |
|                 (at your option) any later version.                  |
|                                                                      |
|     RadioBot is distributed in the hope that it will be useful,      |
|    but WITHOUT ANY WARRANTY; without even the implied warranty of    |
|     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the     |
|             GNU General Public License for more details.             |
|                                                                      |
|  You should have received a copy of the GNU General Public License   |
|  along with RadioBot. If not, see <https://www.gnu.org/licenses/>.   |
\**********************************************************************/
//@AUTOHEADER@END@

#define MEMLEAK
#include <drift/dsl.h>
#include <Windowsx.h>
#include "resource.h"
#include "../../Common/DriftWindowingToolkit/dwt.h"

// DSL no longer provides the old Titus_Buffer C++ class, but RadioBot_Shell
// only uses a small subset of it. This wrapper maps it to DSL_BUFFER.
class Titus_Buffer {
	DSL_BUFFER buf;
public:
	Titus_Buffer() { buffer_init(&buf, false); }
	~Titus_Buffer() { buffer_free(&buf); }
	char * Get() { return buf.data ? buf.data : (char *)""; }
	uint32 GetLen() { return (uint32)buf.len; }
	void Append(const char * ptr, int len) { buffer_append(&buf, ptr, len); }
	void RemoveFromBeginning(uint32 len) { buffer_remove_front(&buf, len); }
};

struct CONFIG {
	HINSTANCE hInstance;
	HWND mWnd;
	UINT trayCreated;
	HBRUSH logBG;
	char fnConf[MAX_PATH];
	bool manual_stop;

	T_SOCKET * lSock;
	T_SOCKET * cSock[2];
	int port;

	bool start_bot_at_startup;
	bool keep_bot_running;
	time_t startBotAt;

	struct {
		bool bot_running;
		HANDLE hStdOut;
		PROCESS_INFORMATION pi;
	} proc;
};
extern CONFIG config;

void AddTrayIcon();
void DelTrayIcon();
void UpdateBalloon(tchar * strTitle, tchar * strContent, int showfor);
