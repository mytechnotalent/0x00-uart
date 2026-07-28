#!/usr/bin/env python3

"""
Daemon that listens to a patched GTKWave to display code disassembly listings.

This script synchronizes the GTKWave waveform viewer with an assembly listing
by listening for UDP packets containing Program Counter (PC) values and highlighting
the corresponding instruction in a terminal UI using curses.
"""

import argparse
import curses
import os
import re
import select
import signal
import socket
import subprocess
import sys
import time
from typing import Any

text_offset = 0


def parse_arguments() -> argparse.Namespace:
    """
    Parse command line arguments.

    Parameters
    ----------
    None

    Returns
    -------
    argparse.Namespace
        Parsed arguments.
    """
    parser = argparse.ArgumentParser(
        description="Daemon listening to GTKWave."
    )
    parser.add_argument("--file", required=False, type=str,
                        default="build/0x00-uart.lst")
    parser.add_argument("--kernel", required=False, type=str,
                        default="../listings/xous-kernel.lst")
    parser.add_argument("--port", required=False, type=int, default=6502)
    return parser.parse_args()


def load_file_lines(filepath: str) -> list[str]:
    """
    Load lines from a file.

    Parameters
    ----------
    filepath : str
        Path to the file.

    Returns
    -------
    list[str]
        List of strings from the file.
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.readlines()
    except FileNotFoundError:
        return []


def create_socket(port: int) -> socket.socket:
    """
    Create a UDP socket bound to localhost.

    Parameters
    ----------
    port : int
        Port number to bind.

    Returns
    -------
    socket.socket
        Bound UDP socket.
    """
    udp_socket = socket.socket(family=socket.AF_INET, type=socket.SOCK_DGRAM)
    udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        udp_socket.bind(("127.0.0.1", port))
    except OSError:
        kill_stale_instance(port)
        udp_socket.bind(("127.0.0.1", port))
    return udp_socket


def pids_on_port(port: int) -> list[int]:
    """
    Return the list of PIDs currently bound to the given UDP port.

    Parameters
    ----------
    port : int
        UDP port number to inspect.

    Returns
    -------
    list[int]
        Process IDs bound to the port (empty if none).
    """
    if sys.platform == "win32":
        try:
            out = subprocess.run(["netstat", "-ano"],
                                 capture_output=True, text=True).stdout
        except (OSError, subprocess.SubprocessError):
            return []
        pids = []
        for line in out.splitlines():
            if "UDP" not in line:
                continue
            if re.search(rf":{port}\s", line):
                parts = line.split()
                if parts and parts[-1].isdigit():
                    pids.append(int(parts[-1]))
        return pids
    try:
        out = subprocess.run(["lsof", "-nP", "-ti", f"UDP:{port}"],
                             capture_output=True, text=True).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    return [int(x) for x in out.split()]


def process_command_line(pid: int) -> str:
    """
    Return the full command line of a process.

    Parameters
    ----------
    pid : int
        Process ID to inspect.

    Returns
    -------
    str
        Full command line, or empty string if it cannot be read.
    """
    if sys.platform == "win32":
        try:
            out = subprocess.run(
                ["wmic", "process", "where", f"ProcessId={pid}",
                 "get", "CommandLine", "/value"],
                capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            return ""
        return out or ""
    try:
        out = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                             capture_output=True, text=True).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    return out or ""


def process_alive(pid: int) -> bool:
    """
    Check whether a process is still running.

    Parameters
    ----------
    pid : int
        Process ID to check.

    Returns
    -------
    bool
        True if the process is alive.
    """
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def kill_stale_instance(port: int) -> None:
    """
    Terminate any previously-running codezoom instance bound to the port.

    Parameters
    ----------
    port : int
        UDP port to check for a stale instance.
    """
    for pid in pids_on_port(port):
        if "codezoom.py" not in process_command_line(pid):
            continue
        print(f"Killing stale codezoom instance (PID {pid})...")
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(0.2)
            if process_alive(pid) and "codezoom.py" in process_command_line(pid):
                os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def configure_curses(stdscr: Any) -> None:
    """
    Configure the curses screen.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.

    Returns
    -------
    None
        No return.
    """
    curses.noecho()
    curses.cbreak()
    stdscr.keypad(True)
    stdscr.nodelay(True)


def parse_data(data: bytes) -> tuple[str, str, bool]:
    """
    Parse UDP packet data.

    Parameters
    ----------
    data : bytes
        Raw packet data.

    Returns
    -------
    tuple[str, str, bool]
        (string_value, region, is_address).
    """
    if len(data) < 2:
        return "", 'user', False
    strlen = data[1]
    string_val = data[2:2 + strlen].decode('utf-8', errors='replace')
    region = 'user'
    is_address = False
    
    # If it contains non-hex chars or is suspiciously long, it's not an address
    if not all(c in '0123456789abcdefABCDEFxX ' for c in string_val) or len(string_val) > 16:
        pass # Treat as raw text
    else:
        try:
            offset = int(string_val, 16)
            region = 'kernel' if offset >= 0xfd00_0000 else 'user'
            string_val = f"{offset:x}"
            is_address = True
        except ValueError:
            pass
            
    return string_val, region, is_address


def find_line_offset(text: list[str], string_val: str, is_address: bool) -> int:
    if is_address:
        search_str = (string_val + ":").lower()
        for index, line in enumerate(text):
            if line.lower().lstrip().startswith(search_str):
                return index
    else:
        # Ignore long binary strings from GTKWave formatting errors
        if all(c in '01xXzZ ' for c in string_val) and len(string_val) > 32:
            return -1
        search_str = string_val.lower().strip()
        if not search_str:
            return -1
        for index, line in enumerate(text):
            if search_str in line.lower():
                return index
    return -1


def render_lines(stdscr: Any, text: list[str], start_line: int, rows: int, offset: int) -> None:
    """
    Render lines to the curses screen.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.
    text : list[str]
        Lines of text to render.
    start_line : int
        Starting line index.
    rows : int
        Number of rows to render.
    offset : int
        Highlighted line offset.

    Returns
    -------
    None
        No return.
    """
    for i in range(rows - 1):
        line_idx = start_line + i
        if line_idx < len(text):
            line_content = text[line_idx].rstrip()
            try:
                stdscr.addstr(i, 0, line_content,
                              curses.A_REVERSE if line_idx == offset else 0)
            except curses.error:
                pass


def draw_region(stdscr: Any, rows: int, region: str, last_str: str = "") -> None:
    """
    Draw the region status line.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.
    rows : int
        Number of rows.
    region : str
        Region name.
    last_str : str
        Last received string.

    Returns
    -------
    None
        No return.
    """
    try:
        status = f"Region: {region} | Last UDP string: {last_str}".ljust(80)
        stdscr.addstr(rows - 1, 0, status, curses.A_REVERSE)
    except curses.error:
        pass


def update_screen(stdscr: Any, files: dict[str, list[str]], data: bytes) -> None:
    """
    Update the screen based on received data.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.
    files : dict[str, list[str]]
        Dictionary containing user and kernel region text.
    data : bytes
        Raw packet data.

    Returns
    -------
    None
        No return.
    """
    global text_offset
    string_val, region, is_address = parse_data(data)
    text = files[region]
    rows, _cols = stdscr.getmaxyx()

    new_offset = find_line_offset(text, string_val, is_address)
    if new_offset != -1:
        text_offset = new_offset

    start = text_offset - rows // 2 if text_offset > rows // 2 else 0
    stdscr.clear()
    render_lines(stdscr, text, start, rows, text_offset)
    draw_region(stdscr, rows, region, string_val)


def handle_socket(stdscr: Any, udp_socket: socket.socket, files: dict[str, list[str]]) -> None:
    """
    Handle socket read operations.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.
    udp_socket : socket.socket
        UDP socket.
    files : dict[str, list[str]]
        Dictionary of loaded files.

    Returns
    -------
    None
        No return.
    """
    readable, _writeable, _exceptional = select.select(
        [udp_socket], [], [], 0.1)
    if readable:
        data = readable[0].recv(64)
        if data and len(data) >= 2 and data[0] == 2:
            update_screen(stdscr, files, data)
    stdscr.refresh()


def handle_input(stdscr: Any) -> bool:
    """
    Handle user input.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.

    Returns
    -------
    bool
        True if quit requested, False otherwise.
    """
    try:
        key = stdscr.getkey()
        return key == 'q'
    except curses.error:
        return False
    except Exception:
        return False


def run_loop(stdscr: Any, udp_socket: socket.socket, files: dict[str, list[str]]) -> None:
    """
    Run the main event loop.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.
    udp_socket : socket.socket
        UDP socket.
    files : dict[str, list[str]]
        Dictionary of loaded files.

    Returns
    -------
    None
        No return.
    """
    while True:
        handle_socket(stdscr, udp_socket, files)
        if handle_input(stdscr):
            break


def main(stdscr: Any) -> None:
    """
    Main curses application entrypoint.

    Parameters
    ----------
    stdscr : Any
        Curses screen object.

    Returns
    -------
    None
        No return.
    """
    args = parse_arguments()
    configure_curses(stdscr)
    udp_socket = create_socket(args.port)
    files: dict[str, list[str]] = {'user': load_file_lines(
        args.file), 'kernel': load_file_lines(args.kernel)}
    
    # Draw initial screen so it doesn't look blank
    stdscr.clear()
    rows, _cols = stdscr.getmaxyx()
    render_lines(stdscr, files['user'], 0, rows, 0)
    draw_region(stdscr, rows, 'user', '(Waiting for first UDP packet)')
    stdscr.refresh()
    
    run_loop(stdscr, udp_socket, files)
    udp_socket.close()


if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        pass
    sys.exit(0)
