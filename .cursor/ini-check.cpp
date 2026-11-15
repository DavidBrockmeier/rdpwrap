/*
 * Loads res/rdpwrap.ini with the project's INI_FILE parser and checks a few
 * stable fields. This is the Linux stand-in for the Windows configuration
 * tool: it proves the parser reads the shipped configuration.
 */
#include "IniFile.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static wchar_t *to_wide(const char *path) {
	size_t length = strlen(path);
	wchar_t *wide = new wchar_t[length + 1];
	for (size_t i = 0; i < length; i++) {
		wide[i] = (unsigned char)path[i];
	}
	wide[length] = 0;
	return wide;
}

static int fail(const char *message) {
	fprintf(stderr, "ini-check: %s\n", message);
	return 1;
}

int main(int argc, char **argv) {
	if (argc != 2) {
		fprintf(stderr, "usage: ini-check <rdpwrap.ini>\n");
		return 2;
	}

	wchar_t *path = to_wide(argv[1]);
	INI_FILE ini(path);
	delete[] path;

	INI_VAR_STRING updated;
	if (!ini.GetVariableInSection((char *)"Main", (char *)"Updated", &updated)) {
		return fail("Main.Updated is missing");
	}
	printf("Main.Updated=%s\n", updated.Value);
	if (strlen(updated.Value) != 10 || updated.Value[4] != '-' || updated.Value[7] != '-') {
		return fail("Main.Updated is not YYYY-MM-DD");
	}

	char *section = (char *)"6.1.7601.17514";
	if (!ini.SectionExists(section)) {
		return fail("section 6.1.7601.17514 is missing");
	}

	INI_VAR_STRING code;
	if (!ini.GetVariableInSection(section, (char *)"DefPolicyCode.x64", &code)) {
		return fail("DefPolicyCode.x64 is missing");
	}
	printf("DefPolicyCode.x64=%s\n", code.Value);
	if (strcmp(code.Value, "CDefPolicy_Query_eax_rdi") != 0) {
		return fail("unexpected DefPolicyCode.x64");
	}

	INI_VAR_STRING single;
	if (!ini.GetVariableInSection(section, (char *)"SingleUserCode.x86", &single)) {
		return fail("SingleUserCode.x86 is missing");
	}
	printf("SingleUserCode.x86=%s\n", single.Value);
	if (strcmp(single.Value, "nop") != 0) {
		return fail("unexpected SingleUserCode.x86");
	}

	INI_VAR_BYTEARRAY nop;
	if (!ini.GetVariableInSection((char *)"PatchCodes", (char *)"nop", &nop)) {
		return fail("PatchCodes.nop is missing");
	}
	printf("PatchCodes.nop bytes=%u\n", (unsigned)nop.ArraySize);
	if (nop.ArraySize != 1 || (unsigned char)nop.Value[0] != 0x90) {
		return fail("PatchCodes.nop did not decode");
	}

	INI_VAR_DWORD sessions;
	if (!ini.GetVariableInSection(
			(char *)"SLPolicy",
			(char *)"TerminalServices-RemoteConnectionManager-AllowMultipleSessions",
			&sessions)) {
		return fail("AllowMultipleSessions is missing");
	}
	printf("AllowMultipleSessions=%u\n", (unsigned)sessions.ValueDec);
	if (sessions.ValueDec != 1) {
		return fail("AllowMultipleSessions is not 1");
	}

	printf("ini-check ok\n");
	return 0;
}
