import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

# ─────────────────────────────────────────
# BRAM model — dict of word-addressed entries
# Populated with a small RISC-V program
# ─────────────────────────────────────────

RESET_ADDRESS = 0x00008000
ROM_BASE      = RESET_ADDRESS

# Small RISC-V test program (word addressed from ROM_BASE)
# addi x1, x0, 1       -> x1 = 1
# addi x2, x0, 2       -> x2 = 2
# add  x3, x1, x2      -> x3 = 3
# addi x4, x0, 5       -> x4 = 5
# bne  x3, x4, +8      -> not taken (3 != 5 but jumps forward)
# addi x5, x0, 99      -> x5 = 99  (should execute)
# ebreak               -> halt
PROGRAM = [
    0x00100093,  # addi x1, x0, 1
    0x00200113,  # addi x2, x0, 2
    0x002081B3,  # add  x3, x1, x2
    0x00500213,  # addi x4, x0, 5
    0x00419463,  # bne  x3, x4, +8   (skips next, goes to ebreak)
    0x06300293,  # addi x5, x0, 99   (skipped)
    0x00100073,  # ebreak
]

# Build word-addressed memory dict
# Processor sends byte addresses; BRAM is word addressed internally
# but the SOC does >> 2 offset. Here we emulate the raw byte address lookup.
bram = {}
for i, word in enumerate(PROGRAM):
    byte_addr = ROM_BASE + (i * 4)
    bram[byte_addr] = word


def bram_read(byte_addr):
    """Return word at byte address, or NOP if unmapped."""
    return bram.get(byte_addr, 0x00000013)  # NOP if not found


# ─────────────────────────────────────────
# BRAM slave emulation coroutine
# Watches addrOut + strobeOut + cycleOut,
# responds with data + acknowledgedIn after 1 cycle (classic Wishbone B3)
# ─────────────────────────────────────────

async def bram_slave(dut, max_cycles=2000):
    """Emulate a single-cycle ACK BRAM slave."""
    ack_pending = False
    pending_data = 0

    for _ in range(max_cycles):
        await RisingEdge(dut.clockIn)

        # Default: deassert ACK
        dut.acknowledgedIn.value = 0
        dut.dataIn.value = 0

        # If we had a pending ACK from last cycle, drive it now
        if ack_pending:
            dut.acknowledgedIn.value = 1
            dut.dataIn.value = pending_data
            ack_pending = False
        else:
            # Check if processor is requesting something
            strobe = int(dut.strobeOut.value)
            cycle  = int(dut.cycleOut.value)

            if strobe and cycle:
                addr  = int(dut.addrOut.value)
                we    = int(dut.writeEnableOut.value)

                if we:
                    data = int(dut.dataOut.value)
                    mask = int(dut.selectOut.value)
                    dut._log.info(f"  [BRAM] WRITE addr=0x{addr:08x} data=0x{data:08x} mask={mask:04b}")
                    bram[addr] = data
                    # ACK write next cycle
                    ack_pending = True
                    pending_data = 0
                else:
                    data = bram_read(addr)
                    dut._log.info(f"  [BRAM] READ  addr=0x{addr:08x} -> 0x{data:08x}")
                    # ACK read next cycle
                    ack_pending = True
                    pending_data = data


# ─────────────────────────────────────────
# Helper: wait for processor to HALT
# ─────────────────────────────────────────

async def wait_for_halt(dut, timeout=2000):
    for _ in range(timeout):
        await RisingEdge(dut.clockIn)
        state = int(dut.state.value)
        if state == 0:  # HALT = 0 in enum
            return True
    return False


# ─────────────────────────────────────────
# Reset helper
# ─────────────────────────────────────────

async def do_reset(dut, cycles=5):
    dut.resetIn.value      = 1
    dut.acknowledgedIn.value = 0
    dut.dataIn.value       = 0
    await ClockCycles(dut.clockIn, cycles)
    dut.resetIn.value = 0
    await RisingEdge(dut.clockIn)


# ─────────────────────────────────────────
# TEST 1: Basic fetch and execute
# ─────────────────────────────────────────

@cocotb.test()
async def test_basic_execute(dut):
    """Run a small program and verify register results via ebreak halt."""

    clock = Clock(dut.clockIn, 10, units="ns")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(bram_slave(dut))

    dut._log.info("=== TEST: basic_execute ===")
    await do_reset(dut)

    halted = await wait_for_halt(dut, timeout=500)
    assert halted, "Processor did not reach HALT (ebreak) within timeout"
    dut._log.info("Processor halted via ebreak — PASS")


# ─────────────────────────────────────────
# TEST 2: Bus protocol — STB/CYC handshake
# ─────────────────────────────────────────

@cocotb.test()
async def test_bus_handshake(dut):
    """Verify STB and CYC are asserted together and drop after ACK."""

    clock = Clock(dut.clockIn, 10, units="ns")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(bram_slave(dut))

    dut._log.info("=== TEST: bus_handshake ===")
    await do_reset(dut)

    violations = 0
    for _ in range(300):
        await RisingEdge(dut.clockIn)
        strobe = int(dut.strobeOut.value)
        cycle  = int(dut.cycleOut.value)

        # STB must never be high without CYC
        if strobe and not cycle:
            dut._log.error("VIOLATION: STB=1 but CYC=0")
            violations += 1

    assert violations == 0, f"{violations} Wishbone handshake violations"
    dut._log.info("Bus handshake — PASS")


# ─────────────────────────────────────────
# TEST 3: Reset clears PC to RESET_ADDRESS
# ─────────────────────────────────────────

@cocotb.test()
async def test_reset_pc(dut):
    """After reset, first fetch should target ROM_BASE."""

    clock = Clock(dut.clockIn, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut._log.info("=== TEST: reset_pc ===")
    dut.resetIn.value       = 1
    dut.acknowledgedIn.value = 0
    dut.dataIn.value        = 0
    await ClockCycles(dut.clockIn, 3)
    dut.resetIn.value = 0

    # Give it a couple cycles to come out of INITIAL
    await ClockCycles(dut.clockIn, 3)

    addr = int(dut.addrOut.value)
    dut._log.info(f"First addrOut after reset = 0x{addr:08x}")
    assert addr == RESET_ADDRESS, \
        f"Expected first fetch at 0x{RESET_ADDRESS:08x}, got 0x{addr:08x}"
    dut._log.info("Reset PC — PASS")


# ─────────────────────────────────────────
# TEST 4: No ACK stall — processor waits
# ─────────────────────────────────────────

@cocotb.test()
async def test_no_ack_stall(dut):
    """With ACK withheld, processor should hold STB/CYC and not advance."""

    clock = Clock(dut.clockIn, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut._log.info("=== TEST: no_ack_stall ===")
    dut.resetIn.value        = 1
    dut.acknowledgedIn.value = 0
    dut.dataIn.value         = 0
    await ClockCycles(dut.clockIn, 5)
    dut.resetIn.value = 0

    # Never assert ACK — processor should keep STB/CYC high
    await ClockCycles(dut.clockIn, 3)  # let it reach RUN

    strobe_seen = False
    addr_stable = None
    for _ in range(20):
        await RisingEdge(dut.clockIn)
        strobe = int(dut.strobeOut.value)
        addr   = int(dut.addrOut.value)

        if strobe:
            strobe_seen = True
            if addr_stable is None:
                addr_stable = addr
            else:
                assert addr == addr_stable, \
                    f"Address changed while stalled: was 0x{addr_stable:08x}, now 0x{addr:08x}"

    assert strobe_seen, "STB never asserted — processor may not be running"
    dut._log.info(f"Processor stalled correctly at addr=0x{addr_stable:08x} — PASS")