#!/usr/bin/env python3
"""
Virtual serial port bridge for UART simulation.
Replaces socat for connecting picocom to Verilog testbench.

Usage:
    Terminal 1: python3 uart_bridge.py
    Terminal 2: picocom -b 115200 /tmp/uart_pty
    Terminal 3: vvp execution2_tb.vvp
"""

import os
import pty
import select
import tty

# File paths that the Verilog testbench will use
SP_FILE = "/tmp/vserial_sp"  # Simulation writes here, we read
PS_FILE = "/tmp/vserial_ps"  # Simulation reads from here, we write
PTY_LINK = "/tmp/uart_pty"   # Symlink to actual PTY device

def setup_pty():
    """Create a pseudo-terminal for picocom to connect to."""
    # A PTY is a pair of virtual devices: a master and a slave.
    # The slave behaves exactly like a real terminal device (/dev/tty* path, ioctl operations, etc.).
    # The master side is a file descriptor that the controlling program reads/writes.
    #
    # Anything written to the master appears on the slave and vice versa
    master_fd, slave_fd = pty.openpty()
    slave_name = os.ttyname(slave_fd)

    # Set raw mode on slave (where picocom connects) - no line buffering, no echo
    tty.setraw(slave_fd)

    # Create/update symlink for consistent access
    try:
        os.remove(PTY_LINK)
    except FileNotFoundError:
        pass

    os.symlink(slave_name, PTY_LINK)

    return master_fd, slave_fd, slave_name

def reset_sim_files():
    """Create/reset the simulation communication files."""
    # Remove old files if they exist
    for filepath in [SP_FILE, PS_FILE]:
        try:
            os.remove(filepath)
        except FileNotFoundError:
            pass

    # Create empty files
    open(SP_FILE, 'w').close()
    open(PS_FILE, 'w').close()

    print(f"[Reset] {SP_FILE}")
    print(f"[Reset] {PS_FILE}")

def main():
    print("=" * 50)
    print("UART Bridge for Verilog Simulation")
    print("=" * 50)

    # Setup PTY for picocom
    pty_master, pty_slave, pty_name = setup_pty()
    print(f"\nPTY created: {pty_name}")
    print(f"Symlink: {PTY_LINK} -> {pty_name}")
    print(f"\nConnect with: picocom -b 115200 --omap crlf --imap lfcrlf --echo {PTY_LINK}")

    # Setup simulation file interface
    reset_sim_files()

    print("\nReady! Start your simulation now: vvp execution2_tb.vvp")
    print("Press Ctrl+C to stop.\n")

    sp_pos = 0

    try:
        while True:
            # Poll every 0.01s
            readable, _, _ = select.select([pty_master], [], [], 0.01)

            # Data from picocom -> simulation
            if pty_master in readable:
                try:
                    data = os.read(pty_master, 1024)
                    if data:
                        with open(PS_FILE, 'ab') as f:
                            f.write(data)
                            # Flushes application buffers to kernel
                            f.flush()
                            # Flushes kernel buffers to storage
                            os.fsync(f.fileno())
                except OSError as e:
                    print(f"[ERROR] PTY read failed: {e}")
                    break

            # At every poll interval check to see if we have simulation data
            # and write it to picocom
            #
            # Data from simulation -> picocom
            try:
                file_size = os.path.getsize(SP_FILE)
                if file_size > sp_pos:
                    with open(SP_FILE, 'rb') as f:
                        f.seek(sp_pos)
                        data = f.read(file_size - sp_pos)
                        if data:
                            os.write(pty_master, data)
                            sp_pos = file_size
            except OSError:
                pass

    except KeyboardInterrupt:
        print("\n\nShutting down bridge...")

    finally:
        # Cleanup
        os.close(pty_master)
        os.close(pty_slave)

        for filename in [SP_FILE, PS_FILE, PTY_LINK]:
            try:
                os.remove(filename)
            except:
                pass

        print("Bridge closed.")

if __name__ == "__main__":
    main()
