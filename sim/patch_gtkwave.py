#!/usr/bin/env python3

"""
Script to patch GTKWave C source files for Windows MinGW64 compilation.

This script replaces POSIX socket includes with Winsock equivalents
to allow GTKWave's UDP mouseover patch to compile seamlessly on Windows.
"""

import os
import sys


def patch_file(filepath: str) -> None:
    """
    Patch a single GTKWave C source file with Windows Socket headers.

    Parameters
    ----------
    filepath : str
        The absolute or relative path to the C source file to be patched.

    Returns
    -------
    None
    """
    if not os.path.exists(filepath):
        print(f"Skipping {filepath}, does not exist.")
        return
    with open(filepath, 'r') as f:
        content = f.read()
    # Handle globals.h: just add the headers
    if "globals.h" in filepath:
        winsock_headers = (
            "\n#include <winsock2.h>\n"
            "#include <ws2tcpip.h>\n"
        )
        content = winsock_headers + content.replace("#include <sys/socket.h>", "").replace("#include <arpa/inet.h>", "")
    # Handle main.c: inject WSAStartup safely at the beginning of main()
    elif "main.c" in filepath:
        content = content.replace("#include <sys/socket.h>", "").replace("#include <arpa/inet.h>", "")
        
        main_signature = "int main(int argc, char *argv[])\n{"
        injected_main = (
            "int main(int argc, char *argv[])\n{\n"
            "#ifdef _WIN32\n"
            "    WSADATA wsaData;\n"
            "    WSAStartup(MAKEWORD(2,2), &wsaData);\n"
            "#endif\n"
        )
        content = content.replace(main_signature, injected_main)
    else:
        # Just remove them from other files (like mouseover.c)
        content = content.replace("#include <sys/socket.h>", "").replace("#include <arpa/inet.h>", "")
    with open(filepath, 'w') as f:
        f.write(content)


def main() -> None:
    """
    Main entry point for patching GTKWave source files.

    Parameters
    ----------
    None

    Returns
    -------
    None
    """
    base_dir = "."
    patch_file(os.path.join(base_dir, "src/globals.h"))
    patch_file(os.path.join(base_dir, "src/main.c"))
    patch_file(os.path.join(base_dir, "src/mouseover.c"))
    print("GTKWave successfully patched for Windows Sockets!")


if __name__ == "__main__":
    main()
